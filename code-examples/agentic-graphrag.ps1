#Requires -Version 5.1
#
# Agentic GraphRAG with Memgraph: runnable end-to-end example (Windows / PowerShell).
#
# This is the Windows counterpart of agentic-graphrag.sh and does exactly the same
# thing.
#
# Story (from agentic-graphrag.md):
#   1. Spin up        -> a) Memgraph   b) the MCP server
#   2. Load / migrate -> data (this demo imports a knowledge graph)
#   3. Prompt         -> a) start your harness   b) load the skill and ask
#
# GraphRAG on Memgraph (see https://memgraph.com/graphrag) runs the whole
# retrieval pipeline as ONE atomic database operation. The page frames it as three
# pipeline types, each matched to a kind of question:
#   1. Text2Cypher                     -> Analytical questions ("how many ...")
#   2. Pivot search + relevance expand -> Local questions      ("what relates to X")
#   3. Query-focused summarisation     -> Global questions     ("main themes across")
#
# This script imports a knowledge graph and runs all three pipelines as atomic
# Cypher against it (Docker only, no key needed). It then, optionally, launches
# Memgraph's official *agentic* GraphRAG app, where an LLM agent classifies each
# question and picks the matching pipeline for you. The Memgraph MCP server is
# also started so your own harness (Claude Desktop, Cursor, VS Code) can query
# the same graph.
#
# Uses ONLY the Memgraph ecosystem:
#   memgraph/memgraph-mage  : the graph database (vector search + MAGE algorithms)
#   memgraph/mgconsole      : imports the dataset + runs the atomic pipelines
#   memgraph/mcp-memgraph   : the MCP server your harness loads as a tool
#   github.com/memgraph/ai-demos : the official agentic GraphRAG app (Streamlit)
#
# Requirements:
#   - Docker Desktop  https://docs.docker.com/desktop/install/windows-install/  (required, must be running)
#   - git             https://git-scm.com/download/win                          (required)
#   - For the OPTIONAL agentic app only:
#       Python 3.10-3.13 (https://www.python.org/downloads/windows/) and an
#       OpenAI API key:  $env:OPENAI_API_KEY = "sk-..."
#
# Usage (PowerShell 5.1 or PowerShell 7+):
#   .\agentic-graphrag.ps1          # import + run the three atomic pipelines
#                                    # (+ launch the agent app if OPENAI_API_KEY is set)
#   .\agentic-graphrag.ps1 clean    # stop containers and remove the work dir
#
# Or run it straight from the web (this does the same as the bare form above;
# `clean` needs the downloaded file, or the docker commands the script prints):
#   iwr -UseBasicParsing https://raw.githubusercontent.com/memgraph/memgraph-platform/main/code-examples/agentic-graphrag.ps1 | iex
#
# If Windows blocks the script, allow local scripts for this session first:
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('run', 'clean')]
    [string]$Command = 'run'
)

# The whole demo lives inside this one function on purpose, so the script behaves
# identically whether it is executed as a file or piped into Invoke-Expression
# (iwr ... | iex). Under `iex` there is no script to exit from, so a top-level
# `exit` tears down the caller's entire PowerShell session; inside a function we
# stop with `return` and let the entry point at the bottom translate that into a
# process exit code, but only when we were really started from a file. Nesting the
# helpers keeps them (and Set-StrictMode) out of the caller's session too.
function Invoke-AgenticGraphRagDemo {
    [CmdletBinding()]
    param(
        [ValidateSet('run', 'clean')]
        [string]$Command = 'run',
        [Parameter(Mandatory = $true)]
        [string]$BaseDir
    )

    Set-StrictMode -Version 2.0

    # Docker and git report progress on stderr. In Windows PowerShell that turns
    # into ErrorRecords as soon as a stream is redirected, so keep the preference
    # at Continue and judge success by exit code alone (cmdlets that must stop pass
    # -ErrorAction Stop explicitly).
    $ErrorActionPreference = 'Continue'

    # Assign $LASTEXITCODE through $global: only. A plain `$LASTEXITCODE = 0` inside
    # a function creates a function-local copy that native commands never update,
    # which would silently disable every exit-code check below.
    $global:LASTEXITCODE = 0

    # ---- Pinned versions ----------------------------------------------------
    $MageImage      = 'memgraph/memgraph-mage:3.12.0'   # version the demo targets
    $MgconsoleImage = 'memgraph/mgconsole:1.6.0'
    $McpImage       = 'memgraph/mcp-memgraph:0.2.0'

    $Net     = 'agenticgraphrag-net'
    $Db      = 'agenticgraphrag-memgraph'
    $Mcp     = 'agenticgraphrag-mcp'
    $McpPort = '8000'

    $Work   = Join-Path $BaseDir '.agentic-graphrag-work'
    $Repo   = Join-Path $Work 'ai-demos'
    $AppDir = Join-Path $Repo 'agentic-graph-rag\agentic'

    # Tailor the copy-pasteable hints to how this was actually started: someone who
    # piped us into `iex` has no .ps1 on disk to re-run or to pass `clean` to.
    $SourceUrl = 'https://raw.githubusercontent.com/memgraph/memgraph-platform/main/code-examples/agentic-graphrag.ps1'
    if ($PSCommandPath) {
        $Self      = '.\' + (Split-Path -Leaf $PSCommandPath)
        $RunHint   = $Self
        $CleanHint = "$Self clean"
    } else {
        $RunHint   = "iwr -UseBasicParsing $SourceUrl | iex"
        $CleanHint = "docker rm -f $Mcp $Db; docker network rm $Net; Remove-Item -Recurse -Force '$Work'"
    }

    # ---- Helpers ------------------------------------------------------------
    function Write-Step {
        param([Parameter(Mandatory = $true)][string]$Message)
        Write-Host ''
        Write-Host "==> $Message" -ForegroundColor Cyan
    }

    function Write-Fail {
        param([Parameter(Mandatory = $true)][string[]]$Message)
        Write-Host ''
        $Message | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    }

    function Invoke-Docker {
        # Run docker quietly, but on failure print what docker actually said.
        # Discarding its output with `*> $null` and then guessing at the cause is
        # how a Docker Hub pull timeout ends up reported as a port conflict.
        param(
            [Parameter(Mandatory = $true)][string]$What,
            [Parameter(Mandatory = $true)][string[]]$DockerArgs
        )
        $out = & docker @DockerArgs 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Fail (@("$What failed (docker exit $LASTEXITCODE):") +
                        ($out | ForEach-Object { "  $_" }))
            return $false
        }
        return $true
    }

    function Invoke-MgConsole {
        # Feed Cypher to mgconsole through a temp file and cmd-level redirection.
        #
        # Piping a PowerShell string straight into `docker run -i` reads better, but
        # PowerShell encodes native-command stdin with the console encoding, and on a
        # console running the UTF-8 code page (chcp 65001, or the "Use Unicode UTF-8"
        # option) that encoding emits a BOM. The BOM arrives in front of the first
        # statement and mgconsole rejects every query with "wrong token at position
        # 0" -- which silently turns the readiness loop below into an infinite wait.
        # Neither $OutputEncoding nor [Console]::OutputEncoding suppresses it, so
        # write the bytes ourselves and let cmd wire up stdin.
        param(
            [Parameter(Mandatory = $true)][string]$Cypher,
            [ValidateSet('Show', 'Quiet', 'Capture')][string]$Mode = 'Show'
        )
        $tmp = [System.IO.Path]::GetTempFileName()
        try {
            [System.IO.File]::WriteAllText($tmp,
                (($Cypher -replace "`r`n", "`n").TrimEnd() + "`n"),
                (New-Object System.Text.UTF8Encoding $false))
            $line = "docker run -i --rm --network $Net $MgconsoleImage --host $Db --port 7687 < `"$tmp`""
            if ($Mode -eq 'Quiet') {
                cmd /c $line *> $null
                return ($LASTEXITCODE -eq 0)
            }
            if ($Mode -eq 'Capture') {
                $out = cmd /c $line 2>$null
                return ($out -join "`n")
            }
            cmd /c $line
        } finally {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }

    function Invoke-Mg {
        # Run Cypher against Memgraph and show the result.
        param([Parameter(Mandatory = $true)][string]$Cypher)
        Invoke-MgConsole -Cypher $Cypher -Mode Show
        if ($LASTEXITCODE -ne 0) { throw "mgconsole exited with code $LASTEXITCODE" }
    }

    function Invoke-MgQuiet {
        # Run Cypher, discard output, report success (used for polling + bulk import).
        param([Parameter(Mandatory = $true)][string]$Cypher)
        return (Invoke-MgConsole -Cypher $Cypher -Mode Quiet)
    }

    function Get-MgText {
        # Run Cypher and capture the raw text output.
        param([Parameter(Mandatory = $true)][string]$Cypher)
        return (Invoke-MgConsole -Cypher $Cypher -Mode Capture)
    }

    function Remove-Tree {
        # rm -rf that also copes with git's read-only object files on Windows.
        param([Parameter(Mandatory = $true)][string]$Path)
        if (-not (Test-Path -LiteralPath $Path)) { return }
        Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
            ForEach-Object { try { $_.IsReadOnly = $false } catch { } }
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }

    function Remove-Demo {
        Write-Step 'Stopping containers, removing network + work dir'
        # Teardown must work even on a machine that no longer has Docker: the work
        # dir is still worth removing, and "nothing to remove" is not a failure.
        if (Get-Command docker -ErrorAction SilentlyContinue) {
            docker rm -f $Mcp $Db *> $null
            docker network rm $Net *> $null
            $global:LASTEXITCODE = 0
        }
        Remove-Tree $Work
        Write-Host 'Cleaned up.'
    }

    if ($Command -eq 'clean') {
        Remove-Demo
        return
    }

    # ---- 0. Prerequisites ----------------------------------------------------
    $missing = @()
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        $missing += '  docker : https://docs.docker.com/desktop/install/windows-install/'
    }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        $missing += '  git    : https://git-scm.com/download/win'
    }
    if ($missing.Count -gt 0) {
        Write-Fail (@('Missing prerequisites:') + $missing)
        $script:DemoExitCode = 1
        return
    }

    # Docker Desktop being installed but not started is the most common way this
    # demo fails. Catch it here, where the fix is obvious, instead of several steps
    # later with a misleading "Failed to start Memgraph".
    docker info *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Fail @(
            'Docker is installed but its engine is not responding.',
            'Start Docker Desktop, wait until it reports "Engine running", then re-run:',
            "  $RunHint")
        $script:DemoExitCode = 1
        return
    }

    # ---- Get the official demo ----------------------------------------------
    Write-Step 'Fetching the official Agentic GraphRAG demo (sparse clone of memgraph/ai-demos)'
    New-Item -ItemType Directory -Force -Path $Work -ErrorAction Stop | Out-Null
    if (-not (Test-Path -LiteralPath (Join-Path $Repo '.git'))) {
        git clone --depth 1 --filter=blob:none --sparse https://github.com/memgraph/ai-demos.git $Repo
        if ($LASTEXITCODE -ne 0) { throw 'git clone failed.' }
        git -C $Repo sparse-checkout set agentic-graph-rag/agentic
        if ($LASTEXITCODE -ne 0) { throw 'git sparse-checkout failed.' }
    }
    $Dataset = Join-Path $AppDir 'asknews-finance-graph.cypherl'
    if (-not (Test-Path -LiteralPath $Dataset)) { throw "Dataset not found at $Dataset" }

    # ---- Pull the images -----------------------------------------------------
    # `docker run` pulls implicitly, but its progress goes to stderr, so a first
    # run used to sit silent for minutes on a multi-GB download and a failed pull
    # surfaced later as a misleading "failed to start". Pull up front, visibly, and
    # retry: Docker Hub timeouts ("timeout awaiting response headers") are common
    # and a single retry usually clears them.
    foreach ($img in @($MageImage, $MgconsoleImage, $McpImage)) {
        docker image inspect $img *> $null
        if ($LASTEXITCODE -eq 0) { continue }
        Write-Step "Pulling $img (first run only, this can take a few minutes)"
        $pulled = $false
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            docker pull $img 2>&1 | ForEach-Object { Write-Host "  $_" }
            if ($LASTEXITCODE -eq 0) { $pulled = $true; break }
            if ($attempt -lt 3) {
                Write-Host "Pull attempt $attempt failed; retrying in 5s..." -ForegroundColor Yellow
                Start-Sleep -Seconds 5
            }
        }
        if (-not $pulled) {
            Write-Fail @(
                "Could not pull $img after 3 attempts.",
                'Check your connection to Docker Hub (a VPN or proxy is a common cause), then re-run:',
                "  $RunHint")
            $script:DemoExitCode = 1
            return
        }
    }

    # ---- 1a. Spin up Memgraph -----------------------------------------------
    Write-Step "Starting Memgraph ($MageImage) with schema info enabled"
    docker rm -f $Db $Mcp *> $null
    docker network create $Net *> $null
    $global:LASTEXITCODE = 0
    if (-not (Invoke-Docker -What 'Starting Memgraph' -DockerArgs @(
                'run', '-d', '--name', $Db, '--network', $Net,
                '-p', '7687:7687', '-p', '7444:7444',
                $MageImage, '--schema-info-enabled=True'))) {
        Write-Host "If a port is already taken, tear down the previous run with: $CleanHint" -ForegroundColor Yellow
        $script:DemoExitCode = 1
        return
    }

    # Bounded wait: an unbounded `while (-not ready)` loop turns any container that
    # dies at startup (or any query that can never succeed) into a script that hangs
    # forever with no explanation, so give up and show the container's logs.
    Write-Step 'Waiting for Memgraph to accept Bolt connections'
    $ready = $false
    for ($waited = 0; $waited -lt 120; $waited++) {
        if (Invoke-MgQuiet 'RETURN 1;') { $ready = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) {
        Write-Fail @('Memgraph did not accept Bolt connections within 120 seconds.',
                     "Last lines of '$Db' logs:")
        docker logs --tail 30 $Db 2>&1 | ForEach-Object { Write-Host "  $_" }
        $script:DemoExitCode = 1
        return
    }

    # ---- 2. Load the knowledge graph ----------------------------------------
    # mgconsole accepts a bounded amount of input per invocation, so the .cypherl is
    # streamed in batches (same approach as the demo's setup.sh, but over a Docker
    # network so it works the same on Linux, macOS, and Windows).
    $lines = [System.IO.File]::ReadAllLines($Dataset)
    Write-Step "Importing the AskNews finance knowledge graph ($($lines.Count) statements)"
    $batch = 300
    $failedBatches = 0
    for ($start = 0; $start -lt $lines.Count; $start += $batch) {
        $end = [Math]::Min($start + $batch - 1, $lines.Count - 1)
        if (-not (Invoke-MgQuiet (($lines[$start..$end]) -join "`n"))) { $failedBatches++ }
    }
    if ($failedBatches -gt 0) {
        # Don't stop: a partial graph still demonstrates the pipelines, but say so
        # rather than let the queries below quietly return thin results.
        Write-Host "Warning: $failedBatches import batch(es) failed; the graph is incomplete." -ForegroundColor Yellow
    }
    $nodes = [regex]::Match((Get-MgText 'MATCH (n) RETURN count(n);'), '\d+').Value
    if (-not $nodes -or $nodes -eq '0') {
        throw "Import produced no nodes. Check the dataset at $Dataset."
    }
    Write-Host "Imported. Memgraph now holds $nodes nodes."

    # ---- 1b. Spin up the MCP server -----------------------------------------
    # This is the "MCP" from the outline: your own harness can load it as a tool and
    # query the same graph, instead of (or alongside) the Streamlit app below.
    Write-Step "Starting the Memgraph MCP server ($McpImage)"
    if (-not (Invoke-Docker -What 'Starting the MCP server' -DockerArgs @(
                'run', '-d', '--name', $Mcp, '--network', $Net,
                '-p', "${McpPort}:8000",
                '--env', "MEMGRAPH_URL=bolt://${Db}:7687",
                $McpImage))) {
        Write-Host "If port $McpPort is already taken, free it or tear down with: $CleanHint" -ForegroundColor Yellow
        $script:DemoExitCode = 1
        return
    }
    # 'docker run -d' returns as soon as the container exists, several seconds
    # before the HTTP server inside it is listening. The endpoint below is meant
    # to be pasted straight into a harness, so wait for the server to say it is
    # up rather than advertising a port that still refuses connections.
    $mcpReady = $false
    for ($i = 0; $i -lt 30; $i++) {
        $running = (& docker inspect -f '{{.State.Running}}' $Mcp 2>&1)
        if ($LASTEXITCODE -ne 0 -or "$running".Trim() -ne 'true') { break }
        $logs = (& docker logs $Mcp 2>&1) -join "`n"
        if ($logs -match 'Application startup complete|Uvicorn running on') {
            $mcpReady = $true
            break
        }
        Start-Sleep -Seconds 1
    }
    $global:LASTEXITCODE = 0
    if ($mcpReady) {
        Write-Host "MCP endpoint: http://localhost:${McpPort}/mcp/"
    }
    else {
        # Not fatal: the three pipelines below talk to Memgraph directly, so the
        # demo is still worth watching without the MCP server.
        Write-Host 'Warning: the MCP server did not become ready; its recent logs:' -ForegroundColor Yellow
        & docker logs --tail 20 $Mcp 2>&1 | ForEach-Object { Write-Host "  $_" }
        $global:LASTEXITCODE = 0
        Write-Host 'Continuing - the pipelines below query Memgraph directly.' -ForegroundColor Yellow
    }

    # ---- 3. Run the three GraphRAG retrieval pipelines (atomic Cypher) -------
    # Each pipeline is ONE database operation, matching https://memgraph.com/graphrag.
    # The agentic app in step 4 just picks which of these to run for a given question.
    $Pivot = 'nvidia'   # the seed entity for the local pipeline

    Write-Step "Pipeline 1/3 - Text2Cypher (Analytical): 'What kinds of organizations are covered, and how many of each?'"
    # An analytical question becomes a single aggregating Cypher query.
    Invoke-Mg @'
MATCH (n:organization) WHERE n.detailed_type IS NOT NULL
RETURN n.detailed_type AS organization_type, count(*) AS count
ORDER BY count DESC LIMIT 8;
'@

    Write-Step "Pipeline 2/3 - Pivot search + relevance expansion (Local): 'What is connected to `"$Pivot`"?'"
    # Pivot on a seed entity, then expand the neighborhood (<=2 hops) in one traversal.
    # In production the pivot is a native vector search; here we pivot by name.
    Invoke-Mg @"
MATCH (seed {id: '$Pivot'})-[*1..2]-(context)
RETURN DISTINCT context.id AS related_entity, context.main_type AS type
LIMIT 10;
"@

    Write-Step "Pipeline 3/3 - Query-focused summarisation (Global): 'What are the most central themes overall?'"
    # A global question ranks the whole graph (PageRank, MAGE) to find themes an LLM
    # would then summarise.
    Invoke-Mg @'
CALL pagerank.get() YIELD node, rank
RETURN node.id AS theme, node.main_type AS type, round(rank * 10000) / 10000 AS importance
ORDER BY importance DESC LIMIT 10;
'@

    Write-Host ''
    Write-Host "$([char]0x2713) GraphRAG retrieval pipelines ran against $nodes nodes." -ForegroundColor Green
    Write-Host @"

Memgraph : bolt://localhost:7687   (knowledge graph loaded)
MCP      : http://localhost:${McpPort}/mcp/   (attach your own harness)

Point your own harness (Claude Desktop / Cursor / VS Code) at the graph with:
  { "mcpServers": { "memgraph": { "url": "http://localhost:${McpPort}/mcp/" } } }
"@

    # ---- 4. Optional: the official agentic app (LLM picks the pipeline) ------
    # Needs an OpenAI API key (raw OpenAI calls) and Python 3.10-3.13. The demo pins
    # deps (tiktoken, sentence-transformers) that only ship wheels for <=3.13; on 3.14+
    # pip would build from source and fail, so pick the newest compatible interpreter.
    $OpenAiKey = [Environment]::GetEnvironmentVariable('OPENAI_API_KEY')
    if ([string]::IsNullOrWhiteSpace($OpenAiKey)) {
        Write-Host @"

To also run the agentic app (an LLM agent that classifies each question and picks
one of the three pipelines above), set an OpenAI key and re-run:
  `$env:OPENAI_API_KEY = "sk-..."
  $RunHint

Tear everything down when you are done:
  $CleanHint
"@
        return
    }

    function Resolve-Python {
        # Prefer the newest interpreter the demo's pinned wheels support.
        $wanted = @('3.13', '3.12', '3.11', '3.10')
        if (Get-Command py -ErrorAction SilentlyContinue) {
            foreach ($ver in $wanted) {
                $out = & py "-$ver" -c "import sys; print('%d.%d' % sys.version_info[:2])" 2>$null
                if ($LASTEXITCODE -eq 0 -and $out) {
                    return [pscustomobject]@{ Exe = 'py'; Args = @("-$ver"); Version = "$out" }
                }
            }
        }
        foreach ($cmd in @('python', 'python3')) {
            if (Get-Command $cmd -ErrorAction SilentlyContinue) {
                $out = & $cmd -c "import sys; print('%d.%d' % sys.version_info[:2])" 2>$null
                if ($LASTEXITCODE -eq 0 -and ($wanted -contains "$out")) {
                    return [pscustomobject]@{ Exe = $cmd; Args = @(); Version = "$out" }
                }
            }
        }
        return $null
    }

    $py = Resolve-Python
    $global:LASTEXITCODE = 0
    if (-not $py) {
        Write-Host 'OPENAI_API_KEY is set but no Python 3.10-3.13 found for the agentic app.' -ForegroundColor Yellow
        Write-Host 'Install one (e.g. winget install Python.Python.3.13); the pipelines above already ran.' -ForegroundColor Yellow
        $script:DemoExitCode = 1
        return
    }

    Write-Step "Creating a Python virtualenv (Python $($py.Version)) and installing the demo's dependencies"
    Write-Host '(sentence-transformers pulls in PyTorch, first install can take a few minutes)'
    $Venv = Join-Path $Work 'venv'
    Remove-Tree $Venv
    $venvArgs = @($py.Args) + @('-m', 'venv', $Venv)
    & $py.Exe @venvArgs
    if ($LASTEXITCODE -ne 0) { throw 'Failed to create the virtualenv.' }

    $VenvPython = Join-Path $Venv 'Scripts\python.exe'
    & $VenvPython -m pip install --quiet --upgrade pip
    & $VenvPython -m pip install --quiet -r (Join-Path $AppDir 'requirements.txt')
    if ($LASTEXITCODE -ne 0) { throw 'pip install failed (some deps may need the MSVC build tools).' }

    # The demo reads OPENAI_API_KEY from a .env in the app directory.
    [System.IO.File]::WriteAllText(
        (Join-Path $AppDir '.env'),
        "OPENAI_API_KEY=$OpenAiKey`n",
        (New-Object System.Text.UTF8Encoding $false))

    Write-Host ''
    Write-Host "$([char]0x2713) Launching the agentic app." -ForegroundColor Green
    Write-Host @'
It opens at http://localhost:8501. On first run it builds embeddings, communities,
and summaries in Memgraph, then lets you ask questions and watch the agent choose
a pipeline per query.

Press Ctrl+C to stop the app; containers keep running.
'@

    Push-Location $AppDir
    try {
        & $VenvPython -m streamlit run agenticGraphRAG.py
    } finally {
        Pop-Location
    }

    Write-Host @"

App stopped. Memgraph and the MCP server are still running so you can re-launch:
  cd "$AppDir"; & "$VenvPython" -m streamlit run agenticGraphRAG.py

Tear everything down when you are done:
  $CleanHint
"@
}

# ---- Entry point -------------------------------------------------------------
# Piped into `iex` there is no $PSScriptRoot, so fall back to the current directory.
$BaseDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$script:DemoExitCode = 0

# Docker, git, and mgconsole write progress/warnings to stderr, so exit codes
# (checked explicitly above), not stderr, decide success. Keep PowerShell from
# turning a native command's stderr into a terminating error. Every global we touch
# here is restored below, so an `iwr | iex` run leaves the session as it found it.
$prevNativeErrorPref = $null
$hasNativeErrorPref = Test-Path variable:PSNativeCommandUseErrorActionPreference
if ($hasNativeErrorPref) {
    $prevNativeErrorPref = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
}
$prevOutputEncoding = $OutputEncoding
$prevConsoleEncoding = $null
try { $prevConsoleEncoding = [Console]::OutputEncoding } catch { }

$OutputEncoding = New-Object System.Text.UTF8Encoding $false
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }

try {
    Invoke-AgenticGraphRagDemo -Command $Command -BaseDir $BaseDir
} finally {
    $OutputEncoding = $prevOutputEncoding
    if ($prevConsoleEncoding) { try { [Console]::OutputEncoding = $prevConsoleEncoding } catch { } }
    if ($hasNativeErrorPref) { $PSNativeCommandUseErrorActionPreference = $prevNativeErrorPref }
}

# Only a real file run may set a process exit code: doing this under `iex` would
# close the caller's PowerShell session.
if ($PSCommandPath) { exit $script:DemoExitCode }
