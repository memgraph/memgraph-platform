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
    <a href="https://hub.docker.com/r/memgraph/memgraph-platform">
    <img src="https://img.shields.io/docker/pulls/memgraph/memgraph-platform" alt="dockerhub-pulls" title="dockerhub-pulls"/>
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

There is also a version without MAGE algorithms for those who want minimal image
with only Memgraph and Memgraph Lab.

You can start Memgraph Platform with:

```
docker run -p 3000:3000 -p 7444:7444 -p 7687:7687 --name memgraph memgraph/memgraph-platform
```

### mgconsole

Start `mgconsole` with:

```
# get the running-container-id with `docker ps`
docker exec -ti <running-container-id> mgconsole

# or
docker run -ti --entrypoint=mgconsole memgraph/memgraph-platform
```

When connecting to local Memgraph with `mgconsole` on Windows and Mac, make
sure to provide the following argument `--host host.docker.internal`:

```
docker run -ti --entrypoint=mgconsole memgraph/memgraph-platform --host host.docker.internal
```

### Lab only

Run only the Lab with the following command:

```
docker run -p 3000:3000 memgraph/memgraph-platform -c /etc/supervisor/supervisord-lab-only.conf
```

### Memgraph only

Run only Memgraph with the following command:

```
docker run -p 7687:7687 memgraph/memgraph-platform -c /etc/supervisor/supervisord-memgraph-only.conf
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
2.2 version and compatible versions of MAGE and Memgraph Lab.

### :whale: Docker build

To build docker image, you need to provide two build arguments:

* `TARGETARCH` - a suffix of the specific local Memgraph debian version; for example if
  you have a local debian package `memgraph-2.10-arm64.deb` that you want to build platform for, use
  the following build argument: `--build-arg="TARGETARCH=2.10-arm64"`.

* `NPM_PACKAGE_TOKEN` - npm token to install private libraries that Memgraph Lab uses, set
  it up with the following argument: `--build-arg="NPM_PACKAGE_TOKEN=ghp_6..."`

1. Run `docker build --build-arg="TARGETARCH=..." --build-arg="NPM_PACKAGE_TOKEN=..." . -t memgraph-platform`
2. Run `docker run -p 3000:3000 -p 7687:7687 memgraph-platform`
3. Go to `http://localhost:3000` and connect to Memgraph database with Memgraph
  Lab in order to test it out

<p align="center">
  <a href="#">
    <img src="https://img.shields.io/badge/⬆️back_to_top_⬆️-white" alt="Back to top" title="Back to top"/>
  </a>
</p>
