#Requires -Version 5.1
#
# AI Memory with Memgraph: runnable end-to-end example (Windows / PowerShell).
#
# This is the Windows counterpart of ai-memory.sh and does exactly the same thing.
#
# Aligned with https://memgraph.com/ai-memory : "Vector Memory Forgets. Graphs
# Don't." Vector memory retrieves what *sounds* similar; a graph stores memory as
# entities and typed relationships you can traverse. Memgraph models three kinds
# of long-term memory as one unified graph an AI system can reason over:
#
#   1. Semantic memory   - what the system KNOWS       (facts, preferences)
#                          -> entities with typed relationships
#   2. Episodic memory   - what the system EXPERIENCED (past interactions, time)
#                          -> interaction nodes encoding sequence and consequence
#   3. Procedural memory - what the system KNOWS HOW TO DO (workflows)
#                          -> steps as nodes, transitions as edges
#
# The point is the interconnection: semantic fact -> episodic event -> procedural
# response. This script seeds all three for the page's own example ("Schedule a
# follow-up with the client like last time") and recalls them by traversal.
#
# Uses ONLY the Memgraph ecosystem (the "build custom" path from the page):
#   - memgraph/memgraph-mage : the graph database that stores the memory
#   - memgraph/mcp-memgraph  : the MCP server your harness loads to read/write it
#   - memgraph/mgconsole     : Memgraph's CLI, used here to seed + query memory
#
# Requirements: Docker Desktop only. No API keys, no Python.
#   Docker Desktop: https://docs.docker.com/desktop/install/windows-install/
#
# Usage (PowerShell 5.1 or PowerShell 7+):
#   .\ai-memory.ps1          # bring everything up, seed memory, run recall
#   .\ai-memory.ps1 clean    # stop and remove everything this script created
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

# Pipe UTF-8 (not the legacy code page) into the containers, and render the
# output of this script correctly on older consoles.
$OutputEncoding = New-Object System.Text.UTF8Encoding $false
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }

# ---- Pinned versions (avoid ':latest' drift) --------------------------------
$MageImage      = 'memgraph/memgraph-mage:3.12.0'
$McpImage       = 'memgraph/mcp-memgraph:0.2.0'
$MgconsoleImage = 'memgraph/mgconsole:1.6.0'

$Net      = 'aimemory-net'
$Db       = 'aimemory-memgraph'
$Mcp      = 'aimemory-mcp'
$BoltPort = '7687'
$McpPort  = '8000'

# ---- Helpers ----------------------------------------------------------------
function Write-Step {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host ''
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Invoke-Cypher {
    # Run one or more Cypher statements against Memgraph and show the result.
    param([Parameter(Mandatory = $true)][string]$Cypher)
    $Cypher | docker run -i --rm --network $Net $MgconsoleImage --host $Db --port $BoltPort
    if ($LASTEXITCODE -ne 0) { throw "mgconsole exited with code $LASTEXITCODE" }
}

function Test-Cypher {
    # Same, but silent: used to poll until Memgraph accepts Bolt connections.
    param([string]$Cypher = 'RETURN 1;')
    $Cypher | docker run -i --rm --network $Net $MgconsoleImage --host $Db --port $BoltPort *> $null
    return ($LASTEXITCODE -eq 0)
}

function Remove-Demo {
    Write-Step 'Stopping and removing containers + network'
    docker rm -f $Mcp $Db *> $null
    docker network rm $Net *> $null
    $global:LASTEXITCODE = 0   # nothing to remove is not a failure
    Write-Host 'Cleaned up.'
}

# ---- clean subcommand -------------------------------------------------------
if ($Command -eq 'clean') {
    Remove-Demo
    exit 0
}

# ---- 0. Prerequisite check --------------------------------------------------
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error 'Docker is required: https://docs.docker.com/desktop/install/windows-install/'
    exit 1
}

# ---- 1a. Spin up Memgraph (the memory store) --------------------------------
Write-Step "Creating network + starting Memgraph ($MageImage)"
docker rm -f $Db $Mcp *> $null
docker network create $Net *> $null
$LASTEXITCODE = 0

docker run -d --name $Db --network $Net `
    -p "${BoltPort}:7687" -p 7444:7444 `
    $MageImage --schema-info-enabled=True *> $null
if ($LASTEXITCODE -ne 0) { throw 'Failed to start Memgraph.' }

Write-Step 'Waiting for Memgraph to accept Bolt connections'
while (-not (Test-Cypher)) { Start-Sleep -Seconds 1 }
Write-Host "Memgraph is up on bolt://localhost:${BoltPort}"

# ---- 1b. Load the harness's memory tool (Memgraph MCP server) ---------------
# Your coding assistant / agent (the "harness") loads this MCP server as a tool.
# It then WRITES what it learns each session and READS it back later. Here we
# start the same server so a harness can attach; the seeding below simulates
# what the harness writes.
Write-Step "Starting the Memgraph MCP server ($McpImage), the memory tool your harness loads"
docker run -d --name $Mcp --network $Net `
    -p "${McpPort}:8000" `
    --env MEMGRAPH_URL="bolt://${Db}:7687" `
    $McpImage *> $null
if ($LASTEXITCODE -ne 0) { throw 'Failed to start the MCP server.' }
Write-Host "MCP server (streamable HTTP) at http://localhost:${McpPort}/mcp/"

# ---- 2. Write the three memory types ----------------------------------------
# Scenario from the page: the assistant has worked with a client before and knows
# how to schedule follow-ups. That knowledge is split across the three memories.
Write-Step 'Writing semantic, episodic, and procedural memory'
Invoke-Cypher @'
CREATE CONSTRAINT ON (c:Client) ASSERT c.name IS UNIQUE;

// --- Semantic memory: what the system KNOWS (facts + preferences) ---
MERGE (c:Client {name: "Acme Corp"}) SET c.contact = "Dana Lee", c.timezone = "America/New_York";
MERGE (p:Preference {kind: "meeting_length", value: "30 min"});
MATCH (c:Client {name:"Acme Corp"}), (p:Preference {kind:"meeting_length"})
  MERGE (c)-[:PREFERS]->(p);

// --- Episodic memory: what the system EXPERIENCED (interactions over time) ---
MERGE (m1:Interaction {id:"int-1", kind:"meeting", weekday:"Tuesday", duration:"30 min", when:"2026-06-30", summary:"kickoff"});
MERGE (m2:Interaction {id:"int-2", kind:"meeting", weekday:"Tuesday", duration:"30 min", when:"2026-07-07", summary:"follow-up"});
MATCH (m1:Interaction {id:"int-1"}), (c:Client {name:"Acme Corp"}) MERGE (m1)-[:WITH]->(c);
MATCH (m2:Interaction {id:"int-2"}), (c:Client {name:"Acme Corp"}) MERGE (m2)-[:WITH]->(c);
MATCH (m1:Interaction {id:"int-1"}), (m2:Interaction {id:"int-2"}) MERGE (m1)-[:NEXT]->(m2);  // sequence

// --- Procedural memory: what the system KNOWS HOW TO DO (a workflow) ---
MERGE (w:Workflow {name:"schedule_follow_up"});
MERGE (s1:Step {name:"book calendar slot"});
MERGE (s2:Step {name:"send invite"});
MATCH (w:Workflow {name:"schedule_follow_up"}), (s1:Step {name:"book calendar slot"}) MERGE (w)-[:STARTS_WITH]->(s1);
MATCH (s1:Step {name:"book calendar slot"}), (s2:Step {name:"send invite"}) MERGE (s1)-[:THEN]->(s2);  // transition
'@
Write-Host 'Wrote semantic + episodic + procedural memory.'

# ---- 3. Recall each memory type, then all three together --------------------
Write-Step "Semantic recall: 'What do we know about the client?'"
Invoke-Cypher @'
MATCH (c:Client {name:"Acme Corp"})-[:PREFERS]->(p:Preference)
RETURN c.contact AS client, c.timezone AS timezone, p.value AS preferred_length;
'@

Write-Step "Episodic recall: 'What happened last time?' (most recent interaction)"
Invoke-Cypher @'
MATCH (i:Interaction)-[:WITH]->(:Client {name:"Acme Corp"})
RETURN i.when AS date, i.weekday AS weekday, i.duration AS duration, i.summary AS summary
ORDER BY i.when DESC LIMIT 1;
'@

Write-Step "Procedural recall: 'How do we schedule a follow-up?' (steps in order)"
Invoke-Cypher @'
MATCH (:Workflow {name:"schedule_follow_up"})-[:STARTS_WITH]->(first:Step)
MATCH p=(first)-[:THEN*0..]->(s:Step)
WITH s, length(p) AS ord ORDER BY ord
RETURN collect(s.name) AS steps;
'@

Write-Step "Interconnected recall: 'Schedule a follow-up with the client like last time.'"
# One traversal joins semantic (client + timezone) + episodic (last meeting) +
# procedural (the workflow steps): semantic fact -> episodic event -> procedural response.
Invoke-Cypher @'
MATCH (c:Client {name:"Acme Corp"})
MATCH (last:Interaction)-[:WITH]->(c)
WITH c, last ORDER BY last.when DESC LIMIT 1
MATCH (:Workflow {name:"schedule_follow_up"})-[:STARTS_WITH]->(f:Step)
MATCH pth=(f)-[:THEN*0..]->(st:Step)
WITH c, last, st, length(pth) AS o ORDER BY o
RETURN c.contact AS client, c.timezone AS timezone,
       last.weekday AS like_last_time_day, last.duration AS duration,
       collect(st.name) AS actions;
'@

Write-Step 'Memory ontology via SHOW SCHEMA INFO (returned in constant time)'
try {
    Invoke-Cypher 'SHOW SCHEMA INFO;'
} catch {
    Write-Host '(enable with --schema-info-enabled, already set)'
}

# ---- Wrap up ----------------------------------------------------------------
Write-Host ''
Write-Host "$([char]0x2713) AI memory is live." -ForegroundColor Green
Write-Host @"
The assistant can now answer "like last time" by traversing: semantic (Acme Corp,
New York) -> episodic (last meeting: 30 min, Tuesday) -> procedural (book calendar
slot, send invite).

Explore the memory graph visually with Memgraph Lab:
  docker run -d --name aimemory-lab --network $Net -p 3000:3000 -e QUICK_CONNECT_MG_HOST=$Db -e QUICK_CONNECT_MG_PORT=7687 memgraph/lab:3.12.0
  start http://localhost:3000     # then run:  MATCH p=()-[]-() RETURN p;

Wire the memory into a real harness (so it collects sessions automatically).
Add this to your MCP client config (e.g. Claude Desktop / Cursor / VS Code):

  {
    "mcpServers": {
      "memgraph-memory": {
        "url": "http://localhost:${McpPort}/mcp/"
      }
    }
  }

Your assistant then calls the MCP tools (run_query, get_schema, ...) to write new
semantic/episodic/procedural memory and recall it, exactly as the seeding did.

Tear everything down when you are done:
  .\ai-memory.ps1 clean
"@
