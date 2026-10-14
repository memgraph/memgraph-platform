#!/usr/bin/env bash
#
# AI memory with Memgraph: the single entry point.
#
# Says what is about to happen and hands over to Context Graph's setup
# (github.com/memgraph/ai-toolkit/tree/main/context-graph), which draws the Memgraph
# logo and does the rest: finds or starts Memgraph, and wires your coding agents
# (Claude Code, Codex, Copilot CLI, Cursor, OpenCode, ...) so what they know, did
# and know how to do is kept as one graph. It asks before changing anything.
#
# Usage:
#   curl -sSL https://install.memgraph.com/ai-memory | bash
#   ./ai-memory.sh
#
# Needs a terminal to ask its questions on. Without one (CI, a pipe to a file) the
# script prints the command to run instead; AI_MEMORY_SKIP_SETUP=1 does the same.

set -euo pipefail

CONTEXT_GRAPH_INSTALL_URL="https://raw.githubusercontent.com/memgraph/ai-toolkit/main/context-graph/scripts/install.sh"

GRAY=''
OFF=''
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  GRAY=$'\033[38;5;245m'; OFF=$'\033[0m'   # Memgraph's gray, #857F87
fi

printf '\n%sAI memory: your coding agents remember what they know, did and learned.%s\n' "$GRAY" "$OFF"
printf '%sSetup finds or starts Memgraph, connects your agents, and asks first.%s\n' "$GRAY" "$OFF"

# Setup is interactive and asks before changing anything, so it only runs with a person at the terminal:
# stdout a TTY and a /dev/tty to read keys from (piped into bash, stdin is this script).
if [[ -z "${AI_MEMORY_SKIP_SETUP:-}" && -t 1 ]] && (exec </dev/tty) 2>/dev/null; then
  curl -fsSL "$CONTEXT_GRAPH_INSTALL_URL" | bash
else
  printf '\nSet it up with:\n  curl -fsSL %s | bash\n' "$CONTEXT_GRAPH_INSTALL_URL"
fi
