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
# Requirements -- two things you install once, yourself; the script checks for
# both up front and prints how to get them if they are missing:
#   - Docker Desktop   : https://docs.docker.com/desktop/install/windows-install/
#   - Python 3.10-3.13 : https://www.python.org/downloads/windows/
# Everything below that (the Memgraph image, the Python packages) the script
# installs on its own, into a throwaway virtualenv next to this file.
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

# Docker and mgconsole write progress/warnings to stderr, so exit codes (read
# through Get-ExitCode below), not stderr, decide success. Keep PowerShell from
# turning a native command's stderr into a terminating error.
if (Test-Path variable:PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}

# ---- Pinned versions (avoid ':latest' drift) --------------------------------
$MageImage = 'memgraph/memgraph-mage:3.12.0'
$LabImage = 'memgraph/lab:3.12.0'

$Net = 'aimemory-net'
$Db = 'aimemory-memgraph'
$Lab = 'aimemory-lab'
$BoltPort = '7687'
$PyWanted = @('3.13', '3.12', '3.11', '3.10')

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Venv = Join-Path $ScriptDir '.ai-memory-venv'

# ---- Helpers ----------------------------------------------------------------
# The engine stores a native command's exit code in the GLOBAL $LASTEXITCODE, so
# a bare "$LASTEXITCODE = 0" anywhere in a script creates a script-scoped copy
# that shadows it and freezes every later check at 0 -- silently disabling all
# error handling. Always read and reset it through these two helpers.
function Get-ExitCode {
    if (Test-Path variable:global:LASTEXITCODE) { return $global:LASTEXITCODE }
    return 0
}

function Reset-ExitCode {
    $global:LASTEXITCODE = 0
}

function Write-Step {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host ''
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Fatal {
    # A missing high-level dependency is not a bug to stack-trace: say what is
    # missing and exactly how to get it.
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [string[]]$Hints = @()
    )
    Write-Host ''
    Write-Host $Message -ForegroundColor Red
    foreach ($hint in $Hints) { Write-Host "  $hint" }
    Write-Host ''
    exit 1
}

function Invoke-Cypher {
    # Run one or more Cypher statements against Memgraph and show the result,
    # reusing the mgconsole already bundled in the memgraph-mage image.
    param([Parameter(Mandatory = $true)][string]$Cypher)
    $Cypher | docker exec -i $Db mgconsole --host 127.0.0.1 --port $BoltPort
    if ((Get-ExitCode) -ne 0) { throw "mgconsole exited with code $(Get-ExitCode)." }
}

function Test-Cypher {
    # Same, but silent: used to poll until Memgraph accepts Bolt connections.
    param([string]$Cypher = 'RETURN 1;')
    $Cypher | docker exec -i $Db mgconsole --host 127.0.0.1 --port $BoltPort *> $null
    return ((Get-ExitCode) -eq 0)
}

function Remove-Demo {
    Write-Step 'Stopping and removing container + network'
    docker rm -f $Db *> $null
    docker rm -f $Lab *> $null
    docker network rm $Net *> $null
    if (Test-Path $Venv) { Remove-Item -Recurse -Force $Venv }
    Reset-ExitCode   # nothing to remove is not a failure
    Write-Host 'Cleaned up.'
}

function Resolve-Python {
    # Prefer the "py" launcher (the standard python.org install on Windows),
    # asking it directly for an interpreter path so the result is always a
    # single concrete executable regardless of which selector matched.
    if (Get-Command py -ErrorAction SilentlyContinue) {
        foreach ($version in $PyWanted) {
            # 'py -3.x' reports a missing version on STDOUT ("Python 3.x not
            # found!") and exits non-zero, so check the exit code AND that the
            # path exists -- otherwise that message is taken for a python path.
            $exe = & py "-$version" -c 'import sys; print(sys.executable)' 2>$null |
                Select-Object -Last 1
            if ((Get-ExitCode) -eq 0 -and $exe -and (Test-Path -LiteralPath $exe)) {
                return $exe
            }
        }
    }
    # No launcher: fall back to whatever python is on PATH, if its version fits.
    # The Microsoft Store stub answers here too, but it exits non-zero.
    foreach ($name in @('python', 'python3')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if (-not $cmd) { continue }
        $version = & $name -c 'import sys;print("%d.%d"%sys.version_info[:2])' 2>$null |
            Select-Object -Last 1
        if ((Get-ExitCode) -eq 0 -and $PyWanted -contains $version) { return $cmd.Source }
    }
    return $null
}

# ---- clean subcommand -------------------------------------------------------
if ($Command -eq 'clean') {
    Remove-Demo
    exit 0
}

# ---- 0. Prerequisite checks --------------------------------------------------
# Only the two high-level dependencies are checked (never installed) here: a
# container engine and a language runtime are the user's call. The low-level
# dependencies -- the Memgraph image and the Python packages -- are installed
# automatically further down.
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Fatal 'Missing dependency: Docker (the memory store runs in a container).' @(
        'Install Docker Desktop: https://docs.docker.com/desktop/install/windows-install/',
        'Or from a terminal:     winget install --id Docker.DockerDesktop',
        'Then reopen PowerShell and re-run:  .\ai-memory.ps1'
    )
}

docker info *> $null
if ((Get-ExitCode) -ne 0) {
    Write-Fatal 'Docker is installed, but its engine is not responding.' @(
        'Start Docker Desktop and wait until it reports "Engine running",',
        'then re-run:  .\ai-memory.ps1'
    )
}

$PyBin = Resolve-Python
if (-not $PyBin) {
    Write-Fatal 'Missing dependency: Python 3.10-3.13 (runs the memory client).' @(
        'Install it: https://www.python.org/downloads/windows/',
        'Or:         winget install --id Python.Python.3.12',
        'Tick "Add python.exe to PATH" in the installer, then reopen PowerShell',
        'so the new PATH is picked up, and re-run:  .\ai-memory.ps1'
    )
}

# Pipe plain UTF-8 into the containers, and render this script's own output
# correctly on older consoles. The no-BOM encodings matter: on a UTF-8 console
# (chcp 65001) the defaults carry a byte-order mark, and PowerShell 5.1 writes it
# straight into mgconsole's stdin, which then rejects every query with "wrong
# token at position 0". Saved and restored so the demo leaves no trace in the
# calling session.
$PriorOutputEncoding = $global:OutputEncoding
$PriorConsoleOutputEncoding = [Console]::OutputEncoding
$PriorConsoleInputEncoding = [Console]::InputEncoding
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false
$global:OutputEncoding = $Utf8NoBom
try { [Console]::OutputEncoding = $Utf8NoBom } catch { }
try { [Console]::InputEncoding = $Utf8NoBom } catch { }

try {
    # ---- 1. Spin up Memgraph (the memory store) ------------------------------
    Write-Step "Creating network + starting Memgraph ($MageImage)"
    docker rm -f $Db *> $null
    docker network create $Net *> $null
    Reset-ExitCode   # an already existing network is not a failure

    docker run -d --name $Db --network $Net `
        -p "${BoltPort}:7687" -p 7444:7444 `
        $MageImage --schema-info-enabled=True *> $null
    if ((Get-ExitCode) -ne 0) {
        throw "Failed to start Memgraph. Is something else listening on port ${BoltPort}?"
    }

    Write-Step 'Waiting for Memgraph to be ready (Bolt-aware check)'
    $deadline = (Get-Date).AddSeconds(120)
    while (-not (Test-Cypher)) {
        if ((Get-Date) -gt $deadline) {
            docker logs --tail 50 $Db
            throw 'Memgraph did not accept Bolt connections within 120s (logs above).'
        }
        Start-Sleep -Seconds 1
    }
    Write-Host "Memgraph is up on bolt://localhost:${BoltPort}"

    # ---- 2. Install the Context Graph memory packages ------------------------
    $pyVersion = & $PyBin --version 2>&1 | Select-Object -Last 1
    Write-Step "Creating a Python virtualenv ($pyVersion) and installing sessions-graph, actions-graph, skills-graph"
    if (Test-Path $Venv) { Remove-Item -Recurse -Force $Venv }
    & $PyBin -m venv $Venv
    if ((Get-ExitCode) -ne 0) { throw "Failed to create a virtualenv with $PyBin." }

    $VenvPython = Join-Path $Venv 'Scripts\python.exe'
    if (-not (Test-Path $VenvPython)) { throw "The virtualenv is missing its interpreter ($VenvPython)." }

    & $VenvPython -m pip install --quiet --upgrade pip
    if ((Get-ExitCode) -ne 0) { throw 'Failed to upgrade pip inside the virtualenv.' }
    & $VenvPython -m pip install --quiet sessions-graph actions-graph skills-graph memgraph-toolbox
    if ((Get-ExitCode) -ne 0) { throw 'Failed to install the Context Graph packages from PyPI.' }

    # ---- 3. Write and recall the three memory types --------------------------
    Write-Step 'Writing and recalling semantic, episodic, and procedural memory'
    $env:MEMGRAPH_URL = "bolt://localhost:${BoltPort}"
    try {
        & $VenvPython (Join-Path $ScriptDir 'ai-memory.py')
        if ((Get-ExitCode) -ne 0) { throw "ai-memory.py exited with code $(Get-ExitCode)." }
    } finally {
        Remove-Item Env:\MEMGRAPH_URL -ErrorAction SilentlyContinue
    }

    # ---- 4. Inspect the memory ontology --------------------------------------
    Write-Step 'Memory ontology via SHOW SCHEMA INFO (returned in constant time)'
    try {
        Invoke-Cypher 'SHOW SCHEMA INFO;'
    } catch {
        Write-Host '(enable with --schema-info-enabled, already set)'
    }
} catch {
    Write-Host ''
    Write-Host "x $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Container logs:  docker logs $Db"
    Write-Host 'Start over with: .\ai-memory.ps1 clean'
    Write-Host ''
    exit 1
} finally {
    $global:OutputEncoding = $PriorOutputEncoding
    try { [Console]::OutputEncoding = $PriorConsoleOutputEncoding } catch { }
    try { [Console]::InputEncoding = $PriorConsoleInputEncoding } catch { }
}

# ---- Wrap up ----------------------------------------------------------------
Write-Host ''
Write-Host "$([char]0x2713) AI memory is live." -ForegroundColor Green
Write-Host @"
The assistant can now answer "like last time" by traversing: semantic (Acme
Corp, New York) -> episodic (last session: follow-up meeting) -> procedural
(schedule-follow-up skill).

Explore the memory graph visually with Memgraph Lab:
  docker run -d --name $Lab --network $Net -p 3000:3000 -e QUICK_CONNECT_MG_HOST=$Db -e QUICK_CONNECT_MG_PORT=7687 $LabImage
  start http://localhost:3000     # then run:  MATCH p=()-[]-() RETURN p;

Wire this into a REAL harness so it collects sessions automatically (no seeding
by hand). One script installs and wires the Context Graph plugin for Claude
Code or Codex end to end, defaulting to this same Memgraph instance
(bolt://localhost:$BoltPort, no auth, database memgraph) -- run it from WSL or
Git Bash (no native PowerShell port yet):

  curl -fsSL https://raw.githubusercontent.com/memgraph/ai-toolkit/main/context-graph/scripts/install.sh | bash
  # Codex instead of Claude Code:
  CONTEXT_GRAPH_RUNTIME=codex bash -c "`$(curl -fsSL https://raw.githubusercontent.com/memgraph/ai-toolkit/main/context-graph/scripts/install.sh)"

It registers the runtime's plugin marketplace, installs the plugin (the step a
bare 'agent-context-graph bootstrap' can't do -- that's what wires hooks into
the runtime), installs the CLI with all three connectors, sets your identity
(defaults to your git user.name; override with AGENT_CONTEXT_GRAPH_USER_ID),
and verifies with doctor. Full env var list and defaults:
  https://github.com/memgraph/ai-toolkit/tree/main/context-graph#getting-started-claude-code-or-codex

Every real session then writes Memory/Action/Skill nodes automatically, the
same nodes ai-memory.py just wrote by hand.

Tear everything down when you are done:
  .\ai-memory.ps1 clean

If you ran the installer above, mind the order: the plugin keeps writing to
whatever answers on bolt://localhost:$BoltPort, which is this container. Removing it
leaves the hooks with nowhere to write. Either hold off until you are done with
the plugin, or re-run install.sh afterwards -- with nothing reachable it starts
a Memgraph of its own on the same port.
"@
