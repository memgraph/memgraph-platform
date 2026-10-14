#Requires -Version 5.1
#
# AI memory with Memgraph: the single entry point (Windows / PowerShell).
#
# The Windows counterpart of ai-memory.sh. Context Graph's setup
# (github.com/memgraph/ai-toolkit/tree/main/context-graph) does the work: it finds
# or starts Memgraph and connects your coding agents, so what they know, did and
# know how to do is kept as one graph. It is a shell script, so on Windows it runs
# from WSL or Git Bash; this script says so and prints the command, as it cannot
# ask its questions from here.
#
# Usage (PowerShell 5.1 or PowerShell 7+):
#   iwr https://install.memgraph.com/ai-memory/windows -useb | iex
#   .\ai-memory.ps1
#
# If Windows blocks the script, allow local scripts for this session first:
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

Set-StrictMode -Version 2.0

$InstallUrl = 'https://raw.githubusercontent.com/memgraph/ai-toolkit/main/context-graph/scripts/install.sh'

Write-Host ''
Write-Host 'memgraph' -ForegroundColor DarkYellow
Write-Host ''
Write-Host 'AI memory: your coding agents remember what they know, did and learned.' -ForegroundColor DarkGray
Write-Host 'Setup finds or starts Memgraph, connects your agents, and asks first.' -ForegroundColor DarkGray
Write-Host ''
Write-Host 'In WSL or Git Bash, run:'
Write-Host "  curl -fsSL $InstallUrl | bash"
Write-Host ''
