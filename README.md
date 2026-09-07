<p align="center">
  <img src="https://uploads-ssl.webflow.com/5e7ceb09657a69bdab054b3a/5e7ceb09657a6937ab054bba_Black_Original%20_Logo.png" width="300"/>
</p>
<p align="center">One command to run it all.</p>

<p align="center">
  <a href="https://github.com/memgraph/memgraph-platform/blob/main/LICENSE">
    <img src="https://img.shields.io/github/license/memgraph/memgraph-platform?style=plastic" alt="license" title="license"/>
</p>

## :runner: Quick start

With Docker running on your system and ports 7687, 7444 and 3000 available, run one of the following commands to download the Memgraph Docker Compose file and start the Memgraph and Memgraph Lab services:

**Linux/macOS**

```
curl -sSL https://install.memgraph.com | bash
```

**Windows**

```
iwr https://install.memgraph.com/windows -useb | iex
```

By running `docker ps`, you'll notice `memgraph-mage` and `memgraph-lab` containers running. If you head over to `localhost:3000`, Quick Connect in Memgraph Lab will detect Memgraph running on your system. Check out the basic [Docker Compose file](./docker-compose.yml) and update it to fit your needs.

To start `mgconsole`, run the following command:

```
# with `docker ps` get the Memgraph container id
docker exec -ti <container-id> mgconsole
```

## :bulb: Code examples

Each example is a self-contained, end-to-end demo: it starts Memgraph in Docker, loads data, and runs real queries. Docker is the only requirement (AI Memory also needs Python 3.10-3.13). The walkthroughs live in [`code-examples/`](./code-examples/README.md).

| Example | Linux/macOS | Windows |
| --- | --- | --- |
| [Agentic AI](./code-examples/agentic-ai.md) | `curl -sSL https://install.memgraph.com/agentic-ai \| bash` | `iwr https://install.memgraph.com/agentic-ai/windows -useb \| iex` |
| [Agentic GraphRAG](./code-examples/agentic-graphrag.md) | `curl -sSL https://install.memgraph.com/agentic-graphrag \| bash` | `iwr https://install.memgraph.com/agentic-graphrag/windows -useb \| iex` |
| [AI Memory](./code-examples/ai-memory.md) | `curl -sSL https://install.memgraph.com/ai-memory \| bash` | `iwr https://install.memgraph.com/ai-memory/windows -useb \| iex` |

The one-liners run the script straight from the web. To tear an example down, run the downloaded script with `clean` (e.g. `./agentic-ai.sh clean` or `.\agentic-ai.ps1 clean`), or run the docker commands the example prints at the end.

## :clipboard: Description

This repository holds the scripts served by [install.memgraph.com](https://install.memgraph.com): the quick start installers ([`init.sh`](./init.sh), [`init.ps1`](./init.ps1)) with their [Docker Compose file](./docker-compose.yml), and the runnable [code examples](./code-examples/). Together they start the Memgraph ecosystem:
- [MemgraphDB](https://github.com/memgraph/memgraph), including the MAGE graph algorithms
- [mgconsole](https://github.com/memgraph/mgconsole)
- [Memgraph Lab](https://memgraph.com/docs/data-visualization)

The Docker images they use:
- [Memgraph Docker image](https://hub.docker.com/r/memgraph/memgraph)
- [Memgraph MAGE Docker image](https://hub.docker.com/r/memgraph/memgraph-mage)
- [Memgraph Lab Docker image](https://hub.docker.com/r/memgraph/lab)

<p align="center">
  <a href="#">
    <img src="https://img.shields.io/badge/⬆️back_to_top_⬆️-white" alt="Back to top" title="Back to top"/>
  </a>
</p>
