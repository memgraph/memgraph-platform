#Requires -Version 5.1
#
# Smoke-test every example in this folder on Windows.
#
# Each example is a self-contained demo that starts containers on fixed ports, so
# they cannot run at the same time (ai-memory.ps1 and agentic-graphrag.ps1 both
# publish Bolt on 7687). This runs them one at a time, in a child PowerShell, and
# tears each one down before and after, then reports pass/fail per example.
#
# An example passes when it exits 0 AND prints its success marker, so a demo that
# fails halfway but still reaches its closing banner cannot be mistaken for a
# working one.
#
# Requirements: whatever the examples need (Docker Desktop running, git, Python
# 3.10-3.13). Missing ones are reported per example instead of failing the run.
#
# Usage (PowerShell 5.1 or PowerShell 7+):
#   .\test.ps1                        # run all examples, clean up after each
#   .\test.ps1 -Only ai-memory        # run one (repeatable: -Only a,b)
#   .\test.ps1 -KeepUp                # leave the last example's containers up
#   .\test.ps1 -CleanOnly             # just tear every example down
#
# Logs land in test-logs-windows\<example>.log; on failure the tail is printed
# inline.
#
# If Windows blocks the script, allow local scripts for this session first:
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

[CmdletBinding()]
param(
    [ValidateSet('ai-memory', 'agentic-ai', 'agentic-graphrag')]
    [string[]]$Only,

    # Skip the teardown that normally follows each example, to poke at the graph.
    [switch]$KeepUp,

    # Tear every example down and exit (useful after -KeepUp, or after a Ctrl+C).
    [switch]$CleanOnly,

    # Per-example budget. The examples pull multi-GB images on a cold machine.
    [int]$TimeoutMinutes = 30
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Continue'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogDir = Join-Path $ScriptDir 'test-logs-windows'

# Run each example in a child process of the SAME host we are running under, so
# that its `exit` sets a process exit code we can read instead of killing this
# session, and PowerShell 7 gets tested with PowerShell 7.
$PsExe = try { (Get-Process -Id $PID).Path } catch { $null }
if (-not $PsExe -or -not (Test-Path -LiteralPath $PsExe)) { $PsExe = 'powershell.exe' }

# The success marker each example prints last. Substring match, so the checkmark
# and colouring around it do not matter.
$Examples = @(
    [pscustomobject]@{
        Name    = 'ai-memory'
        Script  = 'ai-memory.ps1'
        Marker  = 'AI memory is live.'
        Needs   = @('docker', 'python')
    },
    [pscustomobject]@{
        Name    = 'agentic-ai'
        Script  = 'agentic-ai.ps1'
        Marker  = 'Agents planned over the reasoning graph'
        Needs   = @('docker')
    },
    [pscustomobject]@{
        Name    = 'agentic-graphrag'
        Script  = 'agentic-graphrag.ps1'
        Marker  = 'GraphRAG retrieval pipelines ran against'
        Needs   = @('docker', 'git')
    }
)

# ---- Helpers ----------------------------------------------------------------
# $LASTEXITCODE lives in the global scope; a plain assignment here would create a
# script-scoped copy that native commands never update, silently freezing every
# exit-code check at its last value.
function Get-ExitCode {
    if (Test-Path variable:global:LASTEXITCODE) { return $global:LASTEXITCODE }
    return 0
}

function Write-Head {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host ''
    Write-Host "=== $Message" -ForegroundColor Cyan
}

function Test-Docker {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { return 'docker is not installed' }
    docker info *> $null
    if ((Get-ExitCode) -ne 0) { return 'the Docker engine is not responding (start Docker Desktop)' }
    return $null
}

function Test-Git {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return 'git is not installed' }
    return $null
}

function Test-Python {
    # Same range the examples accept; mirrors their own detection closely enough
    # to predict whether they will find an interpreter.
    foreach ($version in @('3.13', '3.12', '3.11', '3.10')) {
        if (Get-Command py -ErrorAction SilentlyContinue) {
            $exe = & py "-$version" -c 'import sys; print(sys.executable)' 2>$null | Select-Object -Last 1
            if ((Get-ExitCode) -eq 0 -and $exe -and (Test-Path -LiteralPath $exe)) { return $null }
        }
    }
    foreach ($name in @('python', 'python3')) {
        if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { continue }
        $version = & $name -c 'import sys;print("%d.%d"%sys.version_info[:2])' 2>$null | Select-Object -Last 1
        if ((Get-ExitCode) -eq 0 -and @('3.10', '3.11', '3.12', '3.13') -contains $version) { return $null }
    }
    return 'no Python 3.10-3.13 found'
}

function Get-MissingRequirement {
    param([Parameter(Mandatory = $true)][string[]]$Needs)
    foreach ($need in $Needs) {
        $problem = switch ($need) {
            'docker' { Test-Docker }
            'git'    { Test-Git }
            'python' { Test-Python }
            default  { $null }
        }
        if ($problem) { return $problem }
    }
    return $null
}

function Read-Utf8 {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Invoke-Example {
    # Run one example in a child host, capturing stdout+stderr to a log file, and
    # kill it if it outstays the budget -- a demo that hangs must not hang the
    # whole test run.
    param(
        [Parameter(Mandatory = $true)][string]$Script,
        [string[]]$Arguments = @(),
        [Parameter(Mandatory = $true)][string]$LogPath,
        [int]$TimeoutSeconds = 1800
    )
    $outFile = "$LogPath.out"
    $errFile = "$LogPath.err"
    $argList = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
                 '-File', (Join-Path $ScriptDir $Script)) + $Arguments

    $proc = Start-Process -FilePath $PsExe -ArgumentList $argList `
        -WorkingDirectory $ScriptDir -NoNewWindow -PassThru `
        -RedirectStandardOutput $outFile -RedirectStandardError $errFile

    # Touch .Handle before waiting. Start-Process -PassThru hands back a Process
    # object that has not opened a handle to the child, and once the child exits
    # without one .ExitCode reads back as $null -- which would make every example
    # look like it failed with a blank exit code.
    $null = $proc.Handle

    $timedOut = $false
    if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
        $timedOut = $true
        try { $proc.Kill() } catch { }
        try { $proc.WaitForExit(15000) | Out-Null } catch { }
    }

    # Join the two streams into one log. Start-Process cannot merge them, and the
    # examples deliberately let docker/git write to stderr.
    #
    # Read as UTF-8 explicitly: the examples set their console output encoding to
    # UTF-8, but Get-Content in Windows PowerShell decodes with the ANSI code
    # page, which turns their checkmark into mojibake and then writes that back
    # into the log double-encoded.
    $stdout = Read-Utf8 $outFile
    $stderr = Read-Utf8 $errFile
    $combined = $stdout
    if ($stderr) { $combined += "`n--- stderr ---`n$stderr" }
    [System.IO.File]::WriteAllText($LogPath, $combined, (New-Object System.Text.UTF8Encoding $false))
    Remove-Item -LiteralPath $outFile, $errFile -Force -ErrorAction SilentlyContinue

    $exitCode = if ($null -ne $proc.ExitCode) { [int]$proc.ExitCode } else { -1 }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output   = $combined
        TimedOut = $timedOut
    }
}

function Show-Tail {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [int]$Lines = 30
    )
    $tail = ($Text -split "`r?`n") | Select-Object -Last $Lines
    $tail | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
}

# ---- Select the examples to run ----------------------------------------------
$selected = if ($Only) { $Examples | Where-Object { $Only -contains $_.Name } } else { $Examples }
if (-not $selected) {
    Write-Host 'Nothing selected.' -ForegroundColor Red
    exit 1
}

# ---- clean-only mode ---------------------------------------------------------
if ($CleanOnly) {
    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    foreach ($example in $selected) {
        Write-Head "Cleaning $($example.Name)"
        Invoke-Example -Script $example.Script -Arguments @('clean') `
            -LogPath (Join-Path $LogDir "$($example.Name).clean.log") -TimeoutSeconds 300 | Out-Null
    }
    Write-Host ''
    Write-Host 'Cleaned up.'
    exit 0
}

# ---- Run ---------------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

# agentic-graphrag launches a blocking Streamlit app when OPENAI_API_KEY is set,
# which would stall the run forever. Hide the key from the child processes; the
# three retrieval pipelines it tests run without it. Restored afterwards.
$priorOpenAiKey = $env:OPENAI_API_KEY
$hadOpenAiKey = $null -ne $priorOpenAiKey
if ($hadOpenAiKey) {
    Write-Host 'Note: OPENAI_API_KEY is hidden from the examples so the agentic app does not block.' -ForegroundColor Yellow
    Remove-Item Env:\OPENAI_API_KEY -ErrorAction SilentlyContinue
}

$results = @()
try {
    foreach ($example in $selected) {
        $logPath = Join-Path $LogDir "$($example.Name).log"

        $missing = Get-MissingRequirement -Needs $example.Needs
        if ($missing) {
            Write-Head "$($example.Name): SKIPPED"
            Write-Host "  $missing" -ForegroundColor Yellow
            $results += [pscustomobject]@{ Name = $example.Name; Status = 'SKIP'; Seconds = 0; Detail = $missing }
            continue
        }

        # Start from a known state: a container left over from an earlier run
        # would otherwise hold the port this example needs.
        Write-Head "$($example.Name): tearing down any previous run"
        Invoke-Example -Script $example.Script -Arguments @('clean') `
            -LogPath (Join-Path $LogDir "$($example.Name).clean.log") -TimeoutSeconds 300 | Out-Null

        Write-Head "$($example.Name): running .\$($example.Script)"
        Write-Host "  (log: $logPath)"
        $started = Get-Date
        $run = Invoke-Example -Script $example.Script -LogPath $logPath `
            -TimeoutSeconds ($TimeoutMinutes * 60)
        $seconds = [int]((Get-Date) - $started).TotalSeconds

        $hasMarker = $run.Output -and $run.Output.Contains($example.Marker)
        if ($run.TimedOut) {
            $detail = "timed out after $TimeoutMinutes minutes"
        } elseif ($run.ExitCode -ne 0) {
            $detail = "exit code $($run.ExitCode)"
        } elseif (-not $hasMarker) {
            $detail = "exited 0 but never printed '$($example.Marker)'"
        } else {
            $detail = ''
        }

        if ($detail) {
            Write-Host "  FAIL ($detail) after ${seconds}s" -ForegroundColor Red
            Show-Tail -Text $run.Output
            $results += [pscustomobject]@{ Name = $example.Name; Status = 'FAIL'; Seconds = $seconds; Detail = $detail }
        } else {
            Write-Host "  PASS after ${seconds}s" -ForegroundColor Green
            $results += [pscustomobject]@{ Name = $example.Name; Status = 'PASS'; Seconds = $seconds; Detail = '' }
        }

        # Free the ports for the next example. Skipped only for the last one under
        # -KeepUp, so the graph is still there to poke at.
        $isLast = $example.Name -eq $selected[-1].Name
        if (-not ($KeepUp -and $isLast)) {
            Write-Head "$($example.Name): cleaning up"
            Invoke-Example -Script $example.Script -Arguments @('clean') `
                -LogPath (Join-Path $LogDir "$($example.Name).clean.log") -TimeoutSeconds 300 | Out-Null
        }
    }
} finally {
    if ($hadOpenAiKey) { $env:OPENAI_API_KEY = $priorOpenAiKey }
}

# ---- Summary -----------------------------------------------------------------
Write-Host ''
Write-Host '=== Summary' -ForegroundColor Cyan
foreach ($result in $results) {
    $colour = switch ($result.Status) {
        'PASS'  { 'Green' }
        'FAIL'  { 'Red' }
        default { 'Yellow' }
    }
    $line = '{0,-6} {1,-18} {2,5}s' -f $result.Status, $result.Name, $result.Seconds
    if ($result.Detail) { $line += "  ($($result.Detail))" }
    Write-Host $line -ForegroundColor $colour
}

$failed = @($results | Where-Object { $_.Status -eq 'FAIL' })
Write-Host ''
if ($failed.Count -gt 0) {
    Write-Host "$($failed.Count) example(s) failed. Full logs in $LogDir" -ForegroundColor Red
    exit 1
}
Write-Host "All good. Full logs in $LogDir"
if ($KeepUp) { Write-Host "Containers from '$($selected[-1].Name)' are still up; tear them down with: .\test.ps1 -CleanOnly" }
exit 0
