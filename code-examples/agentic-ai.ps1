#Requires -Version 5.1
#
# Agentic AI with Memgraph: runnable end-to-end example (Windows / PowerShell).
#
# This is the Windows counterpart of agentic-ai.sh and does exactly the same thing.
#
# Aligned with https://memgraph.com/agentic-ai : "Agents That Plan. Not Prompt."
# An agent models its problem as a REASONING GRAPH and plans by traversal instead
# of by prompting:
#   - nodes      = states / decision points
#   - edges      = available actions
#   - properties = scores (expected value, success rate, feasibility)
# The traversed path is an inspectable, auditable trace; alternatives are scored
# and compared. Four graph operations replace LLM guesswork:
#   1. Weighted traversal  - evaluate multi-step plans without LLM calls
#   2. Shortest path       - most efficient route to a goal
#   3. Centrality          - find the critical intermediate states
#   4. Community detection - group related sub-tasks for parallel execution
#
# The page also stresses MULTI-AGENT coordination over SHARED STATE. That shared
# layer is Memgraph Zero / MemGQL: a federated GQL engine (one Bolt + GQL
# endpoint) in front of many backends, so a fleet of agents reaches the same data
# without ETL. Here MemGQL federates:
#   - Memgraph   : the reasoning graph the agents PLAN over (+ MAGE algorithms)
#   - PostgreSQL : customer records the agents pull as shared context
# Graph-native planning (MAGE, weighted shortest path) runs in Memgraph directly;
# MemGQL gives every agent one endpoint to that shared state plus other sources.
#
# Uses ONLY the Memgraph ecosystem (+ stock postgres, one of Zero's connectors):
#   memgraph/memgraph-mage, memgraph/memgql, memgraph/mgconsole, postgres
#
# Requirements: Docker Desktop only. No API keys.
#   Docker Desktop: https://docs.docker.com/desktop/install/windows-install/
#   The script bind-mounts two generated files into containers, so the drive this
#   script lives on must be shared with Docker Desktop (Settings > Resources >
#   File sharing; C:\Users is shared by default).
#
# Usage (PowerShell 5.1 or PowerShell 7+):
#   .\agentic-ai.ps1          # bring up the shared layer + reasoning graph, plan
#   .\agentic-ai.ps1 clean    # stop and remove everything this script created
#
# If Windows blocks the script, allow local scripts for this session first:
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('run', 'clean')]
    [string]$Command = 'run'
)

Set-StrictMode -Version 2.0
$LASTEXITCODE = 0
# Docker and mgconsole write progress/warnings to stderr, so exit codes (checked
# explicitly below), not stderr, decide success. Keep PowerShell from turning a
# native command's stderr into a terminating error.
if (Test-Path variable:PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$OutputEncoding = New-Object System.Text.UTF8Encoding $false
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }

# ---- Pinned versions --------------------------------------------------------
$MageImage      = 'memgraph/memgraph-mage:3.12.0'
$MemgqlImage    = 'memgraph/memgql:0.7.0'
$MgconsoleImage = 'memgraph/mgconsole:1.6.0'
$PostgresImage  = 'postgres:18'

# Demo-scoped names so this never collides with your own containers/networks.
$Net      = 'zero-demo-net'
$Memgraph = 'zero-demo-memgraph'
$Postgres = 'zero-demo-postgres'
$Memgql   = 'zero-demo-memgql'

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$Work      = Join-Path $ScriptDir '.memgql-work'

# ---- Helpers ----------------------------------------------------------------
function Write-Step {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host ''
    Write-Host "==> $Message" -ForegroundColor Cyan
}

# Invoke-Mg plans over the reasoning graph in Memgraph directly (port 7687, MAGE).
function Invoke-Mg {
    param([Parameter(Mandatory = $true)][string]$Cypher)
    $Cypher | docker run -i --rm --network $Net $MgconsoleImage --host $Memgraph --port 7687
    if ($LASTEXITCODE -ne 0) { throw "mgconsole (Memgraph) exited with code $LASTEXITCODE" }
}

# Invoke-Memgql is the shared, federated endpoint every agent connects to (7688).
function Invoke-Memgql {
    param([Parameter(Mandatory = $true)][string]$Cypher)
    $Cypher | docker run -i --rm --network $Net $MgconsoleImage --host $Memgql --port 7688
    if ($LASTEXITCODE -ne 0) { throw "mgconsole (MemGQL) exited with code $LASTEXITCODE" }
}

function Test-Bolt {
    # Silent probe against either endpoint, used for the readiness loops.
    param([Parameter(Mandatory = $true)][string]$MgHost, [Parameter(Mandatory = $true)][string]$Port)
    'RETURN 1;' | docker run -i --rm --network $Net $MgconsoleImage --host $MgHost --port $Port *> $null
    return ($LASTEXITCODE -eq 0)
}

function ConvertTo-DockerPath {
    # Docker Desktop accepts forward-slash Windows paths (C:/Users/... ) in -v.
    param([Parameter(Mandatory = $true)][string]$Path)
    return ($Path -replace '\\', '/')
}

function Write-Utf8NoBom {
    # No BOM: a BOM would break the psql init script and the JSON mapping.
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Content)
    $lf = $Content -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($Path, $lf, (New-Object System.Text.UTF8Encoding $false))
}

function Remove-Demo {
    Write-Step 'Stopping and removing containers + network + work dir'
    docker rm -f $Memgql $Memgraph $Postgres *> $null
    docker network rm $Net *> $null
    $global:LASTEXITCODE = 0   # nothing to remove is not a failure
    if (Test-Path -LiteralPath $Work) { Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue }
    Write-Host 'Cleaned up.'
}

if ($Command -eq 'clean') {
    Remove-Demo
    exit 0
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error 'Docker is required: https://docs.docker.com/desktop/install/windows-install/'
    exit 1
}

# ---- Reset any previous run -------------------------------------------------
docker rm -f $Memgql $Memgraph $Postgres *> $null
docker network create $Net *> $null
$LASTEXITCODE = 0

# ---- Generate the Postgres seed + the relational->graph mapping -------------
New-Item -ItemType Directory -Force -Path $Work -ErrorAction Stop | Out-Null

# Postgres source: customer records the agents pull as shared context.
$InitSql = Join-Path $Work 'init.sql'
Write-Utf8NoBom $InitSql @'
CREATE TABLE customers (id SERIAL PRIMARY KEY, name TEXT, tier TEXT);
CREATE TABLE companies (id SERIAL PRIMARY KEY, name TEXT);
CREATE TABLE works_at  (id SERIAL PRIMARY KEY, customer_id INT REFERENCES customers(id), company_id INT REFERENCES companies(id));

INSERT INTO customers (name, tier) VALUES ('Ada Lovelace', 'enterprise'), ('Linus T.', 'standard'), ('Grace H.', 'enterprise');
INSERT INTO companies (name)       VALUES ('Acme Corp'), ('Globex');
INSERT INTO works_at (customer_id, company_id) VALUES (1, 1), (2, 2), (3, 1);
'@

# MemGQL mapping: how the Postgres tables become graph nodes and edges.
$MappingJson = Join-Path $Work 'mapping.json'
Write-Utf8NoBom $MappingJson @'
{
  "nodes": [
    { "label": "Customer", "table": "customers", "id_column": "id", "properties": { "name": "name", "tier": "tier" } },
    { "label": "Company",  "table": "companies", "id_column": "id", "properties": { "name": "name" } }
  ],
  "edges": [
    { "rel_type": "WORKS_AT", "table": "works_at", "id_column": "id", "source_column": "customer_id", "target_column": "company_id", "source_label": "Customer", "target_label": "Company" }
  ]
}
'@

$WorkDocker = ConvertTo-DockerPath $Work

# ---- 1. Start the shared data layer (Memgraph + Postgres + MemGQL) ----------
# Backends are reached only by MemGQL over the internal network, so their ports
# are not published to the host, agents talk to the single MemGQL endpoint (7688).
Write-Step "Starting Memgraph backend ($MageImage) - hosts the reasoning graph"
docker run -d --name $Memgraph --network $Net `
    $MageImage --schema-info-enabled=True --log-level=TRACE --also-log-to-stderr *> $null
if ($LASTEXITCODE -ne 0) { throw 'Failed to start Memgraph.' }

Write-Step "Starting PostgreSQL backend ($PostgresImage) - hosts customer records"
docker run -d --name $Postgres --network $Net `
    -e POSTGRES_PASSWORD=postgres `
    -v "${WorkDocker}/init.sql:/docker-entrypoint-initdb.d/init.sql" `
    $PostgresImage *> $null
if ($LASTEXITCODE -ne 0) { throw 'Failed to start PostgreSQL.' }

Write-Step 'Waiting for Memgraph'
while (-not (Test-Bolt -MgHost $Memgraph -Port '7687')) { Start-Sleep -Seconds 1 }
Write-Step 'Waiting for PostgreSQL'
do {
    docker exec $Postgres pg_isready -U postgres *> $null
    $pgReady = ($LASTEXITCODE -eq 0)
    if (-not $pgReady) { Start-Sleep -Seconds 1 }
} while (-not $pgReady)

# If the bind mount did not take effect (a drive that is not shared with Docker
# Desktop), seed the same SQL through psql so the demo still works.
docker exec $Postgres psql -U postgres -d postgres -c 'SELECT 1 FROM customers LIMIT 1;' *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Step 'Seeding PostgreSQL through psql (the init.sql bind mount was not picked up)'
    Get-Content -LiteralPath $InitSql -Raw | docker exec -i $Postgres psql -U postgres -d postgres *> $null
    if ($LASTEXITCODE -ne 0) { throw 'Could not seed PostgreSQL.' }
}

# ---- 2. Seed the reasoning graph (states + scored actions) ------------------
# A customer-support agent's plan space: states are nodes, actions are edges, and
# each action carries a score (expected probability of resolving the ticket).
Write-Step 'Seeding the customer-support reasoning graph in Memgraph'
Invoke-Mg @'
MERGE (s0:State {name:"Ticket received"});
MERGE (s1:State {name:"Assess severity"});
MERGE (a:State  {name:"Auto-resolve"});
MERGE (e:State  {name:"Escalate to human"});
MERGE (r:State  {name:"Request more info"});
MERGE (d:State  {name:"Resolved"});
MATCH (s0:State{name:"Ticket received"}),(s1:State{name:"Assess severity"}) MERGE (s0)-[:ACTION {name:"triage",       score:1.0}]->(s1);
MATCH (s1:State{name:"Assess severity"}),(a:State{name:"Auto-resolve"})     MERGE (s1)-[:ACTION {name:"auto_resolve", score:0.87}]->(a);
MATCH (s1:State{name:"Assess severity"}),(e:State{name:"Escalate to human"})MERGE (s1)-[:ACTION {name:"escalate",     score:0.54}]->(e);
MATCH (s1:State{name:"Assess severity"}),(r:State{name:"Request more info"})MERGE (s1)-[:ACTION {name:"request_info", score:0.31}]->(r);
MATCH (a:State{name:"Auto-resolve"}),(d:State{name:"Resolved"})             MERGE (a)-[:ACTION {name:"close",        score:0.92}]->(d);
MATCH (e:State{name:"Escalate to human"}),(d:State{name:"Resolved"})        MERGE (e)-[:ACTION {name:"human_fix",    score:0.95}]->(d);
MATCH (r:State{name:"Request more info"}),(s1:State{name:"Assess severity"})MERGE (r)-[:ACTION {name:"reassess",     score:0.60}]->(s1);
'@

# ---- 3. Memgraph Zero: put MemGQL in front of both sources ------------------
Write-Step "Starting MemGQL ($MemgqlImage) - the shared federated endpoint (Bolt on 7688)"
docker run -d --name $Memgql --network $Net --stop-timeout 2 -p 7688:7688 `
    --env CONNECTOR_TYPE=multi `
    --env BOLT_LISTEN_ADDR=0.0.0.0:7688 `
    -v "${WorkDocker}/mapping.json:/data/mapping.json" `
    $MemgqlImage *> $null
if ($LASTEXITCODE -ne 0) { throw 'Failed to start MemGQL.' }

Write-Step 'Waiting for MemGQL'
while (-not (Test-Bolt -MgHost $Memgql -Port '7688')) { Start-Sleep -Seconds 1 }

Write-Step "Registering connectors: 'mg' (reasoning graph) and 'pg' (customer records)"
Invoke-Memgql @"
ADD CONNECTOR mg TYPE memgraph URI '${Memgraph}:7687' GRAPH memgraph;
CONNECT mg AS mg_conn;
ADD MAPPING social FROM '/data/mapping.json';
ADD CONNECTOR pg TYPE postgres URI 'host=${Postgres} user=postgres password=postgres dbname=postgres' MAPPING social;
CONNECT pg AS pg_conn;
"@

# ---- 4. Shared context: agents pull records through the one endpoint --------
# Multi-agent coordination: every agent reads the same federated layer. Here an
# agent fetches customer context from Postgres, through MemGQL, with no ETL.
Write-Step 'Agent reads shared context: enterprise customers (Postgres, via MemGQL)'
Invoke-Memgql @'
USE CONNECTION pg_conn
  MATCH (c:Customer)-[:WORKS_AT]->(co:Company)
  WHERE c.tier = 'enterprise'
  RETURN c.name AS customer, c.tier AS tier, co.name AS company
  ORDER BY customer;
'@

# ---- 5. Plan over the reasoning graph (no prompting) ------------------------
# These run natively in Memgraph (MAGE + weighted shortest path).
Write-Step 'Plan 1/4 - Weighted traversal: rank full resolution plans by expected value (no LLM)'
Invoke-Mg @'
MATCH path=(:State {name:"Ticket received"})-[rels:ACTION *1..6]->(:State {name:"Resolved"})
RETURN [n IN nodes(path) | n.name] AS plan,
       round(reduce(p=1.0, r IN rels | p * r.score) * 1000) / 1000 AS expected_value
ORDER BY expected_value DESC LIMIT 4;
'@

Write-Step 'Audit: chosen path vs the next-best alternative (inspectable trace)'
Invoke-Mg @'
MATCH path=(:State {name:"Ticket received"})-[rels:ACTION *1..6]->(:State {name:"Resolved"})
WITH [n IN nodes(path) | n.name] AS plan, reduce(p=1.0, r IN rels | p * r.score) AS ev
ORDER BY ev DESC LIMIT 2
RETURN plan, round(ev * 1000) / 1000 AS expected_value;
'@

Write-Step "Plan 2/4 - Shortest path: most efficient route to 'Resolved' (weighted, cost = 1 - score)"
Invoke-Mg @'
MATCH path=(:State {name:"Ticket received"})-[:ACTION *WSHORTEST (e, n | 1.0 - e.score) total_cost]->(:State {name:"Resolved"})
RETURN [x IN nodes(path) | x.name] AS route, round(total_cost * 1000) / 1000 AS cost;
'@

Write-Step 'Plan 3/4 - Centrality: the critical intermediate state (MAGE betweenness)'
Invoke-Mg @'
CALL betweenness_centrality.get() YIELD node, betweenness_centrality
RETURN node.name AS state, round(betweenness_centrality * 1000) / 1000 AS centrality
ORDER BY centrality DESC LIMIT 5;
'@

Write-Step 'Plan 4/4 - Community detection: sub-tasks that can run in parallel (MAGE)'
Invoke-Mg @'
CALL community_detection.get() YIELD node, community_id
RETURN community_id, collect(node.name) AS states
ORDER BY community_id;
'@

# ---- Wrap up ----------------------------------------------------------------
Write-Host ''
Write-Host "$([char]0x2713) Agents planned over the reasoning graph on a shared data layer." -ForegroundColor Green
Write-Host @"

The plan was chosen by traversal, not prompting: "Ticket received -> Assess
severity -> Auto-resolve -> Resolved" scored highest (expected value 0.8), and
the whole path is an auditable trace you can compare against alternatives.

Every agent reaches the same state through one endpoint (bolt://localhost:7688):
the reasoning graph (Memgraph) and customer records (Postgres), federated with no
ETL. Connect any Bolt tool to explore it (Memgraph Lab, mgconsole, a driver):
  docker run -d --name memgql-lab --network $Net -p 3000:3000 -e QUICK_CONNECT_MG_HOST=$Memgql -e QUICK_CONNECT_MG_PORT=7688 memgraph/lab:3.12.0
  start http://localhost:3000

Give a fleet of agents MCP access to the shared layer (run the Memgraph MCP server
against bolt://localhost:7688; see agentic-graphrag.ps1 for a working setup):
  { "mcpServers": { "memgraph-zero": { "url": "http://localhost:8000/mcp/" } } }

Notes (MemGQL is early):
  - Native graph analytics (MAGE, weighted shortest path) run in Memgraph itself;
    MemGQL federates pattern queries and pushes them down to each source.
  - Authentication/authorization are not supported yet - keep this local.
  - MemGQL Community allows up to two simultaneous data sources.

Tear everything down:
  .\agentic-ai.ps1 clean
"@
