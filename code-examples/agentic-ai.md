# Agentic AI: Reasoning Graphs on a Shared Data Layer

> Agents That Plan. Not Prompt.

On Memgraph ([memgraph.com/agentic-ai](https://memgraph.com/agentic-ai)) an agent
models its problem as a **reasoning graph** and plans by traversal instead of by
prompting:

- **nodes** = states / decision points
- **edges** = available actions
- **properties** = scores (expected value, success rate, feasibility)

Four graph operations replace LLM guesswork, and the path an agent takes is an
**inspectable, auditable trace** that can be scored against alternatives:

| Operation | What it answers |
| --- | --- |
| **Weighted traversal** | Evaluate multi-step plans without LLM calls |
| **Shortest path** | Most efficient route to a goal |
| **Centrality** | Which intermediate states are critical |
| **Community detection** | Which sub-tasks can run in parallel |

The page also stresses **multi-agent coordination over shared state**. That
shared layer is **Memgraph Zero / MemGQL**: a federated GQL engine that puts one
Bolt + GQL endpoint in front of many backends, so a fleet of agents reaches the
same data with no ETL. This example federates two sources:

- **Memgraph** hosts the **reasoning graph** the agents plan over (plus MAGE algorithms).
- **PostgreSQL** hosts **customer records** the agents pull as shared context.

## High-level Plan

1. **Start the shared data layer**: Memgraph + Postgres, federated by MemGQL.
2. **Seed the reasoning graph** (a customer-support agent's plan space).
3. **Read shared context** through the one MemGQL endpoint (multi-agent coordination).
4. **Plan over the reasoning graph** with the four operations, and audit the choice.

## What You Need

- **Docker**: https://docs.docker.com/get-docker/

Docker only. No API keys. Uses the Memgraph ecosystem plus stock `postgres`
(PostgreSQL is one of MemGQL's supported connectors).

## Run It

macOS / Linux:

```bash
./agentic-ai.sh          # bring up the shared layer + reasoning graph, then plan
./agentic-ai.sh clean    # stop and remove everything the script created
```

Windows (PowerShell 5.1 or 7+), same steps, same output:

```powershell
.\agentic-ai.ps1          # bring up the shared layer + reasoning graph, then plan
.\agentic-ai.ps1 clean    # stop and remove everything the script created
```

If Windows blocks the script, allow local scripts for the session first:
`Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`. The script
bind-mounts two generated files into containers, so the drive it lives on must be
shared with Docker Desktop (**Settings → Resources → File sharing**; `C:\Users` is
shared by default).

## Step-by-step

### 1. Start the shared data layer

Demo-scoped names (`zero-demo-*`) avoid clobbering your own containers. Only
MemGQL's port (`7688`) is published; the backends are reached internally, so
agents talk to a single endpoint:

```bash
docker network create zero-demo-net

docker run -d --name zero-demo-memgraph --network zero-demo-net \
  memgraph/memgraph-mage:3.12.0 --schema-info-enabled=True --log-level=TRACE --also-log-to-stderr

docker run -d --name zero-demo-postgres --network zero-demo-net \
  -e POSTGRES_PASSWORD=postgres \
  -v "$PWD/.memgql-work/init.sql":/docker-entrypoint-initdb.d/init.sql \
  postgres:18

docker run -d --name zero-demo-memgql --network zero-demo-net --stop-timeout 2 -p 7688:7688 \
  --env CONNECTOR_TYPE=multi \
  --env BOLT_LISTEN_ADDR=0.0.0.0:7688 \
  -v "$PWD/.memgql-work/mapping.json":/data/mapping.json \
  memgraph/memgql:0.7.0
```

MemGQL learns about each backend and opens a named connection to it:

```cypher
ADD CONNECTOR mg TYPE memgraph URI 'zero-demo-memgraph:7687' GRAPH memgraph;
CONNECT mg AS mg_conn;

ADD MAPPING social FROM '/data/mapping.json';
ADD CONNECTOR pg TYPE postgres URI 'host=zero-demo-postgres user=postgres password=postgres dbname=postgres' MAPPING social;
CONNECT pg AS pg_conn;
```

### 2. Seed the reasoning graph

States are nodes, actions are scored edges. The score is the expected probability
that the action moves the ticket toward resolution:

```cypher
MERGE (s0:State {name:"Ticket received"});
MERGE (s1:State {name:"Assess severity"});
MERGE (a:State  {name:"Auto-resolve"});
MERGE (e:State  {name:"Escalate to human"});
MERGE (d:State  {name:"Resolved"});
MATCH (s0:State{name:"Ticket received"}),(s1:State{name:"Assess severity"})  MERGE (s0)-[:ACTION {name:"triage", score:1.0}]->(s1);
MATCH (s1:State{name:"Assess severity"}),(a:State{name:"Auto-resolve"})      MERGE (s1)-[:ACTION {name:"auto_resolve", score:0.87}]->(a);
MATCH (s1:State{name:"Assess severity"}),(e:State{name:"Escalate to human"}) MERGE (s1)-[:ACTION {name:"escalate", score:0.54}]->(e);
MATCH (a:State{name:"Auto-resolve"}),(d:State{name:"Resolved"})              MERGE (a)-[:ACTION {name:"close", score:0.92}]->(d);
MATCH (e:State{name:"Escalate to human"}),(d:State{name:"Resolved"})         MERGE (e)-[:ACTION {name:"human_fix", score:0.95}]->(d);
```

### 3. Read shared context through MemGQL

Every agent reads the same federated layer. An agent fetches customer context
from Postgres, through MemGQL, with no copy:

```cypher
USE CONNECTION pg_conn
  MATCH (c:Customer)-[:WORKS_AT]->(co:Company)
  WHERE c.tier = 'enterprise'
  RETURN c.name AS customer, c.tier AS tier, co.name AS company;
```

### 4. Plan over the reasoning graph

These run natively in Memgraph (MAGE and weighted shortest path).

**Weighted traversal** ranks whole plans by expected value, no LLM in the loop:

```cypher
MATCH path=(:State {name:"Ticket received"})-[rels:ACTION *1..6]->(:State {name:"Resolved"})
RETURN [n IN nodes(path) | n.name] AS plan,
       reduce(p=1.0, r IN rels | p * r.score) AS expected_value
ORDER BY expected_value DESC LIMIT 4;
```

The top result, `Ticket received → Assess severity → Auto-resolve → Resolved`
(expected value 0.8), is the **chosen path**; the next row is the scored
**alternative**. Returning both is the audit trail the page describes.

**Shortest path** finds the most efficient route to the goal (cost = `1 - score`):

```cypher
MATCH path=(:State {name:"Ticket received"})-[:ACTION *WSHORTEST (e, n | 1.0 - e.score) total_cost]->(:State {name:"Resolved"})
RETURN [x IN nodes(path) | x.name] AS route, total_cost AS cost;
```

**Centrality** flags the critical intermediate state (here, `Assess severity`):

```cypher
CALL betweenness_centrality.get() YIELD node, betweenness_centrality
RETURN node.name AS state, betweenness_centrality AS centrality
ORDER BY centrality DESC LIMIT 5;
```

**Community detection** groups sub-tasks a fleet of agents can take in parallel:

```cypher
CALL community_detection.get() YIELD node, community_id
RETURN community_id, collect(node.name) AS states ORDER BY community_id;
```

## Give a Fleet of Agents MCP Access

Run the Memgraph MCP server against MemGQL's endpoint (`bolt://localhost:7688`) so
every agent shares the same layer through MCP (see `agentic-graphrag.sh` for a
working MCP setup):

```json
{
  "mcpServers": {
    "memgraph-zero": {
      "url": "http://localhost:8000/mcp/"
    }
  }
}
```

## Notes (MemGQL Is Early)

- **Native analytics run in Memgraph.** MAGE algorithms and weighted shortest path
  execute in Memgraph itself; MemGQL federates pattern queries and pushes them
  down to each source.
- **No auth yet**: keep it local.
- **Two data sources** in MemGQL Community (unlimited in Enterprise).

## Clean Up

```bash
./agentic-ai.sh clean          # .\agentic-ai.ps1 clean  on Windows
# and, if you started Lab:
docker rm -f memgql-lab
```

## Where to Go Next

- [Memgraph Agentic AI](https://memgraph.com/agentic-ai) (reasoning graphs and the
  four planning operations).
- [Memgraph Zero](https://memgraph.com/docs/memgraph-zero) /
  [MemGQL docs](https://memgraph.com/docs/memgraph-zero/memgql) and the
  [complete Docker Compose setup](https://memgraph.com/docs/memgraph-zero/memgql/complete).
- Docs: [betweenness centrality](https://memgraph.com/docs/advanced-algorithms/available-algorithms/betweenness_centrality),
  [community detection](https://memgraph.com/docs/advanced-algorithms/available-algorithms/community_detection),
  [weighted shortest path](https://memgraph.com/docs/advanced-algorithms/deep-path-traversal).
