# AI Memory with Memgraph

> Vector Memory Forgets. Graphs Don't.

LLMs are stateless, so they need an external memory. Vector memory retrieves what
*sounds* similar, not what is structurally relevant given the full history. On
Memgraph ([memgraph.com/ai-memory](https://memgraph.com/ai-memory)) memory is a
**graph** of entities and typed relationships you traverse, so recall follows the
actual connections between what the system knows, did, and knows how to do.

Memgraph models three kinds of long-term memory as one unified graph:

| Memory type | What it holds | How it is stored |
| --- | --- | --- |
| **Semantic** | What the system **knows** (facts, preferences) | Entities with typed relationships |
| **Episodic** | What the system **experienced** (past interactions, time) | Interaction nodes encoding sequence and consequence |
| **Procedural** | What the system **knows how to do** (workflows) | Steps as nodes, transitions as edges |

The value is the **interconnection**: *semantic fact → episodic event →
procedural response*. This example seeds all three for the page's own scenario
and answers it by traversal.

## High-level Plan

1. **Spin up** the memory store (Memgraph) and the MCP server your harness loads.
2. **Write** the three memory types for a client the assistant has worked with.
3. **Recall** each type, then all three together to answer *"Schedule a follow-up
   with the client like last time."*

## What You Need

- **Docker**: https://docs.docker.com/get-docker/

That is it. No API keys and no Python: everything runs through Memgraph's own
images (`memgraph-mage`, `mcp-memgraph`, `mgconsole`). This is the "build custom"
path from the page (Cypher, MAGE, MCP).

## Run It

macOS / Linux:

```bash
./ai-memory.sh          # bring everything up, seed memory, run recall
./ai-memory.sh clean    # stop and remove everything the script created
```

Windows (PowerShell 5.1 or 7+), same steps, same output:

```powershell
.\ai-memory.ps1          # bring everything up, seed memory, run recall
.\ai-memory.ps1 clean    # stop and remove everything the script created
```

If Windows blocks the script, allow local scripts for the session first:
`Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`.

## Step-by-step

### 1. Spin up Memgraph and the MCP server

Memgraph starts with schema info enabled (so the ontology is queryable), and the
MCP server, the tool your harness loads to read and write memory, is pointed at it:

```bash
docker network create aimemory-net

docker run -d --name aimemory-memgraph --network aimemory-net \
  -p 7687:7687 -p 7444:7444 \
  memgraph/memgraph-mage:3.12.0 --schema-info-enabled=True

docker run -d --name aimemory-mcp --network aimemory-net \
  -p 8000:8000 --env MEMGRAPH_URL=bolt://aimemory-memgraph:7687 \
  memgraph/mcp-memgraph:0.2.0
```

### 2. Write the three memory types

The assistant has met a client before and knows how to schedule follow-ups. That
knowledge is split across the three memories:

```cypher
// Semantic: what the system KNOWS
MERGE (c:Client {name: "Acme Corp"}) SET c.contact = "Dana Lee", c.timezone = "America/New_York";
MERGE (p:Preference {kind: "meeting_length", value: "30 min"});
MATCH (c:Client {name:"Acme Corp"}), (p:Preference {kind:"meeting_length"}) MERGE (c)-[:PREFERS]->(p);

// Episodic: what the system EXPERIENCED (with a sequence edge)
MERGE (m1:Interaction {id:"int-1", weekday:"Tuesday", duration:"30 min", when:"2026-06-30", summary:"kickoff"});
MERGE (m2:Interaction {id:"int-2", weekday:"Tuesday", duration:"30 min", when:"2026-07-07", summary:"follow-up"});
MATCH (m1:Interaction {id:"int-1"}), (m2:Interaction {id:"int-2"}) MERGE (m1)-[:NEXT]->(m2);

// Procedural: what the system KNOWS HOW TO DO (steps + transitions)
MERGE (w:Workflow {name:"schedule_follow_up"});
MERGE (s1:Step {name:"book calendar slot"}); MERGE (s2:Step {name:"send invite"});
MATCH (w:Workflow {name:"schedule_follow_up"}), (s1:Step {name:"book calendar slot"}) MERGE (w)-[:STARTS_WITH]->(s1);
MATCH (s1:Step {name:"book calendar slot"}), (s2:Step {name:"send invite"}) MERGE (s1)-[:THEN]->(s2);
```

### 3. Recall

Each memory type is a small traversal:

```cypher
-- Semantic: what do we know about the client?
MATCH (c:Client {name:"Acme Corp"})-[:PREFERS]->(p:Preference)
RETURN c.contact, c.timezone, p.value;

-- Episodic: what happened last time?
MATCH (i:Interaction)-[:WITH]->(:Client {name:"Acme Corp"})
RETURN i.when, i.weekday, i.duration ORDER BY i.when DESC LIMIT 1;

-- Procedural: how do we schedule a follow-up?
MATCH (:Workflow {name:"schedule_follow_up"})-[:STARTS_WITH]->(first:Step)
MATCH p=(first)-[:THEN*0..]->(s:Step)
WITH s, length(p) AS ord ORDER BY ord RETURN collect(s.name) AS steps;
```

The payoff is the **interconnected** recall, one traversal that joins all three to
answer *"schedule a follow-up with the client like last time"*:

```cypher
MATCH (c:Client {name:"Acme Corp"})
MATCH (last:Interaction)-[:WITH]->(c)
WITH c, last ORDER BY last.when DESC LIMIT 1
MATCH (:Workflow {name:"schedule_follow_up"})-[:STARTS_WITH]->(f:Step)
MATCH pth=(f)-[:THEN*0..]->(st:Step)
WITH c, last, st, length(pth) AS o ORDER BY o
RETURN c.contact AS client, c.timezone AS timezone,
       last.weekday AS like_last_time_day, last.duration AS duration,
       collect(st.name) AS actions;
```

It returns *Dana Lee, America/New_York, Tuesday, 30 min, [book calendar slot,
send invite]*, everything needed for the assistant to reply *"Done. 30 min Tuesday
slot booked, invite sent."*

### 4. Inspect the memory ontology

`SHOW SCHEMA INFO` returns the whole ontology (labels, relationship types,
properties) in constant time, so an agent can learn the shape of memory before
querying it:

```cypher
SHOW SCHEMA INFO;
```

### 5. Explore visually (optional)

```bash
docker run -d --name aimemory-lab --network aimemory-net -p 3000:3000 \
  -e QUICK_CONNECT_MG_HOST=aimemory-memgraph -e QUICK_CONNECT_MG_PORT=7687 \
  memgraph/lab:3.12.0
# open http://localhost:3000  ->  MATCH p=()-[]-() RETURN p;
```

## Wire It Into a Real Harness

The seeding above did by hand what your assistant should do automatically. Point
an MCP-capable harness (Claude Desktop, Cursor, VS Code, ...) at the running MCP
server and it can call `run_query`, `get_schema`, and the other tools to write new
semantic/episodic/procedural memory and recall it:

```json
{
  "mcpServers": {
    "memgraph-memory": {
      "url": "http://localhost:8000/mcp/"
    }
  }
}
```

A hook in your harness that writes each session's facts, events, and workflows
through `run_query` on exit is the "plugin that collects sessions." On the next
session, the assistant reads that memory back before it starts.

## Clean Up

```bash
./ai-memory.sh clean          # .\ai-memory.ps1 clean  on Windows
# and, if you started Lab:
docker rm -f aimemory-lab
```

## Where to Go Next

- [Memgraph AI Memory](https://memgraph.com/ai-memory) (the three memory types and
  the graph-vs-vector argument).
- Add **semantic recall by similarity**: store an embedding per memory node and use
  Memgraph [vector search](https://memgraph.com/docs/querying/vector-search)
  (`search_node_vectors` is exposed by the MCP server) alongside traversal.
- Retrieve memory with the same [GraphRAG](https://memgraph.com/graphrag) pipelines
  (Text2Cypher, pivot search, query-focused summarisation); see
  `agentic-graphrag.sh` in this folder.
- Read the [Memgraph MCP server](https://memgraph.com/blog/introducing-memgraph-mcp-server)
  and [AI ecosystem](https://memgraph.com/docs/ai-ecosystem) docs.
