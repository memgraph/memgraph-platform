#!/usr/bin/env bash
#
# Agentic GraphRAG with Memgraph: runnable end-to-end example.
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
#   - Docker  https://docs.docker.com/get-docker/   (required)
#   - git     https://git-scm.com/downloads          (required)
#   - For the OPTIONAL agentic app only:
#       Python 3.10-3.13 + pip, and an OpenAI API key:  export OPENAI_API_KEY=sk-...
#
# Usage:
#   ./agentic-graphrag.sh          # import + run the three atomic pipelines
#                                   # (+ launch the agent app if OPENAI_API_KEY is set)
#   ./agentic-graphrag.sh clean    # stop containers and remove the work dir

set -euo pipefail

# ---- Pinned versions --------------------------------------------------------
MAGE_IMAGE="memgraph/memgraph-mage:3.12.0"        # version the demo targets
MGCONSOLE_IMAGE="memgraph/mgconsole:1.6.0"
MCP_IMAGE="memgraph/mcp-memgraph:0.2.0"

NET="agenticgraphrag-net"
DB="agenticgraphrag-memgraph"
MCP="agenticgraphrag-mcp"
MCP_PORT="8000"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK="$SCRIPT_DIR/.agentic-graphrag-work"
REPO="$WORK/ai-demos"
APP_DIR="$REPO/agentic-graph-rag/agentic"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
mg()  { docker run -i --rm --network "$NET" "$MGCONSOLE_IMAGE" --host "$DB" --port 7687; }

teardown() {
  log "Stopping containers, removing network + work dir"
  docker rm -f "$MCP" "$DB" >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
  rm -rf "$WORK"
  echo "Cleaned up."
}

if [[ "${1:-}" == "clean" ]]; then
  teardown
  exit 0
fi

# ---- 0. Prerequisites --------------------------------------------------------
for tool in docker git; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Missing prerequisite: $tool" >&2; exit 1; }
done

# ---- Get the official demo --------------------------------------------------
log "Fetching the official Agentic GraphRAG demo (sparse clone of memgraph/ai-demos)"
mkdir -p "$WORK"
if [[ ! -d "$REPO/.git" ]]; then
  git clone --depth 1 --filter=blob:none --sparse https://github.com/memgraph/ai-demos.git "$REPO"
  git -C "$REPO" sparse-checkout set agentic-graph-rag/agentic
fi
DATASET="$APP_DIR/asknews-finance-graph.cypherl"
[[ -f "$DATASET" ]] || { echo "Dataset not found at $DATASET" >&2; exit 1; }

# ---- 1a. Spin up Memgraph ---------------------------------------------------
log "Starting Memgraph ($MAGE_IMAGE) with schema info enabled"
docker rm -f "$DB" "$MCP" >/dev/null 2>&1 || true
docker network create "$NET" >/dev/null 2>&1 || true
docker run -d --name "$DB" --network "$NET" \
  -p 7687:7687 -p 7444:7444 \
  "$MAGE_IMAGE" --schema-info-enabled=True >/dev/null

log "Waiting for Memgraph to accept Bolt connections"
until echo "RETURN 1;" | mg >/dev/null 2>&1; do sleep 1; done

# ---- 2. Load the knowledge graph --------------------------------------------
# mgconsole accepts a bounded amount of input per invocation, so the .cypherl is
# streamed in batches (same approach as the demo's setup.sh, but over a Docker
# network so it works the same on Linux, macOS, and Windows).
log "Importing the AskNews finance knowledge graph ($(wc -l < "$DATASET") statements)"
lines=$(wc -l < "$DATASET"); batch=300; start=1
while [ "$start" -le "$lines" ]; do
  sed -n "${start},$((start + batch - 1))p" "$DATASET" | mg >/dev/null 2>&1
  start=$((start + batch))
done
nodes=$(echo "MATCH (n) RETURN count(n);" | mg 2>/dev/null | grep -oE '[0-9]+' | head -1)
echo "Imported. Memgraph now holds ${nodes} nodes."

# ---- 1b. Spin up the MCP server ---------------------------------------------
# This is the "MCP" from the outline: your own harness can load it as a tool and
# query the same graph, instead of (or alongside) the Streamlit app below.
log "Starting the Memgraph MCP server ($MCP_IMAGE)"
docker run -d --name "$MCP" --network "$NET" \
  -p "${MCP_PORT}:8000" \
  --env MEMGRAPH_URL="bolt://${DB}:7687" \
  "$MCP_IMAGE" >/dev/null

# 'docker run -d' returns as soon as the container exists, several seconds before
# the HTTP server inside it is listening. The endpoint below is meant to be
# pasted straight into a harness, so wait for the server to say it is up rather
# than advertising a port that still refuses connections.
mcp_ready=0
for _ in $(seq 1 30); do
  [ "$(docker inspect -f '{{.State.Running}}' "$MCP" 2>/dev/null)" = "true" ] || break
  if docker logs "$MCP" 2>&1 | grep -qE "Application startup complete|Uvicorn running on"; then
    mcp_ready=1
    break
  fi
  sleep 1
done
if [ "$mcp_ready" -eq 1 ]; then
  echo "MCP endpoint: http://localhost:${MCP_PORT}/mcp/"
else
  # Not fatal: the three pipelines below talk to Memgraph directly, so the demo
  # is still worth watching without the MCP server.
  echo "Warning: the MCP server did not become ready; its recent logs:" >&2
  docker logs --tail 20 "$MCP" >&2 || true
  echo "Continuing - the pipelines below query Memgraph directly." >&2
fi

# ---- 3. Run the three GraphRAG retrieval pipelines (atomic Cypher) ----------
# Each pipeline is ONE database operation, matching https://memgraph.com/graphrag.
# The agentic app in step 4 just picks which of these to run for a given question.
PIVOT="nvidia"   # the seed entity for the local pipeline

log "Pipeline 1/3 - Text2Cypher (Analytical): 'What kinds of organizations are covered, and how many of each?'"
# An analytical question becomes a single aggregating Cypher query.
echo "MATCH (n:organization) WHERE n.detailed_type IS NOT NULL
      RETURN n.detailed_type AS organization_type, count(*) AS count
      ORDER BY count DESC LIMIT 8;" | mg

log "Pipeline 2/3 - Pivot search + relevance expansion (Local): 'What is connected to \"$PIVOT\"?'"
# Pivot on a seed entity, then expand the neighborhood (<=2 hops) in one traversal.
# In production the pivot is a native vector search; here we pivot by name.
echo "MATCH (seed {id: '$PIVOT'})-[*1..2]-(context)
      RETURN DISTINCT context.id AS related_entity, context.main_type AS type
      LIMIT 10;" | mg

log "Pipeline 3/3 - Query-focused summarisation (Global): 'What are the most central themes overall?'"
# A global question ranks the whole graph (PageRank, MAGE) to find themes an LLM
# would then summarise.
echo "CALL pagerank.get() YIELD node, rank
      RETURN node.id AS theme, node.main_type AS type, round(rank * 10000) / 10000 AS importance
      ORDER BY importance DESC LIMIT 10;" | mg

cat <<EOF

$(printf '\033[1;32m✓ GraphRAG retrieval pipelines ran against %s nodes.\033[0m' "${nodes}")

Memgraph : bolt://localhost:7687   (knowledge graph loaded)
MCP      : http://localhost:${MCP_PORT}/mcp/   (attach your own harness)

Point your own harness (Claude Desktop / Cursor / VS Code) at the graph with:
  { "mcpServers": { "memgraph": { "url": "http://localhost:${MCP_PORT}/mcp/" } } }
EOF

# ---- 4. Optional: the official agentic app (LLM picks the pipeline) ----------
# Needs an OpenAI API key (raw OpenAI calls) and Python 3.10-3.13. The demo pins
# deps (tiktoken, sentence-transformers) that only ship wheels for <=3.13; on 3.14+
# pip would build from source and fail, so pick the newest compatible interpreter.
if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  cat <<EOF

To also run the agentic app (an LLM agent that classifies each question and picks
one of the three pipelines above), set an OpenAI key and re-run:
  export OPENAI_API_KEY=sk-...
  ./agentic-graphrag.sh

Tear everything down when you are done:
  ./agentic-graphrag.sh clean
EOF
  exit 0
fi

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
  echo "OPENAI_API_KEY is set but no Python 3.10-3.13 found for the agentic app." >&2
  echo "Install one (e.g. brew install python@3.13); the pipelines above already ran." >&2
  exit 1
fi

log "Creating a Python virtualenv ($("$PYBIN" --version)) and installing the demo's dependencies"
echo "(sentence-transformers pulls in PyTorch, first install can take a few minutes)"
rm -rf "$WORK/venv"
"$PYBIN" -m venv "$WORK/venv"
# shellcheck disable=SC1091
source "$WORK/venv/bin/activate"
pip install --quiet --upgrade pip
pip install --quiet -r "$APP_DIR/requirements.txt"

# The demo reads OPENAI_API_KEY from a .env in the app directory.
printf 'OPENAI_API_KEY=%s\n' "$OPENAI_API_KEY" > "$APP_DIR/.env"

cat <<EOF

$(printf '\033[1;32m✓ Launching the agentic app.\033[0m') It opens at http://localhost:8501.
On first run it builds embeddings, communities, and summaries in Memgraph, then
lets you ask questions and watch the agent choose a pipeline per query.

Press Ctrl+C to stop the app; containers keep running.
EOF

cd "$APP_DIR"
streamlit run agenticGraphRAG.py

cat <<EOF

App stopped. Memgraph and the MCP server are still running so you can re-launch:
  source "$WORK/venv/bin/activate" && cd "$APP_DIR" && streamlit run agenticGraphRAG.py

Tear everything down when you are done:
  ./agentic-graphrag.sh clean
EOF
