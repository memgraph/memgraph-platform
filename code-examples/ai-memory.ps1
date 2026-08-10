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
# follow-up with the client like last time") and recalls them by traversal --
# using the actual Context Graph packages a live coding-assistant plugin uses
# (github.com/memgraph/ai-toolkit/tree/main/context-graph), not a hand-rolled
# schema:
#   - sessions-graph : semantic memory  -- durable, user-owned facts
#   - actions-graph   : episodic memory -- timestamped session/action history
#   - skills-graph    : procedural memory -- named, reusable how-tos
#
# Requirements: Docker Desktop + Python 3.10-3.13.
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

# ---- Pinned version (avoid ':latest' drift) ---------------------------------
$MageImage = 'memgraph/memgraph-mage:3.12.0'

$Net      = 'aimemory-net'
$Db       = 'aimemory-memgraph'
$BoltPort = '7687'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Venv = Join-Path $ScriptDir '.ai-memory-venv'

# ---- Helpers ----------------------------------------------------------------
function Write-Step {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host ''
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Invoke-Cypher {
    # Run one or more Cypher statements against Memgraph and show the result,
    # reusing the mgconsole already bundled in the memgraph-mage image.
    param([Parameter(Mandatory = $true)][string]$Cypher)
    $Cypher | docker exec -i $Db mgconsole --host 127.0.0.1 --port $BoltPort
    if ($LASTEXITCODE -ne 0) { throw "mgconsole exited with code $LASTEXITCODE" }
}

function Test-Cypher {
    # Same, but silent: used to poll until Memgraph accepts Bolt connections.
    param([string]$Cypher = 'RETURN 1;')
    $Cypher | docker exec -i $Db mgconsole --host 127.0.0.1 --port $BoltPort *> $null
    return ($LASTEXITCODE -eq 0)
}

function Remove-Demo {
    Write-Step 'Stopping and removing container + network'
    docker rm -f $Db *> $null
    docker network rm $Net *> $null
    if (Test-Path $Venv) { Remove-Item -Recurse -Force $Venv }
    $global:LASTEXITCODE = 0   # nothing to remove is not a failure
    Write-Host 'Cleaned up.'
}

# ---- clean subcommand -------------------------------------------------------
if ($Command -eq 'clean') {
    Remove-Demo
    exit 0
}

# ---- 0. Prerequisite checks --------------------------------------------------
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error 'Docker is required: https://docs.docker.com/desktop/install/windows-install/'
    exit 1
}

# Prefer the "py" launcher (the standard python.org install on Windows) asking
# it directly for an interpreter path, so $PyBin is always a single concrete
# executable regardless of which selector matched.
$PyBin = $null
if (Get-Command py -ErrorAction SilentlyContinue) {
    foreach ($verFlag in @('-3.13', '-3.12', '-3.11', '-3.10')) {
        $exe = & py $verFlag -c 'import sys; print(sys.executable)' 2>$null
        if ($LASTEXITCODE -eq 0 -and $exe) { $PyBin = $exe; break }
    }
}
if (-not $PyBin -and (Get-Command python -ErrorAction SilentlyContinue)) {
    $verOut = & python -c 'import sys;print("%d.%d"%sys.version_info[:2])' 2>$null
    if (@('3.10', '3.11', '3.12', '3.13') -contains $verOut) {
        $PyBin = (Get-Command python).Source
    }
}
if (-not $PyBin) {
    Write-Error 'Python 3.10-3.13 is required: https://www.python.org/downloads/'
    exit 1
}

# ---- 1. Spin up Memgraph (the memory store) ----------------------------------
Write-Step "Creating network + starting Memgraph ($MageImage)"
docker rm -f $Db *> $null
docker network create $Net *> $null
$LASTEXITCODE = 0

docker run -d --name $Db --network $Net `
    -p "${BoltPort}:7687" -p 7444:7444 `
    $MageImage --schema-info-enabled=True *> $null
if ($LASTEXITCODE -ne 0) { throw 'Failed to start Memgraph.' }

Write-Step 'Waiting for Memgraph to be ready (Bolt-aware check)'
while (-not (Test-Cypher)) { Start-Sleep -Seconds 1 }
Write-Host "Memgraph is up on bolt://localhost:${BoltPort}"

# ---- 2. Install the Context Graph memory packages ----------------------------
$pyVersion = & $PyBin --version
Write-Step "Creating a Python virtualenv ($pyVersion) and installing sessions-graph, actions-graph, skills-graph"
if (Test-Path $Venv) { Remove-Item -Recurse -Force $Venv }
& $PyBin -m venv $Venv
$VenvPython = Join-Path $Venv 'Scripts\python.exe'
if (-not (Test-Path $VenvPython)) { $VenvPython = Join-Path $Venv 'bin/python' }
& $VenvPython -m pip install --quiet --upgrade pip
& $VenvPython -m pip install --quiet sessions-graph actions-graph skills-graph memgraph-toolbox

# ---- 3. Write and recall the three memory types ------------------------------
Write-Step 'Writing and recalling semantic, episodic, and procedural memory'
$env:MEMGRAPH_URL = "bolt://localhost:${BoltPort}"
& $VenvPython (Join-Path $ScriptDir 'ai-memory.py')
$pyExit = $LASTEXITCODE
Remove-Item Env:\MEMGRAPH_URL
if ($pyExit -ne 0) { throw 'ai-memory.py failed.' }

# ---- 4. Inspect the memory ontology -------------------------------------------
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
The assistant can now answer "like last time" by traversing: semantic (Acme
Corp, New York) -> episodic (last session: follow-up meeting) -> procedural
(schedule-follow-up skill).

Explore the memory graph visually with Memgraph Lab:
  docker run -d --name aimemory-lab --network $Net -p 3000:3000 -e QUICK_CONNECT_MG_HOST=$Db -e QUICK_CONNECT_MG_PORT=7687 memgraph/lab:3.12.0
  start http://localhost:3000     # then run:  MATCH p=()-[]-() RETURN p;

Wire this into a REAL harness so it collects sessions automatically (no seeding
by hand): install the Context Graph plugin for Claude Code or Codex and point it
at this same Memgraph instance -- its defaults (bolt://localhost:7687, no auth,
database memgraph) already match this container.

  uv tool install agent-context-graph --with "skills-graph[agent-context-graph]"
  agent-context-graph bootstrap --runtime claude-code ``
    --connector skills-graph --connector actions-graph --connector sessions-graph
  agent-context-graph config set identity.user_id "your-name"

Every real session then writes Memory/Action/Skill nodes automatically, the
same nodes ai-memory.py just wrote by hand. Full walkthrough:
  https://github.com/memgraph/ai-toolkit/tree/main/context-graph

Tear everything down when you are done:
  .\ai-memory.ps1 clean
"@
