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
# follow-up with the client like last time") and recalls them by traversal.
#
# Uses ONLY the Memgraph ecosystem (the "build custom" path from the page):
#   - memgraph/memgraph-mage : the graph database that stores the memory
#   - memgraph/mcp-memgraph  : the MCP server your harness loads to read/write it
#   - memgraph/mgconsole     : Memgraph's CLI, used here to seed + query memory
#
# Requirements: Docker only. No API keys, no Python.
#   Docker: https://docs.docker.com/get-docker/
#
# Usage:
#   ./ai-memory.sh          # bring everything up, seed memory, run recall
#   ./ai-memory.sh clean    # stop and remove everything this script created

set -euo pipefail

# ---- Pinned versions (avoid ':latest' drift) --------------------------------
MAGE_IMAGE="memgraph/memgraph-mage:3.12.0"
MCP_IMAGE="memgraph/mcp-memgraph:0.2.0"
MGCONSOLE_IMAGE="memgraph/mgconsole:1.6.0"

NET="aimemory-net"
DB="aimemory-memgraph"
MCP="aimemory-mcp"
BOLT_PORT="7687"
MCP_PORT="8000"

# ---- Helpers ----------------------------------------------------------------
log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

query() {
  # Run one or more Cypher statements (read from stdin) against Memgraph.
  docker run -i --rm --network "$NET" "$MGCONSOLE_IMAGE" \
    --host "$DB" --port "$BOLT_PORT"
}

teardown() {
  log "Stopping and removing containers + network"
  docker rm -f "$MCP" "$DB" >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
  echo "Cleaned up."
}

# ---- clean subcommand -------------------------------------------------------
if [[ "${1:-}" == "clean" ]]; then
  teardown
  exit 0
fi

# ---- 0. Prerequisite check --------------------------------------------------
command -v docker >/dev/null 2>&1 || {
  echo "Docker is required: https://docs.docker.com/get-docker/" >&2
  exit 1
}

# ---- 1a. Spin up Memgraph (the memory store) --------------------------------
log "Creating network + starting Memgraph ($MAGE_IMAGE)"
docker rm -f "$DB" "$MCP" >/dev/null 2>&1 || true
docker network create "$NET" >/dev/null 2>&1 || true

docker run -d --name "$DB" --network "$NET" \
  -p "${BOLT_PORT}:7687" -p 7444:7444 \
  "$MAGE_IMAGE" --schema-info-enabled=True >/dev/null

log "Waiting for Memgraph to accept Bolt connections"
until echo "RETURN 1;" | query >/dev/null 2>&1; do sleep 1; done
echo "Memgraph is up on bolt://localhost:${BOLT_PORT}"

# ---- 1b. Load the harness's memory tool (Memgraph MCP server) ---------------
# Your coding assistant / agent (the "harness") loads this MCP server as a tool.
# It then WRITES what it learns each session and READS it back later. Here we
# start the same server so a harness can attach; the seeding below simulates
# what the harness writes.
log "Starting the Memgraph MCP server ($MCP_IMAGE), the memory tool your harness loads"
docker run -d --name "$MCP" --network "$NET" \
  -p "${MCP_PORT}:8000" \
  --env MEMGRAPH_URL="bolt://${DB}:7687" \
  "$MCP_IMAGE" >/dev/null
echo "MCP server (streamable HTTP) at http://localhost:${MCP_PORT}/mcp/"

# ---- 2. Write the three memory types ----------------------------------------
# Scenario from the page: the assistant has worked with a client before and knows
# how to schedule follow-ups. That knowledge is split across the three memories.
log "Writing semantic, episodic, and procedural memory"
query <<'CYPHER'
CREATE CONSTRAINT ON (c:Client) ASSERT c.name IS UNIQUE;

// --- Semantic memory: what the system KNOWS (facts + preferences) ---
MERGE (c:Client {name: "Acme Corp"}) SET c.contact = "Dana Lee", c.timezone = "America/New_York";
MERGE (p:Preference {kind: "meeting_length", value: "30 min"});
MATCH (c:Client {name:"Acme Corp"}), (p:Preference {kind:"meeting_length"})
  MERGE (c)-[:PREFERS]->(p);

// --- Episodic memory: what the system EXPERIENCED (interactions over time) ---
MERGE (m1:Interaction {id:"int-1", kind:"meeting", weekday:"Tuesday", duration:"30 min", when:"2026-06-30", summary:"kickoff"});
MERGE (m2:Interaction {id:"int-2", kind:"meeting", weekday:"Tuesday", duration:"30 min", when:"2026-07-07", summary:"follow-up"});
MATCH (m1:Interaction {id:"int-1"}), (c:Client {name:"Acme Corp"}) MERGE (m1)-[:WITH]->(c);
MATCH (m2:Interaction {id:"int-2"}), (c:Client {name:"Acme Corp"}) MERGE (m2)-[:WITH]->(c);
MATCH (m1:Interaction {id:"int-1"}), (m2:Interaction {id:"int-2"}) MERGE (m1)-[:NEXT]->(m2);  // sequence

// --- Procedural memory: what the system KNOWS HOW TO DO (a workflow) ---
MERGE (w:Workflow {name:"schedule_follow_up"});
MERGE (s1:Step {name:"book calendar slot"});
MERGE (s2:Step {name:"send invite"});
MATCH (w:Workflow {name:"schedule_follow_up"}), (s1:Step {name:"book calendar slot"}) MERGE (w)-[:STARTS_WITH]->(s1);
MATCH (s1:Step {name:"book calendar slot"}), (s2:Step {name:"send invite"}) MERGE (s1)-[:THEN]->(s2);  // transition
CYPHER
echo "Wrote semantic + episodic + procedural memory."

# ---- 3. Recall each memory type, then all three together --------------------
log "Semantic recall: 'What do we know about the client?'"
query <<'CYPHER'
MATCH (c:Client {name:"Acme Corp"})-[:PREFERS]->(p:Preference)
RETURN c.contact AS client, c.timezone AS timezone, p.value AS preferred_length;
CYPHER

log "Episodic recall: 'What happened last time?' (most recent interaction)"
query <<'CYPHER'
MATCH (i:Interaction)-[:WITH]->(:Client {name:"Acme Corp"})
RETURN i.when AS date, i.weekday AS weekday, i.duration AS duration, i.summary AS summary
ORDER BY i.when DESC LIMIT 1;
CYPHER

log "Procedural recall: 'How do we schedule a follow-up?' (steps in order)"
query <<'CYPHER'
MATCH (:Workflow {name:"schedule_follow_up"})-[:STARTS_WITH]->(first:Step)
MATCH p=(first)-[:THEN*0..]->(s:Step)
WITH s, length(p) AS ord ORDER BY ord
RETURN collect(s.name) AS steps;
CYPHER

log "Interconnected recall: 'Schedule a follow-up with the client like last time.'"
# One traversal joins semantic (client + timezone) + episodic (last meeting) +
# procedural (the workflow steps): semantic fact -> episodic event -> procedural response.
query <<'CYPHER'
MATCH (c:Client {name:"Acme Corp"})
MATCH (last:Interaction)-[:WITH]->(c)
WITH c, last ORDER BY last.when DESC LIMIT 1
MATCH (:Workflow {name:"schedule_follow_up"})-[:STARTS_WITH]->(f:Step)
MATCH pth=(f)-[:THEN*0..]->(st:Step)
WITH c, last, st, length(pth) AS o ORDER BY o
RETURN c.contact AS client, c.timezone AS timezone,
       last.weekday AS like_last_time_day, last.duration AS duration,
       collect(st.name) AS actions;
CYPHER

log "Memory ontology via SHOW SCHEMA INFO (returned in constant time)"
echo "SHOW SCHEMA INFO;" | query || echo "(enable with --schema-info-enabled, already set)"

# ---- Wrap up ----------------------------------------------------------------
cat <<EOF

$(printf '\033[1;32m✓ AI memory is live.\033[0m') The assistant can now answer "like last time"
by traversing: semantic (Acme Corp, New York) -> episodic (last meeting: 30 min,
Tuesday) -> procedural (book calendar slot, send invite).

Explore the memory graph visually with Memgraph Lab:
  docker run -d --name aimemory-lab --network ${NET} -p 3000:3000 \\
    -e QUICK_CONNECT_MG_HOST=${DB} -e QUICK_CONNECT_MG_PORT=7687 memgraph/lab:3.12.0
  open http://localhost:3000     # then run:  MATCH p=()-[]-() RETURN p;

Wire the memory into a real harness (so it collects sessions automatically).
Add this to your MCP client config (e.g. Claude Desktop / Cursor / VS Code):

  {
    "mcpServers": {
      "memgraph-memory": {
        "url": "http://localhost:${MCP_PORT}/mcp/"
      }
    }
  }

Your assistant then calls the MCP tools (run_query, get_schema, ...) to write new
semantic/episodic/procedural memory and recall it, exactly as the seeding did.

Tear everything down when you are done:
  ./ai-memory.sh clean
EOF
