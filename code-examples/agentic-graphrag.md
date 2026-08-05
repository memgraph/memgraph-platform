# Agentic GraphRAG with Memgraph

Standard RAG retrieves text chunks by similarity. **GraphRAG** traverses a
knowledge graph to follow multi-hop relationships across entities, giving an LLM
structured context that vector search alone misses. On Memgraph
([memgraph.com/graphrag](https://memgraph.com/graphrag)) the whole retrieval
pipeline runs as **one atomic database operation**, not a distributed system you
orchestrate, which makes each pipeline self-contained and easy for an agent to
generate.

Memgraph frames GraphRAG as **three retrieval pipeline types**, each matched to a
kind of question:

| Pipeline | Question type | Example |
| --- | --- | --- |
| **Text2Cypher** | Analytical | "How many organizations of each type are covered?" |
| **Pivot search + relevance expansion** | Local | "What is connected to NVIDIA?" |
| **Query-focused summarisation** | Global | "What are the main themes overall?" |

This example imports a real knowledge graph and runs **all three pipelines as
atomic Cypher** against it (Docker only). It then optionally launches Memgraph's
official **agentic** GraphRAG app, where an LLM agent classifies each question and
picks the matching pipeline for you. The **Memgraph MCP server** is also started
so your own harness (Claude Desktop, Cursor, VS Code) can query the same graph.

## High-level Plan

1. **Spin up** Memgraph and the Memgraph MCP server.
2. **Load** a knowledge graph (an AskNews finance dataset).
3. **Run the three GraphRAG pipelines** as atomic queries (Analytical, Local, Global).
4. **Optional agent**: let an LLM pick the pipeline, or attach your own MCP harness.

## What You Need

- **Docker**: https://docs.docker.com/get-docker/ (required)
- **git**: https://git-scm.com/downloads (required)
- For the **optional** agentic app only:
  - **Python 3.10–3.13 and pip**: https://www.python.org/downloads/ (the demo's
    pinned deps have no wheels for 3.14+; the script auto-picks a compatible one)
  - **An OpenAI API key**: `export OPENAI_API_KEY=sk-...`

## Run It

macOS / Linux:

```bash
./agentic-graphrag.sh          # import + run the three atomic pipelines (Docker only)
./agentic-graphrag.sh clean    # stop containers and remove the work dir
```

Windows (PowerShell 5.1 or 7+), same steps, same output:

```powershell
.\agentic-graphrag.ps1          # import + run the three atomic pipelines (Docker only)
.\agentic-graphrag.ps1 clean    # stop containers and remove the work dir
```

If Windows blocks the script, allow local scripts for the session first:
`Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`.

To also launch the LLM agent app, set a key first:

```bash
export OPENAI_API_KEY=sk-...
./agentic-graphrag.sh          # runs the pipelines, then opens the app at :8501
```

```powershell
$env:OPENAI_API_KEY = "sk-..."
.\agentic-graphrag.ps1          # runs the pipelines, then opens the app at :8501
```

## Step-by-step

### 1. Spin up Memgraph and the MCP server

Memgraph starts with schema info enabled (so a connected agent can inspect the
graph), and the MCP server is pointed at it:

```bash
docker network create agenticgraphrag-net

docker run -d --name agenticgraphrag-memgraph --network agenticgraphrag-net \
  -p 7687:7687 -p 7444:7444 \
  memgraph/memgraph-mage:3.12.0 --schema-info-enabled=True

docker run -d --name agenticgraphrag-mcp --network agenticgraphrag-net \
  -p 8000:8000 --env MEMGRAPH_URL=bolt://agenticgraphrag-memgraph:7687 \
  memgraph/mcp-memgraph:0.2.0
```

### 2. Load the knowledge graph

The demo ships a `.cypherl` dump. `mgconsole` accepts a bounded amount of input
per call, so the script streams it in batches over the Docker network (the same
idea as the demo's `setup.sh`, but network-based so it behaves the same on Linux,
macOS, and Windows):

```bash
lines=$(wc -l < asknews-finance-graph.cypherl); batch=300; start=1
while [ "$start" -le "$lines" ]; do
  sed -n "${start},$((start + batch - 1))p" asknews-finance-graph.cypherl \
    | docker run -i --rm --network agenticgraphrag-net memgraph/mgconsole:1.6.0 \
        --host agenticgraphrag-memgraph --port 7687
  start=$((start + batch))
done
```

This loads roughly 1,000 nodes and 1,600 relationships (finance entities such as
organizations, people, markets, and events). Swap in your own `.cypherl` to make
the example dataset-agnostic.

### 3. Run the three GraphRAG pipelines

Each pipeline is a single atomic query. This is the core of GraphRAG on Memgraph;
the agent in step 4 just decides which one to run.

**Text2Cypher (Analytical)** turns an analytical question into one aggregating query:

```cypher
MATCH (n:organization) WHERE n.detailed_type IS NOT NULL
RETURN n.detailed_type AS organization_type, count(*) AS count
ORDER BY count DESC LIMIT 8;
```

**Pivot search + relevance expansion (Local)** pivots on a seed entity, then
expands its neighborhood in one traversal. In production the pivot is a native
vector search; here we pivot by name:

```cypher
MATCH (seed {id: 'nvidia'})-[*1..2]-(context)
RETURN DISTINCT context.id AS related_entity, context.main_type AS type
LIMIT 10;
```

**Query-focused summarisation (Global)** ranks the whole graph with PageRank
(MAGE) to surface the central themes an LLM would then summarise:

```cypher
CALL pagerank.get() YIELD node, rank
RETURN node.id AS theme, node.main_type AS type, round(rank * 10000) / 10000 AS importance
ORDER BY importance DESC LIMIT 10;
```

On the AskNews finance graph this surfaces "federal reserve", "us stock market",
and "wall street" as the top themes.

### 4. Optional: let an agent pick the pipeline

**a) The official agentic app.** If `OPENAI_API_KEY` is set, the script creates a
virtualenv, installs the demo's `requirements.txt` (Streamlit, the Neo4j driver,
`sentence-transformers`, `openai`), and launches it:

```bash
streamlit run agenticGraphRAG.py     # http://localhost:8501
```

The agent classifies each question and runs the matching pipeline. It makes
autonomous decisions, so the same question can take different paths across runs.

**b) Your own MCP harness.** The MCP server is already running, so any MCP-capable
assistant can query the same graph. Add to its MCP config:

```json
{
  "mcpServers": {
    "memgraph": {
      "url": "http://localhost:8000/mcp/"
    }
  }
}
```

Your assistant then has tools like `run_query`, `get_schema`, `get_page_rank`,
and `search_node_vectors`, the same building blocks the three pipelines use.

## Clean Up

```bash
./agentic-graphrag.sh clean     # .\agentic-graphrag.ps1 clean  on Windows
```

## Where to Go Next

- [Memgraph GraphRAG](https://memgraph.com/graphrag) (the three pipeline types and
  the atomic retrieval pipeline).
- Blog: [How To Build Agentic GraphRAG?](https://memgraph.com/blog/build-agentic-graphrag-ai)
- Demo source: [memgraph/ai-demos / agentic-graph-rag/agentic](https://github.com/memgraph/ai-demos/tree/main/agentic-graph-rag/agentic)
- Docs: [Memgraph GraphRAG](https://memgraph.com/docs/ai-ecosystem/graph-rag),
  [vector search](https://memgraph.com/docs/querying/vector-search),
  [PageRank](https://memgraph.com/docs/advanced-algorithms/available-algorithms/pagerank).
