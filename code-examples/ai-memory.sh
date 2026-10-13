#!/usr/bin/env bash
#
# AI Memory with Memgraph: runnable end-to-end example.
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
# using the actual packages Context Graph uses to capture coding agents' sessions
# (github.com/memgraph/ai-toolkit/tree/main/context-graph), not a hand-rolled
# schema:
#   - sessions-graph : semantic memory  -- durable, user-owned facts
#   - actions-graph   : episodic memory -- timestamped session/action history
#   - skills-graph    : procedural memory -- named, reusable how-tos
# It then opens Context Graph's own setup, so your agents write that memory from
# real sessions (on a terminal only; AI_MEMORY_SKIP_SETUP=1 skips it).
#
# Requirements -- two things you install once, yourself; the script checks for
# both up front and prints how to get them if they are missing:
#   - Docker           : https://docs.docker.com/get-docker/
#   - Python 3.10-3.13 : https://www.python.org/downloads/
# Everything below that (the Memgraph image, the Python packages) the script
# installs on its own, into a throwaway virtualenv next to this file.
#
# Usage:
#   ./ai-memory.sh          # bring everything up, seed memory, run recall
#   ./ai-memory.sh clean    # stop and remove everything this script created
#   MEMGRAPH_PORT=7688 ./ai-memory.sh  # use an explicit host Bolt port
# A busy default port falls back to a Docker-assigned port.
#
# If you have the script locally, use the `clean` command above. Piped straight
# from the web (curl -sSL https://install.memgraph.com/ai-memory | bash) there is no
# file to pass `clean` to, so the script prints the equivalent cleanup commands
# in the terminal instead.

set -euo pipefail

# ---- Pinned versions (avoid ':latest' drift) ---------------------------------
MAGE_IMAGE="memgraph/memgraph-mage:3.12.0"
LAB_IMAGE="memgraph/lab:3.12.0"

NET="aimemory-net"
DB="aimemory-memgraph"
# Marks the demo's Memgraph as throwaway: Context Graph's installer never points a harness's hooks at a
# container carrying it, so `clean` can't silently remove where real sessions are written.
DISPOSABLE_LABEL="com.memgraph.ai-memory.disposable=true"
LAB="aimemory-lab"
CONTEXT_GRAPH_INSTALL_URL="https://raw.githubusercontent.com/memgraph/ai-toolkit/main/context-graph/scripts/install.sh"
PORT_EXPLICIT="${MEMGRAPH_PORT:+1}"
BOLT_PORT="${MEMGRAPH_PORT:-7687}"

# Run from a checkout, ai-memory.py sits next to this script. Piped into bash
# (curl -sSL https://install.memgraph.com/ai-memory | bash) there is no script
# file -- BASH_SOURCE is unset, which bash 3.2 (macOS) rejects under `set -u` --
# so work in the current directory and fetch ai-memory.py from the repo instead.
PY_URL="https://raw.githubusercontent.com/memgraph/memgraph-platform/main/code-examples/ai-memory.py"
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  SCRIPT_DIR="$PWD"
fi
VENV="$SCRIPT_DIR/.ai-memory-venv"

# Tailor the copy-pasteable hints to how this was actually started. If you have the
# script locally, we print the `clean` command; if not (piped into bash), there is
# no file on disk to re-run or to pass `clean` to, so we print the equivalent
# cleanup commands as they would be written in the terminal.
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]:-}" ]]; then
  SELF="./$(basename "${BASH_SOURCE[0]}")"
  RUN_HINT="$SELF"
  CLEAN_HINT="$SELF clean"
else
  RUN_HINT="curl -sSL https://install.memgraph.com/ai-memory | bash"
  CLEAN_HINT="docker rm -f $DB $LAB; docker network rm $NET; rm -rf '$VENV'"
fi

# ---- Helpers ----------------------------------------------------------------
# Memgraph's brand colours: orange (#FB6E00) as the accent, gray (#857F87) for
# everything quieter, the nearest xterm-256 colours where there is no truecolor.
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  if [[ "${COLORTERM:-}" == truecolor || "${COLORTERM:-}" == 24bit ]]; then
    ORANGE=$'\033[38;2;251;110;0m'; GRAY=$'\033[38;2;133;127;135m'; GREEN=$'\033[38;2;25;175;102m'
  else
    ORANGE=$'\033[38;5;208m'; GRAY=$'\033[38;5;245m'; GREEN=$'\033[38;5;35m'
  fi
  BOLD=$'\033[1m'; OFF=$'\033[0m'
else
  ORANGE=''; GRAY=''; GREEN=''; BOLD=''; OFF=''
fi
# The Python client reads this to colour its own headings the same way.
export AI_MEMORY_ACCENT="$ORANGE"

log() { printf '\n%s==>%s %s%s%s\n' "$ORANGE" "$OFF" "$BOLD" "$*" "$OFF"; }

banner() {
  # The Memgraph wordmark: letter faces in orange, their drop shadow in gray.
  # Too narrow a terminal gets the name in one word instead.
  local cols line
  cols=$(tput cols 2>/dev/null || echo 80)
  if (( cols < 73 )); then
    printf '\n%s%smemgraph%s  AI memory\n' "$BOLD" "$ORANGE" "$OFF"
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
  # Under it, a small graph: nodes in orange, edges in gray.
  while IFS= read -r line; do
    line="${line//●/${ORANGE}●${GRAY}}"
    printf '%s%s%s\n' "$GRAY" "$line" "$OFF"
  done <<'GRAPH'
●───────●──────────────●─────────●────────────────●──────────●────────●
 ╲     ╱ ╲            ╱           ╲              ╱            ╲      ╱
  ●───●   ●──────────●             ●────────────●              ●────●
GRAPH
  echo
  printf '%sAI memory: what an assistant knows, did, and knows how to do, as one graph.%s\n' "$GRAY" "$OFF"
}

query() {
  # Run one or more Cypher statements (read from stdin) against Memgraph,
  # reusing the mgconsole already bundled in the memgraph-mage image.
  docker exec -i "$DB" mgconsole --host 127.0.0.1 --port 7687
}

teardown() {
  log "Stopping and removing container + network"
  docker rm -f "$DB" >/dev/null 2>&1 || true
  docker rm -f "$LAB" >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
  rm -rf "$VENV"
  echo "Cleaned up."
}

# ---- clean subcommand -------------------------------------------------------
if [[ "${1:-}" == "clean" ]]; then
  teardown
  exit 0
fi

banner

# ---- 0. Prerequisite checks --------------------------------------------------
# Only the two high-level dependencies are checked (never installed) here: a
# container engine and a language runtime are the user's call. The low-level
# dependencies -- the Memgraph image and the Python packages -- are installed
# automatically further down.
fatal() {
  printf '\n\033[1;31m%s\033[0m\n' "$1" >&2
  shift
  for hint in "$@"; do printf '  %s\n' "$hint" >&2; done
  echo >&2
  exit 1
}

command -v docker >/dev/null 2>&1 || fatal \
  "Missing dependency: Docker (the memory store runs in a container)." \
  "Install it: https://docs.docker.com/get-docker/" \
  "Then re-run: $RUN_HINT"

docker info >/dev/null 2>&1 || fatal \
  "Docker is installed, but its engine is not responding." \
  "Start Docker (Docker Desktop, colima, or your daemon of choice)," \
  "then re-run: $RUN_HINT"

PYBIN=""
for cand in python3.13 python3.12 python3.11 python3.10; do
  command -v "$cand" >/dev/null 2>&1 && { PYBIN="$cand"; break; }
done
if [[ -z "$PYBIN" ]] && command -v python3 >/dev/null 2>&1; then
  case "$(python3 -c 'import sys;print("%d.%d"%sys.version_info[:2])')" in
    3.10|3.11|3.12|3.13) PYBIN="python3" ;;
  esac
fi
if [[ -z "$PYBIN" ]]; then
  fatal "Missing dependency: Python 3.10-3.13 (runs the memory client)." \
    "Install it: https://www.python.org/downloads/" \
    "macOS:      brew install python@3.12" \
    "Debian etc: sudo apt install python3.12 python3.12-venv" \
    "Then re-run: $RUN_HINT"
fi

# ---- 1. Spin up Memgraph (the memory store) ---------------------------------
log "Creating network + starting Memgraph ($MAGE_IMAGE)"
docker rm -f "$DB" >/dev/null 2>&1 || true
docker network create "$NET" >/dev/null 2>&1 || true

if output=$(docker run -d --name "$DB" --network "$NET" --label "$DISPOSABLE_LABEL" \
  -p "${BOLT_PORT}:7687" "$MAGE_IMAGE" --schema-info-enabled=True 2>&1); then
  :
elif [[ "$output" == *"port is already allocated"* || "$output" == *"address already in use"* ]]; then
  # Docker retains the failed container after a binding conflict. Remove only
  # this attempt; never stop the process that already owns the requested port.
  docker rm "$DB" >/dev/null
  if [[ -n "$PORT_EXPLICIT" ]]; then
    echo "Port $BOLT_PORT is already allocated; rerun with MEMGRAPH_PORT set to a free port." >&2
    exit 1
  fi
  echo "Port $BOLT_PORT is already allocated -- asking Docker for a free Bolt port."
  docker run -d --name "$DB" --network "$NET" --label "$DISPOSABLE_LABEL" -p 7687 \
    "$MAGE_IMAGE" --schema-info-enabled=True >/dev/null
  BOLT_PORT=$(docker inspect --format '{{(index (index .NetworkSettings.Ports "7687/tcp") 0).HostPort}}' "$DB")
else
  printf '%s\n' "$output" >&2
  exit 1
fi


log "Waiting for Memgraph to be ready (Bolt-aware check)"
ready=0
for i in $(seq 1 30); do
  if echo "RETURN 1;" | query >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done
if [[ "$ready" -ne 1 ]]; then
  echo "Memgraph did not become ready in time" >&2
  docker logs "$DB" || true
  exit 1
fi
echo "Memgraph is up on bolt://localhost:${BOLT_PORT}"

# ---- 2. Install the Context Graph memory packages ----------------------------
log "Creating a Python virtualenv ($("$PYBIN" --version)) and installing sessions-graph, actions-graph, skills-graph"
rm -rf "$VENV"
"$PYBIN" -m venv "$VENV"
"$VENV/bin/pip" install --quiet --upgrade pip
"$VENV/bin/pip" install --quiet sessions-graph actions-graph skills-graph memgraph-toolbox

# ---- 3. Write and recall the three memory types ------------------------------
# Use the ai-memory.py next to this script when there is one (checkout); when
# piped, download it into the venv so `clean` removes it along with everything
# else this script created.
PY_FILE="$SCRIPT_DIR/ai-memory.py"
if [[ ! -f "$PY_FILE" ]]; then
  PY_FILE="$VENV/ai-memory.py"
  log "Downloading ai-memory.py (the memory client) from the memgraph-platform repo"
  command -v curl >/dev/null 2>&1 || fatal \
    "Missing dependency: curl (needed to download ai-memory.py)." \
    "Install it, or clone https://github.com/memgraph/memgraph-platform and run code-examples/ai-memory.sh"
  curl -fsSL "$PY_URL" -o "$PY_FILE" || fatal \
    "Could not download ai-memory.py from $PY_URL" \
    "Check your network, or clone https://github.com/memgraph/memgraph-platform and run code-examples/ai-memory.sh"
fi

MEMGRAPH_URL="bolt://localhost:${BOLT_PORT}" "$VENV/bin/python" "$PY_FILE"

printf '\n%s%s✓ AI memory is live.%s To see the graph in Memgraph Lab:\n' "$BOLD" "$GREEN" "$OFF"
cat <<EOF
  docker run -d --name ${LAB} --network ${NET} -p 3000:3000 \\
    -e QUICK_CONNECT_MG_HOST=${DB} -e QUICK_CONNECT_MG_PORT=7687 ${LAB_IMAGE}
  then open http://localhost:3000 and run  MATCH p=()-[]-() RETURN p;
EOF

# ---- 4. Hand over to Context Graph -------------------------------------------
# The demo wrote memory by hand; Context Graph writes it from real coding agents.
# Its setup is interactive and asks before changing anything, so it only runs
# with a person at the terminal: stdout a TTY and a /dev/tty to read keys from
# (piped into bash, stdin is this script). Tests set AI_MEMORY_SKIP_SETUP=1.
log "Next: give your coding agents this memory"
echo "Context Graph records Claude Code, Codex, Cursor and other agents' sessions into"
echo "a Memgraph of its own (not this throwaway one) so they can recall them later."
if [[ -z "${AI_MEMORY_SKIP_SETUP:-}" && -t 1 ]] && (exec </dev/tty) 2>/dev/null; then
  echo "Opening its setup; nothing changes until you confirm there."
  if curl -fsSL "$CONTEXT_GRAPH_INSTALL_URL" | bash; then
    # Setup installs the viewer unless it was unticked; offer it only when it's there.
    if memgraph-context-graph ui --version >/dev/null 2>&1; then
      printf '\nOpen the Context Graph viewer now? [Y/n] '
      read -r answer </dev/tty || answer=n
      [[ "$answer" =~ ^[Nn] ]] || memgraph-context-graph ui </dev/tty || true
    fi
  else
    echo "Setup didn't finish. Run it again whenever you like:"
    echo "  curl -fsSL $CONTEXT_GRAPH_INSTALL_URL | bash"
  fi
else
  echo "Set it up with:"
  echo "  curl -fsSL $CONTEXT_GRAPH_INSTALL_URL | bash"
fi

cat <<EOF

Remove the demo when you're done (Context Graph's Memgraph is separate):
  $CLEAN_HINT
EOF
