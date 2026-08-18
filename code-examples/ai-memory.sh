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
# using the actual Context Graph packages a live coding-assistant plugin uses
# (github.com/memgraph/ai-toolkit/tree/main/context-graph), not a hand-rolled
# schema:
#   - sessions-graph : semantic memory  -- durable, user-owned facts
#   - actions-graph   : episodic memory -- timestamped session/action history
#   - skills-graph    : procedural memory -- named, reusable how-tos
#
# Requirements: Docker + Python 3.10-3.13.
#   Docker: https://docs.docker.com/get-docker/
#
# Usage:
#   ./ai-memory.sh          # bring everything up, seed memory, run recall
#   ./ai-memory.sh clean    # stop and remove everything this script created

set -euo pipefail

# ---- Pinned version (avoid ':latest' drift) ---------------------------------
MAGE_IMAGE="memgraph/memgraph-mage:3.12.0"

NET="aimemory-net"
DB="aimemory-memgraph"
BOLT_PORT="7687"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$SCRIPT_DIR/.ai-memory-venv"

# ---- Helpers ----------------------------------------------------------------
log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

query() {
  # Run one or more Cypher statements (read from stdin) against Memgraph,
  # reusing the mgconsole already bundled in the memgraph-mage image.
  docker exec -i "$DB" mgconsole --host 127.0.0.1 --port 7687
}

teardown() {
  log "Stopping and removing container + network"
  docker rm -f "$DB" >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
  rm -rf "$VENV"
  echo "Cleaned up."
}

# ---- clean subcommand -------------------------------------------------------
if [[ "${1:-}" == "clean" ]]; then
  teardown
  exit 0
fi

# ---- 0. Prerequisite checks --------------------------------------------------
command -v docker >/dev/null 2>&1 || {
  echo "Docker is required: https://docs.docker.com/get-docker/" >&2
  exit 1
}

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
  echo "Python 3.10-3.13 is required: https://www.python.org/downloads/" >&2
  exit 1
fi

# ---- 1. Spin up Memgraph (the memory store) ---------------------------------
log "Creating network + starting Memgraph ($MAGE_IMAGE)"
docker rm -f "$DB" >/dev/null 2>&1 || true
docker network create "$NET" >/dev/null 2>&1 || true

docker run -d --name "$DB" --network "$NET" \
  -p "${BOLT_PORT}:7687" -p 7444:7444 \
  "$MAGE_IMAGE" --schema-info-enabled=True >/dev/null

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
log "Writing and recalling semantic, episodic, and procedural memory"
MEMGRAPH_URL="bolt://localhost:${BOLT_PORT}" "$VENV/bin/python" "$SCRIPT_DIR/ai-memory.py"

# ---- 4. Inspect the memory ontology ------------------------------------------
log "Memory ontology via SHOW SCHEMA INFO (returned in constant time)"
echo "SHOW SCHEMA INFO;" | query || echo "(enable with --schema-info-enabled, already set)"

# ---- Wrap up ----------------------------------------------------------------
cat <<EOF

$(printf '\033[1;32m✓ AI memory is live.\033[0m') The assistant can now answer "like last time"
by traversing: semantic (Acme Corp, New York) -> episodic (last session:
follow-up meeting) -> procedural (schedule-follow-up skill).

Explore the memory graph visually with Memgraph Lab:
  docker run -d --name aimemory-lab --network ${NET} -p 3000:3000 \\
    -e QUICK_CONNECT_MG_HOST=${DB} -e QUICK_CONNECT_MG_PORT=7687 memgraph/lab:3.12.0
  open http://localhost:3000     # then run:  MATCH p=()-[]-() RETURN p;

Wire this into a REAL harness so it collects sessions automatically (no seeding
by hand). One script installs and wires the Context Graph plugin for Claude
Code or Codex end to end, defaulting to this same Memgraph instance
(bolt://localhost:${BOLT_PORT}, no auth, database memgraph):

  curl -fsSL https://raw.githubusercontent.com/memgraph/ai-toolkit/main/context-graph/scripts/install.sh | bash
  # Codex instead of Claude Code:
  CONTEXT_GRAPH_RUNTIME=codex bash -c "\$(curl -fsSL https://raw.githubusercontent.com/memgraph/ai-toolkit/main/context-graph/scripts/install.sh)"

It registers the runtime's plugin marketplace, installs the plugin (the step a
bare 'agent-context-graph bootstrap' can't do -- that's what wires hooks into
the runtime), installs the CLI with all three connectors, sets your identity
(defaults to your git user.name; override with AGENT_CONTEXT_GRAPH_USER_ID),
and verifies with doctor. Full env var list and defaults:
  https://github.com/memgraph/ai-toolkit/tree/main/context-graph#getting-started-claude-code-or-codex

Every real session then writes Memory/Action/Skill nodes automatically, the
same nodes ai-memory.py just wrote by hand.

Tear everything down when you are done:
  ./ai-memory.sh clean
EOF
