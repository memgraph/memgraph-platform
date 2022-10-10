<p align="center">
  <img src="https://uploads-ssl.webflow.com/5e7ceb09657a69bdab054b3a/5e7ceb09657a6937ab054bba_Black_Original%20_Logo.png" width="300"/>
</p>
<p align="center">Download everything you need to run Memgraph in one Docker image.</p>

<p align="center">
  <a href="https://github.com/memgraph/memgraph-platform/blob/main/LICENSE">
    <img src="https://img.shields.io/github/license/memgraph/memgraph-platform?style=plastic" alt="license" title="license"/>
  <a href="https://hub.docker.com/r/memgraph/memgraph-platform">
    <img src="https://img.shields.io/docker/v/memgraph/memgraph-platform" alt="dockerhub" title="dockerhub"/>
  </a>
</p>

## :clipboard: Description

This repository serves as a docker package builder for the Memgraph ecosystem.
It works by combining
[MemgraphDB](https://github.com/memgraph/memgraph-platform), [Memgraph
Lab](https://github.com/memgraph/lab),
[mgconsole](https://github.com/memgraph/mgconsole) and
[MAGE](https://github.com/memgraph/mage) into one container and running the
processes with supervisor. First, it builds Memgraph Lab in separate node
containers and then transfers it to Debian, where MAGE is built on top of a
Debian package.

You can start Memgraph Platform with:

```
docker run -it --rm -p 3000:3000 -p 7687:7687 memgraph/memgraph-platform
```

## :hourglass: Versioning

New versioning is transparent in the sense that we explicitly state which
version of software is included, and it looks like this:

`memgraph/memgraph-platform:2.5.0-memgraph2.4-lab2.2.2-mage1.3.5`

and just by looking at each of the Memgraph Platform version, you can know which
versions of software it contains without looking at details in release notes.

### :no_entry_sign: Old (Deprecated)

This versioning is deprecated and was used until v2.4.0 Memgraph Platform.

We have decided that major and minor versions of Memgraph Platform will follow
Memgraph versioning. And the patch version will be followed with any
update from Mage or Memgraph Lab, or updates on Memgraph Platform itself.

In other words if we have `memgraph-platform:2.2.0`, it means it contains Memgraph
2.2 version and compatible versions of Mage and Memgraph Lab.

### :whale: Docker build

1. Run `docker build . -t test`
2. Run `docker run --rm -it -p 3000:3000 -p 7687:7687 memgraph-platform:latest`
3. Go to `http://localhost:3000` and connect to Memgrpah database with Memgraph
  Lab in order to test it out

<p align="center">
  <a href="#">
    <img src="https://img.shields.io/badge/⬆️back_to_top_⬆️-white" alt="Back to top" title="Back to top"/>
  </a>
</p>
