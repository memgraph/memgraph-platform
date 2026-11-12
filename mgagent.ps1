#Requires -Version 5.1
#
# mgagent quick start (Windows / PowerShell): Memgraph's AI assistant, next to a
# fresh Memgraph. The Windows counterpart of mgagent.sh; it does the same thing.
#
#   iwr https://install.memgraph.com/mgagent/windows -useb | iex
#
# Starts the latest Memgraph MAGE image (memgraph/memgraph-mage:latest) and then
# the latest mgagent image (memgraph/mgagent:latest), already connected to it.
# Both share a private Docker network; Memgraph is also published on the host
# (localhost:7687, 7444) for Memgraph Lab, mgconsole or your own drivers.
#
# LLM provider settings already set in this PowerShell session ($env:...) are
# passed on to mgagent:
#   ANTHROPIC_API_KEY  ANTHROPIC_BASE_URL
#   OPENAI_API_KEY     OPENAI_BASE_URL
#   GEMINI_API_KEY     GOOGLE_API_KEY
#   DEEPSEEK_API_KEY   XAI_API_KEY   MISTRAL_API_KEY
#   OLLAMA_HOST        OLLAMA_BASE_URL
# plus MGAGENT_TELEMETRY (set it to "off" to opt out of usage statistics).
# A base URL on localhost / 127.0.0.1 / 0.0.0.0 is rewritten to
# host.docker.internal, since localhost inside the container is the container.
# With none of these set, mgagent asks for a provider and key on first run and
# keeps it in the "mgagent" Docker volume.
#
# Requirements: Docker Desktop, running ("Engine running" in its UI).
#   https://docs.docker.com/desktop/install/windows-install/
#
# Options (environment variables):
#   $env:MGAGENT_WORKDIR = '<dir>'  mount <dir> at /work and start mgagent there,
#                                   so it can read and import your files (the
#                                   drive must be shared with Docker Desktop)
#   $env:MEMGRAPH_PORT = '<port>'   host port for Memgraph's Bolt endpoint (default 7687)
#
# Arguments go to mgagent. `iex` cannot pass any, so use the script block form,
# e.g. for a one-off headless question:
#   & ([scriptblock]::Create((iwr https://install.memgraph.com/mgagent/windows -useb))) -p "how many nodes are there?"
# or, with the file downloaded:  .\mgagent.ps1 -p "how many nodes are there?"
#
# Tear down (Memgraph keeps running after mgagent exits):
#   & ([scriptblock]::Create((iwr https://install.memgraph.com/mgagent/windows -useb))) clean
#   (or: docker rm -f mgagent-memgraph; docker network rm mgagent-net)
#
# If Windows blocks the downloaded file, allow local scripts for this session:
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# No param() block on purpose: every argument, `-p` included, must reach
# mgagent untouched in $args rather than be bound (or rejected) by PowerShell.

# Everything lives in this one function on purpose, so the script behaves the
# same run as a file or piped into Invoke-Expression (iwr ... | iex). Under
# `iex` there is no script to exit from, so a top-level `exit` would close the
# caller's PowerShell session; inside a function we `return` and the entry
# point at the bottom turns that into an exit code only for a real file run.
# The function writes nothing to the pipeline and is never piped or captured:
# mgagent's terminal UI needs docker to own the console.
function Invoke-MgagentQuickStart {
    param(
        [string[]]$MgagentArgs = @()
    )

    Set-StrictMode -Version 2.0

    # Docker reports progress on stderr. In Windows PowerShell that becomes
    # ErrorRecords as soon as a stream is redirected, so keep the preference at
    # Continue and judge success by exit code alone.
    $ErrorActionPreference = 'Continue'

    # Assign $LASTEXITCODE through $global: only: a plain assignment inside a
    # function makes a local copy that native commands never update.
    $global:LASTEXITCODE = 0

    $MageImage    = 'memgraph/memgraph-mage:latest'
    $MgagentImage = 'memgraph/mgagent:latest'

    $Net          = 'mgagent-net'
    $Memgraph     = 'mgagent-memgraph'
    $Volume       = 'mgagent'
    $MemgraphPort = if ($env:MEMGRAPH_PORT) { $env:MEMGRAPH_PORT } else { '7687' }

    $SourceUrl = 'https://install.memgraph.com/mgagent/windows'
    if ($PSCommandPath) {
        $Self      = '.\' + (Split-Path -Leaf $PSCommandPath)
        $RunHint   = $Self
        $CleanHint = "$Self clean"
    } else {
        $RunHint   = "iwr $SourceUrl -useb | iex"
        $CleanHint = "& ([scriptblock]::Create((iwr $SourceUrl -useb))) clean"
    }

    # Every variable mgagent reads its provider from (apps/cli/src/config.ts).
    $KeyVars   = @('ANTHROPIC_API_KEY', 'OPENAI_API_KEY', 'GEMINI_API_KEY', 'GOOGLE_API_KEY',
                   'DEEPSEEK_API_KEY', 'XAI_API_KEY', 'MISTRAL_API_KEY')
    $UrlVars   = @('ANTHROPIC_BASE_URL', 'OPENAI_BASE_URL', 'OLLAMA_HOST', 'OLLAMA_BASE_URL')
    $OtherVars = @('MGAGENT_TELEMETRY')

    # ---- Helpers ------------------------------------------------------------
    function Write-Step([string]$Message) {
        Write-Host ''
        Write-Host "==> $Message" -ForegroundColor Cyan
    }
    function Write-Warn([string]$Message) {
        Write-Host 'Warning: ' -ForegroundColor Yellow -NoNewline
        Write-Host $Message
    }
    function Write-Fail([string[]]$Message) {
        Write-Host ''
        $Message | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    }
    function Write-Found([string]$Name, [string]$Value, [string]$Note = '') {
        Write-Host '  + ' -ForegroundColor Green -NoNewline
        Write-Host "$Name = $Value" -NoNewline
        if ($Note) { Write-Host " $Note" -ForegroundColor DarkGray } else { Write-Host '' }
    }

    function Get-EnvValue([string]$Name) {
        $v = [Environment]::GetEnvironmentVariable($Name, 'Process')
        if ($null -eq $v) { return '' }
        return $v.Trim()
    }

    # A key shown as its first and last few characters, never the whole thing.
    function Get-Masked([string]$Value) {
        if ($Value.Length -le 12) { return '****' }
        return $Value.Substring(0, 6) + '...' + $Value.Substring($Value.Length - 4)
    }

    # localhost in a URL (with or without a scheme, as OLLAMA_HOST often is)
    # points at the host when seen from inside the container.
    function ConvertTo-ContainerUrl([string]$Url) {
        return $Url -replace '^((?:[A-Za-z][A-Za-z0-9+.-]*://)?)(localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1\])(?=[:/]|$)', '${1}host.docker.internal'
    }

    function Test-ContainerRunning {
        $state = & docker inspect -f '{{.State.Running}}' $Memgraph 2>$null
        return ($LASTEXITCODE -eq 0 -and "$state".Trim() -eq 'true')
    }

    function Invoke-Teardown {
        Write-Step "Removing $Memgraph and the $Net network"
        & docker rm -f $Memgraph *> $null
        & docker network rm $Net *> $null
        $global:LASTEXITCODE = 0
        Write-Host "Cleaned up. mgagent settings and history stay in the `"$Volume`" volume:"
        Write-Host "  docker volume rm $Volume"
    }

    # ---- Requirements -------------------------------------------------------
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Fail 'Docker is required: https://docs.docker.com/desktop/install/windows-install/'
        $script:MgagentExitCode = 1; return
    }
    & docker info *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Fail 'Docker is installed but not reachable. Is Docker Desktop running ("Engine running")?'
        $script:MgagentExitCode = 1; return
    }

    if ($MgagentArgs.Count -gt 0 -and $MgagentArgs[0] -eq 'clean') {
        Invoke-Teardown
        return
    }

    # mgagent is a terminal UI: it needs a console to draw in. Without one
    # (CI, redirected input) only headless use (-p ...) can work.
    $interactive = $true
    try { $interactive = -not ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) } catch { $interactive = $false }
    if (-not $interactive -and $MgagentArgs.Count -eq 0) {
        Write-Fail "No console to run mgagent's UI in. Run this from a PowerShell window, or pass a headless question (-p `"...`")."
        $script:MgagentExitCode = 1; return
    }

    # ---- Provider settings from the environment -----------------------------
    # Rewritten base URLs are set in this process only while docker runs and
    # restored afterwards, so an `iex` run leaves the session as it found it.
    $envFlags      = New-Object System.Collections.Generic.List[string]
    $savedEnv      = @{}
    $foundProvider = $false

    Write-Step 'Looking for LLM provider settings in your environment'
    foreach ($var in $KeyVars) {
        $val = Get-EnvValue $var
        if (-not $val) { continue }
        Write-Found $var (Get-Masked $val)
        $envFlags.Add('-e'); $envFlags.Add($var)
        $foundProvider = $true
    }
    foreach ($var in $UrlVars) {
        $val = Get-EnvValue $var
        if (-not $val) { continue }
        $new = ConvertTo-ContainerUrl $val
        if ($new -ne $val) {
            Write-Found $var $new "(was $val)"
            $savedEnv[$var] = [Environment]::GetEnvironmentVariable($var, 'Process')
            [Environment]::SetEnvironmentVariable($var, $new, 'Process')
        } else {
            Write-Found $var $val
        }
        $envFlags.Add('-e'); $envFlags.Add($var)
        # A base URL alone is a provider for a local server (Ollama, vLLM, LM Studio...).
        if ($var -eq 'OPENAI_BASE_URL' -or $var -like 'OLLAMA_*') { $foundProvider = $true }
    }
    foreach ($var in $OtherVars) {
        $val = Get-EnvValue $var
        if (-not $val) { continue }
        Write-Found $var $val
        $envFlags.Add('-e'); $envFlags.Add($var)
    }
    if (-not $foundProvider) {
        Write-Host '  none found - mgagent will ask for a provider and key on first run'
        Write-Host '  (or set one first, e.g. $env:ANTHROPIC_API_KEY = "...", and re-run)'
    }

    try {
        # ---- Images ---------------------------------------------------------
        Write-Step "Pulling $MageImage and $MgagentImage"
        foreach ($image in @($MageImage, $MgagentImage)) {
            & docker pull $image
            if ($LASTEXITCODE -ne 0) {
                # Offline, or a registry hiccup: a copy on this machine will do.
                & docker image inspect $image *> $null
                if ($LASTEXITCODE -ne 0) {
                    Write-Fail "Could not pull $image."
                    $script:MgagentExitCode = 1; return
                }
                Write-Warn "could not pull $image; using the copy already on this machine"
            }
        }

        # ---- Memgraph -------------------------------------------------------
        & docker network inspect $Net *> $null
        if ($LASTEXITCODE -ne 0) {
            & docker network create $Net *> $null
            if ($LASTEXITCODE -ne 0) { Write-Fail "Could not create the $Net Docker network."; $script:MgagentExitCode = 1; return }
        }

        $latestId  = "$(& docker image inspect -f '{{.Id}}' $MageImage 2>$null)".Trim()
        $currentId = "$(& docker inspect -f '{{.Image}}' $Memgraph 2>$null)".Trim()
        $hasContainer = ($LASTEXITCODE -eq 0 -and $currentId)

        if ($hasContainer -and $currentId -eq $latestId -and (Test-ContainerRunning)) {
            Write-Step "Memgraph is already running ($Memgraph), reusing it"
        } else {
            if ($hasContainer) {
                Write-Step "Replacing the previous $Memgraph container with the latest image"
                & docker rm -f $Memgraph *> $null
            }
            Write-Step "Starting Memgraph ($MageImage) on localhost:$MemgraphPort"
            # A port already in use (another Memgraph?) fails the run, so fall
            # back to Bolt alone (7444 only streams logs to Lab), then to no host
            # ports at all: mgagent reaches Memgraph over the Docker network.
            $attempts = @(
                @('-p', "${MemgraphPort}:7687", '-p', '7444:7444'),
                @('-p', "${MemgraphPort}:7687"),
                @()
            )
            $started = $false
            $lastOut = @()
            for ($i = 0; $i -lt $attempts.Count; $i++) {
                $runArgs = @('run', '-d', '--name', $Memgraph, '--network', $Net) + $attempts[$i] +
                           @($MageImage, '--schema-info-enabled=True')
                $lastOut = & docker @runArgs 2>&1
                if ($LASTEXITCODE -eq 0) { $started = $true; break }
                & docker rm -f $Memgraph *> $null
                if ($i -eq 0) { Write-Warn "port 7444 is in use on the host; starting Memgraph without it (only Lab's log view needs it)" }
                if ($i -eq 1) { Write-Warn "port $MemgraphPort is in use on the host; starting Memgraph without host ports (set `$env:MEMGRAPH_PORT to pick another)" }
            }
            if (-not $started) {
                Write-Fail (@('Could not start Memgraph:') + ($lastOut | ForEach-Object { "  $_" }))
                $script:MgagentExitCode = 1; return
            }
        }

        Write-Step 'Waiting for Memgraph to accept connections'
        $ready = $false
        for ($t = 0; $t -lt 60; $t++) {
            & docker exec $Memgraph bash -c 'echo > /dev/tcp/127.0.0.1/7687' *> $null
            if ($LASTEXITCODE -eq 0) { $ready = $true; break }
            if (-not (Test-ContainerRunning)) {
                & docker logs --tail 20 $Memgraph
                Write-Fail 'Memgraph exited during startup (logs above).'
                $script:MgagentExitCode = 1; return
            }
            Start-Sleep -Seconds 1
        }
        if (-not $ready) { Write-Warn "Memgraph is not answering yet; starting mgagent anyway (see: docker logs $Memgraph)" }

        # ---- mgagent --------------------------------------------------------
        $runArgs = @('run')
        if ($interactive) { $runArgs += '-it' }
        $runArgs += @('--rm', '--network', $Net,
                      '--add-host=host.docker.internal:host-gateway',
                      '-v', "${Volume}:/home/nonroot/.mgagent")
        # The -e flags carry only variable names, so key values never show up
        # in a process listing.
        $runArgs += $envFlags.ToArray()

        if ($env:MGAGENT_WORKDIR) {
            if (-not (Test-Path -LiteralPath $env:MGAGENT_WORKDIR -PathType Container)) {
                Write-Fail "MGAGENT_WORKDIR is not a directory: $env:MGAGENT_WORKDIR"
                $script:MgagentExitCode = 1; return
            }
            $workDir = (Resolve-Path -LiteralPath $env:MGAGENT_WORKDIR).ProviderPath
            $runArgs += @('-v', "${workDir}:/work", '-w', '/work')
            Write-Step "Mounting $workDir at /work"
        }

        $runArgs += @($MgagentImage, '-c', "bolt://${Memgraph}:7687") + $MgagentArgs

        Write-Step "Starting mgagent ($MgagentImage), connected to bolt://${Memgraph}:7687"
        & docker @runArgs
        $status = $LASTEXITCODE
    } finally {
        foreach ($var in $savedEnv.Keys) {
            [Environment]::SetEnvironmentVariable($var, $savedEnv[$var], 'Process')
        }
    }

    # ---- Wrap up ------------------------------------------------------------
    # Ask Docker rather than trusting MEMGRAPH_PORT: a reused container keeps
    # the ports it was started with.
    $hostPort = ''
    $portOut = & docker port $Memgraph 7687/tcp 2>$null
    if ($LASTEXITCODE -eq 0 -and $portOut) {
        $first = @($portOut)[0]
        $hostPort = $first.Substring($first.LastIndexOf(':') + 1).Trim()
    }
    $global:LASTEXITCODE = 0

    Write-Host ''
    Write-Host 'Memgraph is still running' -NoNewline -ForegroundColor White
    if ($hostPort) {
        Write-Host " ($Memgraph) at bolt://localhost:$hostPort"
    } else {
        Write-Host " ($Memgraph), reachable only on the $Net Docker network"
    }
    Write-Host @"

Start mgagent again (settings and history are kept in the "$Volume" volume):
  $RunHint

Explore the graph in Memgraph Lab:
  docker run -d --rm --name mgagent-lab --network $Net -p 3000:3000 ``
    -e QUICK_CONNECT_MG_HOST=$Memgraph -e QUICK_CONNECT_MG_PORT=7687 memgraph/lab:latest
  start http://localhost:3000

Tear everything down:
  $CleanHint
"@
    $script:MgagentExitCode = $status
}

# ---- Entry point -------------------------------------------------------------
$script:MgagentExitCode = 0

# Keep PowerShell 7.3+ from turning a native command's non-zero exit into an
# error; exit codes are checked explicitly above. Every global touched here is
# restored below, so an `iwr | iex` run leaves the session as it found it.
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
    Invoke-MgagentQuickStart -MgagentArgs @($args)
} finally {
    $OutputEncoding = $prevOutputEncoding
    if ($prevConsoleEncoding) { try { [Console]::OutputEncoding = $prevConsoleEncoding } catch { } }
    if ($hasNativeErrorPref) { $PSNativeCommandUseErrorActionPreference = $prevNativeErrorPref }
}

# Only a real file run may set a process exit code: doing this under `iex`
# would close the caller's PowerShell session.
if ($PSCommandPath) { exit $script:MgagentExitCode }
