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
| **Semantic** | What the system **knows** (facts, preferences) | `(:User)-[:HAS_MEMORY]->(:Memory)` |
| **Episodic** | What the system **experienced** (past interactions, time) | `(:Session)-[:HAS_ACTION]->(:Action)`, sequenced by `FOLLOWED_BY` |
| **Procedural** | What the system **knows how to do** (workflows) | `(:Session)-[:USED_SKILL]->(:Skill)` |

This example writes and reads all three through the actual
[Context Graph](https://github.com/memgraph/ai-toolkit/tree/main/context-graph)
packages a live coding-assistant plugin uses — `sessions-graph`, `actions-graph`,
`skills-graph` — instead of a hand-rolled schema. The `(:User)`/`(:Session)`
nodes those three packages share are the join key, so the payoff is a genuine
graph traversal, not three separate lookups glued together.

## High-level Plan

1. **Spin up** the memory store (Memgraph).
2. **Write** the three memory types for a client the assistant has worked with,
   through `sessions-graph`/`actions-graph`/`skills-graph`.
3. **Recall** each type, then all three together to answer *"Schedule a
   follow-up with the client like last time."*

## What You Need

- **Docker**: https://docs.docker.com/get-docker/
- **Python 3.10-3.13**: https://www.python.org/downloads/ (installs the three
  Context Graph packages above from PyPI into a throwaway virtualenv — no
  repository checkout needed)

No API keys: this example writes structured memory directly, the same way an
application would call these packages. Automatic, LLM-backed extraction from
raw conversation text is a separate, opt-in step — see
[Where to Go Next](#where-to-go-next).

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

### 1. Spin up Memgraph

Memgraph starts with schema info enabled, so the ontology is queryable once the
Context Graph packages have written into it:

```bash
docker network create aimemory-net

docker run -d --name aimemory-memgraph --network aimemory-net \
  -p 7687:7687 -p 7444:7444 \
  memgraph/memgraph-mage:3.12.0 --schema-info-enabled=True
```

### 2. Install the Context Graph memory packages

```bash
python3 -m venv .ai-memory-venv
.ai-memory-venv/bin/pip install sessions-graph actions-graph skills-graph memgraph-toolbox
```

### 3. Write the three memory types

The assistant has met a client before and knows how to schedule follow-ups.
That knowledge is split across three packages, glued together by a shared
`(:User {user_id})` and two `(:Session {session_id})` nodes
(`session-acme-kickoff`, `session-acme-followup`) — see `ai-memory.py`:

```python
# Episodic: two real sessions, each with a ToolCall/ToolResult (actions-graph)
actions.create_session(Session(session_id="session-acme-kickoff", ...))
actions.create_session(Session(session_id="session-acme-followup", ...))
actions.record_tool_call(session_id=..., tool_name="schedule_meeting", tool_input={...})
actions.record_tool_result(session_id=..., tool_use_id=..., tool_name="schedule_meeting", ...)

# Semantic: a durable fact about the client (sessions-graph)
memories.save_memory(
    user_id="acme-corp",
    content="Acme Corp's contact is Dana Lee (timezone America/New_York); they prefer 30-minute meetings.",
    session_id="session-acme-kickoff",
)

# Procedural: a reusable skill, used during the follow-up session (skills-graph)
skills.add_skill(Skill(name="schedule-follow-up", description="...", content="1. Book a calendar slot...\n2. Send a calendar invite."))
skills.record_skill_usage(session_id="session-acme-followup", skill_name="schedule-follow-up", action="used", timestamp=...)
```

Run it:

```bash
MEMGRAPH_URL=bolt://localhost:7687 .ai-memory-venv/bin/python ai-memory.py
```

### 4. Recall

Each memory type is a small, package-provided lookup:

```python
memories.get_memories("acme-corp")               # semantic
actions.list_sessions(limit=1)                    # episodic: most recent session
actions.get_session_actions(session.session_id)   # ... and what happened in it
skills.get_skill("schedule-follow-up")            # procedural
```

The payoff is the **interconnected** recall: one Cypher traversal through the
shared `User`/`Session` nodes joins all three to answer *"schedule a follow-up
with the client like last time"*:

```cypher
MATCH (u:User {user_id: "acme-corp"})-[:HAS_MEMORY]->(mem:Memory)
MATCH (u)-[:HAD_SESSION]->(s:Session)-[:HAS_ACTION]->(a:Action {tool_name: "schedule_meeting"})
WITH u, mem, s, a ORDER BY s.started_at DESC LIMIT 1
OPTIONAL MATCH (s)-[:USED_SKILL]->(sk:Skill)
RETURN mem.content AS client_facts, s.session_id AS last_session,
       a.timestamp AS last_meeting_at, sk.name AS skill, sk.content AS how_to
```

It returns *Dana Lee's Acme Corp facts, the `session-acme-followup` session,
the `schedule-follow-up` skill and its steps* — everything needed for the
assistant to reply *"Done. 30 min Tuesday slot booked, invite sent."*

### 5. Inspect the memory ontology

`SHOW SCHEMA INFO` returns the whole ontology (labels, relationship types,
properties) in constant time, so an agent can learn the shape of memory before
querying it — now the real `User`/`Session`/`Memory`/`Action`/`Skill` schema
the Context Graph packages created, not a demo-only schema:

```cypher
SHOW SCHEMA INFO;
```

### 6. Explore visually (optional)

```bash
docker run -d --name aimemory-lab --network aimemory-net -p 3000:3000 \
  -e QUICK_CONNECT_MG_HOST=aimemory-memgraph -e QUICK_CONNECT_MG_PORT=7687 \
  memgraph/lab:3.12.0
# open http://localhost:3000  ->  MATCH p=()-[]-() RETURN p;
```

## Wire It Into a Real Harness

The seeding above did by hand what a real coding-assistant plugin does
automatically. For Claude Code, one script installs and wires the
[Context Graph](https://github.com/memgraph/ai-toolkit/tree/main/context-graph)
plugin end to end, defaulting to this same Memgraph instance
(`bolt://localhost:7687`, no auth, database `memgraph`):

```bash
curl -fsSL https://raw.githubusercontent.com/memgraph/ai-toolkit/main/context-graph/scripts/install.sh | bash
```

It registers the Claude Code plugin marketplace and installs the plugin —
the step a bare `agent-context-graph bootstrap` can't do, since that's what
actually wires hooks into Claude Code — installs the CLI with all three
connectors, sets your identity, and verifies with `doctor`. It even starts
Memgraph itself if nothing's reachable, so on a clean machine it doubles as
an alternative to steps 1–2 above. Override identity with
`AGENT_CONTEXT_GRAPH_USER_ID` (defaults to `git config user.name`); see the
[Context Graph guide](https://github.com/memgraph/ai-toolkit/blob/main/context-graph/README.md#getting-started-claude-code)
for the rest of the configurable env vars and defaults, Codex setup (no
non-interactive plugin-install step there yet), reconciliation, and
cross-component queries.

Every real session then writes `Memory`/`Action`/`Skill` nodes automatically —
the same nodes `ai-memory.py` just wrote by hand — and the next session reads
that memory back before it starts.

## Clean Up

```bash
./ai-memory.sh clean          # .\ai-memory.ps1 clean  on Windows
# and, if you started Lab:
docker rm -f aimemory-lab
```

## Where to Go Next

- [Memgraph AI Memory](https://memgraph.com/ai-memory) (the three memory types and
  the graph-vs-vector argument).
- Turn on **automatic, LLM-backed extraction**: this example wrote Memory nodes
  by hand; `sessions-graph`'s reconciliation step instead extracts entities
  from real session transcripts via `unstructured2graph` + LightRAG — see
  [sessions-graph § reconciliation](https://github.com/memgraph/ai-toolkit/blob/main/context-graph/sessions-graph/README.md#session-reconciliation).
- Add **semantic recall by similarity**: `sessions-graph` already maintains a
  full-text index over `Memory.content`; pair it with Memgraph
  [vector search](https://memgraph.com/docs/querying/vector-search) for
  embedding-based recall alongside traversal.
- Retrieve memory with the same [GraphRAG](https://memgraph.com/graphrag) pipelines
  (Text2Cypher, pivot search, query-focused summarisation); see
  `agentic-graphrag.sh` in this folder.
- Read the [Context Graph](https://github.com/memgraph/ai-toolkit/tree/main/context-graph)
  project docs and [AI ecosystem](https://memgraph.com/docs/ai-ecosystem) docs.
