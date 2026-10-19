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

[Context Graph](https://github.com/memgraph/ai-toolkit/tree/main/context-graph)
does this for your coding agents (Claude Code, Codex, Copilot CLI, Cursor,
OpenCode, Antigravity CLI, Grok Build): it records their sessions into a Memgraph
as those three kinds of memory, so they can recall them later.

## Run It

`ai-memory.sh` is only the entry point. It says what is about to
happen and starts Context Graph's setup, which draws the Memgraph logo and does
the rest: finds or starts Memgraph, and connects the agents you pick. It asks before it changes
anything.

macOS / Linux:

```bash
curl -sSL https://install.memgraph.com/ai-memory | bash
```

Windows (PowerShell 5.1 or 7+):

```powershell
iwr https://install.memgraph.com/ai-memory/windows -useb | iex
```

The setup needs a terminal to ask its questions on. Without one (CI, output sent
to a file), or with `AI_MEMORY_SKIP_SETUP=1`, the script only prints the command:

```bash
curl -fsSL https://raw.githubusercontent.com/memgraph/ai-toolkit/main/context-graph/scripts/install.sh | bash
```

or, on Windows, `iwr https://raw.githubusercontent.com/memgraph/ai-toolkit/main/context-graph/scripts/install.ps1 -useb | iex`.

## After Setup

- `memgraph-context-graph ui` shows what your agents capture, in the terminal.
- `memgraph-context-graph setup` again changes your choices; it skips what is
  already done.
- `memgraph-context-graph uninstall` undoes the wiring.

See the
[Context Graph guide](https://github.com/memgraph/ai-toolkit/blob/main/context-graph/README.md#getting-started)
for the rest, including how to look at the graph itself in Memgraph Lab.

## Where to Go Next

- [Memgraph AI Memory](https://memgraph.com/ai-memory) (the three memory types and
  the graph-vs-vector argument).
- Retrieve memory with the same [GraphRAG](https://memgraph.com/graphrag) pipelines
  (Text2Cypher, pivot search, query-focused summarisation); see
  `agentic-graphrag.sh` in this folder.
- Read the [Context Graph](https://github.com/memgraph/ai-toolkit/tree/main/context-graph)
  project docs and [AI ecosystem](https://memgraph.com/docs/ai-ecosystem) docs.
