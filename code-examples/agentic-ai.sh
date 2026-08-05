#!/usr/bin/env bash
#
# Agentic AI with Memgraph: runnable end-to-end example.
#
# Aligned with https://memgraph.com/agentic-ai : "Agents That Plan. Not Prompt."
# An agent models its problem as a REASONING GRAPH and plans by traversal instead
# of by prompting:
#   - nodes      = states / decision points
#   - edges      = available actions
#   - properties = scores (expected value, success rate, feasibility)
# The traversed path is an inspectable, auditable trace; alternatives are scored
# and compared. Four graph operations replace LLM guesswork:
#   1. Weighted traversal  - evaluate multi-step plans without LLM calls
#   2. Shortest path       - most efficient route to a goal
#   3. Centrality          - find the critical intermediate states
#   4. Community detection - group related sub-tasks for parallel execution
#
# The page also stresses MULTI-AGENT coordination over SHARED STATE. That shared
# layer is Memgraph Zero / MemGQL: a federated GQL engine (one Bolt + GQL
# endpoint) in front of many backends, so a fleet of agents reaches the same data
# without ETL. Here MemGQL federates:
#   - Memgraph   : the reasoning graph the agents PLAN over (+ MAGE algorithms)
#   - PostgreSQL : customer records the agents pull as shared context
# Graph-native planning (MAGE, weighted shortest path) runs in Memgraph directly;
# MemGQL gives every agent one endpoint to that shared state plus other sources.
#
# Uses ONLY the Memgraph ecosystem (+ stock postgres, one of Zero's connectors):
#   memgraph/memgraph-mage, memgraph/memgql, memgraph/mgconsole, postgres
#
# Requirements: Docker only. No API keys.
#   Docker: https://docs.docker.com/get-docker/
#
# Usage:
#   ./agentic-ai.sh          # bring up the shared layer + reasoning graph, plan
#   ./agentic-ai.sh clean    # stop and remove everything this script created

set -euo pipefail

# ---- Pinned versions --------------------------------------------------------
MAGE_IMAGE="memgraph/memgraph-mage:3.12.0"
MEMGQL_IMAGE="memgraph/memgql:0.7.0"
MGCONSOLE_IMAGE="memgraph/mgconsole:1.6.0"
POSTGRES_IMAGE="postgres:18"

# Demo-scoped names so this never collides with your own containers/networks.
NET="zero-demo-net"
MEMGRAPH="zero-demo-memgraph"
POSTGRES="zero-demo-postgres"
MEMGQL="zero-demo-memgql"

WORK="$(cd "$(dirname "$0")" && pwd)/.memgql-work"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

# mg() plans over the reasoning graph in Memgraph directly (port 7687, MAGE).
mg()     { docker run -i --rm --network "$NET" "$MGCONSOLE_IMAGE" --host "$MEMGRAPH" --port 7687; }
# memgql() is the shared, federated endpoint every agent connects to (port 7688).
memgql() { docker run -i --rm --network "$NET" "$MGCONSOLE_IMAGE" --host "$MEMGQL"    --port 7688; }

teardown() {
  log "Stopping and removing containers + network + work dir"
  docker rm -f "$MEMGQL" "$MEMGRAPH" "$POSTGRES" >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
  rm -rf "$WORK"
  echo "Cleaned up."
}

if [[ "${1:-}" == "clean" ]]; then
  teardown
  exit 0
fi

command -v docker >/dev/null 2>&1 || {
  echo "Docker is required: https://docs.docker.com/get-docker/" >&2
  exit 1
}

# ---- Reset any previous run -------------------------------------------------
docker rm -f "$MEMGQL" "$MEMGRAPH" "$POSTGRES" >/dev/null 2>&1 || true
docker network create "$NET" >/dev/null 2>&1 || true

# ---- Generate the Postgres seed + the relational->graph mapping -------------
mkdir -p "$WORK"

# Postgres source: customer records the agents pull as shared context.
cat > "$WORK/init.sql" <<'SQL'
CREATE TABLE customers (id SERIAL PRIMARY KEY, name TEXT, tier TEXT);
CREATE TABLE companies (id SERIAL PRIMARY KEY, name TEXT);
CREATE TABLE works_at  (id SERIAL PRIMARY KEY, customer_id INT REFERENCES customers(id), company_id INT REFERENCES companies(id));

INSERT INTO customers (name, tier) VALUES ('Ada Lovelace', 'enterprise'), ('Linus T.', 'standard'), ('Grace H.', 'enterprise');
INSERT INTO companies (name)       VALUES ('Acme Corp'), ('Globex');
INSERT INTO works_at (customer_id, company_id) VALUES (1, 1), (2, 2), (3, 1);
SQL

# MemGQL mapping: how the Postgres tables become graph nodes and edges.
cat > "$WORK/mapping.json" <<'JSON'
{
  "nodes": [
    { "label": "Customer", "table": "customers", "id_column": "id", "properties": { "name": "name", "tier": "tier" } },
    { "label": "Company",  "table": "companies", "id_column": "id", "properties": { "name": "name" } }
  ],
  "edges": [
    { "rel_type": "WORKS_AT", "table": "works_at", "id_column": "id", "source_column": "customer_id", "target_column": "company_id", "source_label": "Customer", "target_label": "Company" }
  ]
}
JSON

# ---- 1. Start the shared data layer (Memgraph + Postgres + MemGQL) ----------
# Backends are reached only by MemGQL over the internal network, so their ports
# are not published to the host, agents talk to the single MemGQL endpoint (7688).
log "Starting Memgraph backend ($MAGE_IMAGE) - hosts the reasoning graph"
docker run -d --name "$MEMGRAPH" --network "$NET" \
  "$MAGE_IMAGE" --schema-info-enabled=True --log-level=TRACE --also-log-to-stderr >/dev/null

log "Starting PostgreSQL backend ($POSTGRES_IMAGE) - hosts customer records"
docker run -d --name "$POSTGRES" --network "$NET" \
  -e POSTGRES_PASSWORD=postgres \
  -v "$WORK/init.sql":/docker-entrypoint-initdb.d/init.sql \
  "$POSTGRES_IMAGE" >/dev/null

log "Waiting for Memgraph"
until echo "RETURN 1;" | mg >/dev/null 2>&1; do sleep 1; done
log "Waiting for PostgreSQL"
until docker exec "$POSTGRES" pg_isready -U postgres >/dev/null 2>&1; do sleep 1; done

# ---- 2. Seed the reasoning graph (states + scored actions) ------------------
# A customer-support agent's plan space: states are nodes, actions are edges, and
# each action carries a score (expected probability of resolving the ticket).
log "Seeding the customer-support reasoning graph in Memgraph"
mg <<'CYPHER'
MERGE (s0:State {name:"Ticket received"});
MERGE (s1:State {name:"Assess severity"});
MERGE (a:State  {name:"Auto-resolve"});
MERGE (e:State  {name:"Escalate to human"});
MERGE (r:State  {name:"Request more info"});
MERGE (d:State  {name:"Resolved"});
MATCH (s0:State{name:"Ticket received"}),(s1:State{name:"Assess severity"}) MERGE (s0)-[:ACTION {name:"triage",       score:1.0}]->(s1);
MATCH (s1:State{name:"Assess severity"}),(a:State{name:"Auto-resolve"})     MERGE (s1)-[:ACTION {name:"auto_resolve", score:0.87}]->(a);
MATCH (s1:State{name:"Assess severity"}),(e:State{name:"Escalate to human"})MERGE (s1)-[:ACTION {name:"escalate",     score:0.54}]->(e);
MATCH (s1:State{name:"Assess severity"}),(r:State{name:"Request more info"})MERGE (s1)-[:ACTION {name:"request_info", score:0.31}]->(r);
MATCH (a:State{name:"Auto-resolve"}),(d:State{name:"Resolved"})             MERGE (a)-[:ACTION {name:"close",        score:0.92}]->(d);
MATCH (e:State{name:"Escalate to human"}),(d:State{name:"Resolved"})        MERGE (e)-[:ACTION {name:"human_fix",    score:0.95}]->(d);
MATCH (r:State{name:"Request more info"}),(s1:State{name:"Assess severity"})MERGE (r)-[:ACTION {name:"reassess",     score:0.60}]->(s1);
CYPHER

# ---- 3. Memgraph Zero: put MemGQL in front of both sources ------------------
log "Starting MemGQL ($MEMGQL_IMAGE) - the shared federated endpoint (Bolt on 7688)"
docker run -d --name "$MEMGQL" --network "$NET" --stop-timeout 2 -p 7688:7688 \
  --env CONNECTOR_TYPE=multi \
  --env BOLT_LISTEN_ADDR=0.0.0.0:7688 \
  -v "$WORK/mapping.json":/data/mapping.json \
  "$MEMGQL_IMAGE" >/dev/null

log "Waiting for MemGQL"
until echo "RETURN 1;" | memgql >/dev/null 2>&1; do sleep 1; done

log "Registering connectors: 'mg' (reasoning graph) and 'pg' (customer records)"
memgql <<CYPHER
ADD CONNECTOR mg TYPE memgraph URI '${MEMGRAPH}:7687' GRAPH memgraph;
CONNECT mg AS mg_conn;
ADD MAPPING social FROM '/data/mapping.json';
ADD CONNECTOR pg TYPE postgres URI 'host=${POSTGRES} user=postgres password=postgres dbname=postgres' MAPPING social;
CONNECT pg AS pg_conn;
CYPHER

# ---- 4. Shared context: agents pull records through the one endpoint --------
# Multi-agent coordination: every agent reads the same federated layer. Here an
# agent fetches customer context from Postgres, through MemGQL, with no ETL.
log "Agent reads shared context: enterprise customers (Postgres, via MemGQL)"
memgql <<'CYPHER'
USE CONNECTION pg_conn
  MATCH (c:Customer)-[:WORKS_AT]->(co:Company)
  WHERE c.tier = 'enterprise'
  RETURN c.name AS customer, c.tier AS tier, co.name AS company
  ORDER BY customer;
CYPHER

# ---- 5. Plan over the reasoning graph (no prompting) ------------------------
# These run natively in Memgraph (MAGE + weighted shortest path).
log "Plan 1/4 - Weighted traversal: rank full resolution plans by expected value (no LLM)"
mg <<'CYPHER'
MATCH path=(:State {name:"Ticket received"})-[rels:ACTION *1..6]->(:State {name:"Resolved"})
RETURN [n IN nodes(path) | n.name] AS plan,
       round(reduce(p=1.0, r IN rels | p * r.score) * 1000) / 1000 AS expected_value
ORDER BY expected_value DESC LIMIT 4;
CYPHER

log "Audit: chosen path vs the next-best alternative (inspectable trace)"
mg <<'CYPHER'
MATCH path=(:State {name:"Ticket received"})-[rels:ACTION *1..6]->(:State {name:"Resolved"})
WITH [n IN nodes(path) | n.name] AS plan, reduce(p=1.0, r IN rels | p * r.score) AS ev
ORDER BY ev DESC LIMIT 2
RETURN plan, round(ev * 1000) / 1000 AS expected_value;
CYPHER

log "Plan 2/4 - Shortest path: most efficient route to 'Resolved' (weighted, cost = 1 - score)"
mg <<'CYPHER'
MATCH path=(:State {name:"Ticket received"})-[:ACTION *WSHORTEST (e, n | 1.0 - e.score) total_cost]->(:State {name:"Resolved"})
RETURN [x IN nodes(path) | x.name] AS route, round(total_cost * 1000) / 1000 AS cost;
CYPHER

log "Plan 3/4 - Centrality: the critical intermediate state (MAGE betweenness)"
mg <<'CYPHER'
CALL betweenness_centrality.get() YIELD node, betweenness_centrality
RETURN node.name AS state, round(betweenness_centrality * 1000) / 1000 AS centrality
ORDER BY centrality DESC LIMIT 5;
CYPHER

log "Plan 4/4 - Community detection: sub-tasks that can run in parallel (MAGE)"
mg <<'CYPHER'
CALL community_detection.get() YIELD node, community_id
RETURN community_id, collect(node.name) AS states
ORDER BY community_id;
CYPHER

# ---- Wrap up ----------------------------------------------------------------
cat <<EOF

$(printf '\033[1;32m✓ Agents planned over the reasoning graph on a shared data layer.\033[0m')

The plan was chosen by traversal, not prompting: "Ticket received -> Assess
severity -> Auto-resolve -> Resolved" scored highest (expected value 0.8), and
the whole path is an auditable trace you can compare against alternatives.

Every agent reaches the same state through one endpoint (bolt://localhost:7688):
the reasoning graph (Memgraph) and customer records (Postgres), federated with no
ETL. Connect any Bolt tool to explore it (Memgraph Lab, mgconsole, a driver):
  docker run -d --name memgql-lab --network ${NET} -p 3000:3000 \\
    -e QUICK_CONNECT_MG_HOST=${MEMGQL} -e QUICK_CONNECT_MG_PORT=7688 memgraph/lab:3.12.0
  open http://localhost:3000

Give a fleet of agents MCP access to the shared layer (run the Memgraph MCP server
against bolt://localhost:7688; see agentic-graphrag.sh for a working setup):
  { "mcpServers": { "memgraph-zero": { "url": "http://localhost:8000/mcp/" } } }

Notes (MemGQL is early):
  - Native graph analytics (MAGE, weighted shortest path) run in Memgraph itself;
    MemGQL federates pattern queries and pushes them down to each source.
  - Authentication/authorization are not supported yet - keep this local.
  - MemGQL Community allows up to two simultaneous data sources.

Tear everything down:
  ./agentic-ai.sh clean
EOF
