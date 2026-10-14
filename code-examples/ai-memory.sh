#!/usr/bin/env bash
#
# AI memory with Memgraph: the single entry point.
#
# Draws the Memgraph logo, says what is about to happen, and hands over to
# Context Graph's setup (github.com/memgraph/ai-toolkit/tree/main/context-graph),
# which does the rest: finds or starts Memgraph, and wires your coding agents
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

# Memgraph's brand colours: orange (#FB6E00) for the wordmark, gray (#857F87) for edges and quiet text, the
# brand gradient (yellow, orange, red, purple) on the graph's nodes. The nearest xterm-256 colours where
# there is no truecolor; none at all when not on a terminal or NO_COLOR is set.
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  if [[ "${COLORTERM:-}" == truecolor || "${COLORTERM:-}" == 24bit ]]; then
    ORANGE=$'\033[38;2;251;110;0m'; GRAY=$'\033[38;2;133;127;135m'
    YELLOW=$'\033[38;2;255;197;0m'; RED=$'\033[38;2;220;34;35m'; PURPLE=$'\033[38;2;114;0;150m'
  else
    ORANGE=$'\033[38;5;208m'; GRAY=$'\033[38;5;245m'
    YELLOW=$'\033[38;5;220m'; RED=$'\033[38;5;160m'; PURPLE=$'\033[38;5;90m'
  fi
  BOLD=$'\033[1m'; OFF=$'\033[0m'
else
  ORANGE=''; GRAY=''; YELLOW=''; RED=''; PURPLE=''; BOLD=''; OFF=''
fi

banner() {
  # The wordmark: letter faces in orange, their drop shadow in gray. Too narrow a terminal gets one word.
  local cols line
  cols=$(tput cols 2>/dev/null || echo 80)
  if (( cols < 73 )); then
    printf '\n%s%smemgraph%s\n' "$BOLD" "$ORANGE" "$OFF"
    return
  fi
  echo
  while IFS= read -r line; do
    line="${line//█/${ORANGE}█${GRAY}}"
    printf '%s%s%s\n' "$GRAY" "$line" "$OFF"
  done <<'WORDMARK'
███╗   ███╗███████╗███╗   ███╗ ██████╗ ██████╗  █████╗ ██████╗ ██╗  ██╗
████╗ ████║██╔════╝████╗ ████║██╔════╝ ██╔══██╗██╔══██╗██╔══██╗██║  ██║
██╔████╔██║█████╗  ██╔████╔██║██║  ███╗██████╔╝███████║██████╔╝███████║
██║╚██╔╝██║██╔══╝  ██║╚██╔╝██║██║   ██║██╔══██╗██╔══██║██╔═══╝ ██╔══██║
██║ ╚═╝ ██║███████╗██║ ╚═╝ ██║╚██████╔╝██║  ██║██║  ██║██║     ██║  ██║
╚═╝     ╚═╝╚══════╝╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝
WORDMARK
  # Under it, a graph as wide as the wordmark: edges in gray, nodes in the brand gradient, left to right.
  # The letters Y, O, R and P stand for the four node colours, and are never printed.
  while IFS= read -r line; do
    line="${line//Y/${YELLOW}●${GRAY}}"
    line="${line//O/${ORANGE}●${GRAY}}"
    line="${line//R/${RED}●${GRAY}}"
    line="${line//P/${PURPLE}●${GRAY}}"
    printf '%s%s%s\n' "$GRAY" "$line" "$OFF"
  done <<'GRAPH'
Y───────────────Y                 O─────────────────R─────────────────P
 ╲             ╱ ╲               ╱ ╲               ╱ ╲               ╱
  Y           Y───O             O───R             R───P             P
   ╲         ╱     ╲           ╱     ╲           ╱     ╲           ╱
    Y───────Y       O─────────O       R─────────R       P─────────P
     ╲     ╱       ╱         ╱         ╲         ╲     ╱         ╱
      Y───Y           O─────O           R─────R           P─────P
GRAPH
}

banner
printf '\n%sAI memory: what an assistant knows, did, and knows how to do, as one graph.%s\n' "$GRAY" "$OFF"
printf '%sContext Graph sets it up: it finds or starts Memgraph and connects your coding agents.%s\n' "$GRAY" "$OFF"

# Setup is interactive and asks before changing anything, so it only runs with a person at the terminal:
# stdout a TTY and a /dev/tty to read keys from (piped into bash, stdin is this script).
if [[ -z "${AI_MEMORY_SKIP_SETUP:-}" && -t 1 ]] && (exec </dev/tty) 2>/dev/null; then
  # --no-banner: the wordmark above is Context Graph's own (memgraph-context-graph >= 0.7.0).
  curl -fsSL "$CONTEXT_GRAPH_INSTALL_URL" | bash -s -- --no-banner
else
  printf '\nSet it up with:\n  curl -fsSL %s | bash\n' "$CONTEXT_GRAPH_INSTALL_URL"
fi
