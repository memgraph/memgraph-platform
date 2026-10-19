#Requires -Version 5.1
#
# AI memory with Memgraph: the single entry point (Windows / PowerShell).
#
# The Windows counterpart of ai-memory.sh. Context Graph's setup
# (github.com/memgraph/ai-toolkit/tree/main/context-graph) does the work: it finds
# or starts Memgraph and connects your coding agents, so what they know, did and
# know how to do is kept as one graph. It asks before changing anything.
#
# Needs a console to ask its questions on. Without one (CI, output sent to a file),
# or with AI_MEMORY_SKIP_SETUP=1, the script prints the command to run instead.
#
# Usage (PowerShell 5.1 or PowerShell 7+):
#   iwr https://install.memgraph.com/ai-memory/windows -useb | iex
#   .\ai-memory.ps1
#
# If Windows blocks the script, allow local scripts for this session first:
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

Set-StrictMode -Version 2.0

$InstallUrl = 'https://raw.githubusercontent.com/memgraph/ai-toolkit/main/context-graph/scripts/install.ps1'

Write-Host ''
Write-Host 'AI memory: what an assistant knows, did, and knows how to do, as one graph.' -ForegroundColor DarkGray
Write-Host 'Context Graph sets it up: it finds or starts Memgraph and connects your coding agents.' -ForegroundColor DarkGray

$HasConsole = -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected
if (-not $env:AI_MEMORY_SKIP_SETUP -and $HasConsole) {
    Invoke-Expression (Invoke-WebRequest -UseBasicParsing $InstallUrl).Content
} else {
    Write-Host ''
    Write-Host 'Set it up with:'
    Write-Host "  iwr $InstallUrl -useb | iex"
}
