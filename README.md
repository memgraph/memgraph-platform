<p align="center">
  <img src="https://uploads-ssl.webflow.com/5e7ceb09657a69bdab054b3a/5e7ceb09657a6937ab054bba_Black_Original%20_Logo.png" width="300"/>
</p>
<p align="center">One command to run it all.</p>

<p align="center">
  <a href="https://github.com/memgraph/memgraph-platform/blob/main/LICENSE">
    <img src="https://img.shields.io/github/license/memgraph/memgraph-platform?style=plastic" alt="license" title="license"/>
</p>

## :runner: Quick start

With Docker running on your system and ports 7687, 7444 and 3000 available, run one of the following commands to download Memgraph Platform Docker Compose file and start Memgraph and Memgraph Lab services:

**Linux/macOS**

```
curl https://install.memgraph.com | sh
```

**Windows**

```
iwr https://windows.memgraph.com | iex
```

By running `docker ps`, you'll notice `memgraph-mage` and `memgraph-lab` containers running. If you head over to `localhost:3000`, Quick Connect in Memgraph Lab will detect Memgraph running on your system. Check out the basic [Docker Compose file](./docker-compose.yml) and update it to fit your needs.

To start `mgconsole`, run the following command:

```
# with `docker ps` get the Memgraph container id 
docker exec -ti <container-id> mgconsole
```

## :clipboard: Description

This repository serves as a Docker package builder for the Memgraph ecosystem, consisting of:
- [MemgraphDB](https://github.com/memgraph/memgraph)
- [mgconsole](https://github.com/memgraph/mgconsole)
- [MAGE](https://github.com/memgraph/mage)
- [Memgraph Lab](https://memgraph.com/docs/data-visualization)

Here are the Docker images which can be built from this repository:
- [Memgraph Docker image](https://hub.docker.com/r/memgraph/memgraph)
- [Memgraph MAGE Docker image](https://hub.docker.com/r/memgraph/memgraph-mage)
- [Memgraph Lab Docker image](https://hub.docker.com/r/memgraph/lab)
- ([*deprecated*](#exclamation-deprecated-memgraph-platform-docker-image)) [Memgraph Platform Docker image](https://hub.docker.com/r/memgraph/memgraph-platform) 


## :exclamation: (Deprecated) Memgraph Platform Docker image

The last Memgraph Platform image published on Docker Hub is 2.14.1. In the future, from Memgraph 2.15, **Memgraph Platform image will no longer be published**, and [Docker Compose](./docker-compose.yml) containing Memgraph MAGE and Lab services will replace it.


You can start Memgraph Platform with:

```
docker run -p 3000:3000 -p 7444:7444 -p 7687:7687 --name memgraph memgraph/memgraph-platform
```

### How to start mgconsole

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

### How to start only Lab

Run only the Lab with the following command:

```
docker run -p 3000:3000 memgraph/memgraph-platform -c /etc/supervisor/supervisord-lab-only.conf
```

### How to start only Memgraph

Run only Memgraph with the following command:

```
docker run -p 7687:7687 memgraph/memgraph-platform -c /etc/supervisor/supervisord-memgraph-only.conf
```


### :hourglass: Versioning

The versioning is transparent in the sense that we explicitly state which
version of software is included, and it looks like this:

`memgraph/memgraph-platform:2.5.0-memgraph2.4-lab2.2.2-mage1.3.5`

and just by looking at each of the Memgraph Platform version, you can know which
versions of software it contains without looking at details in release notes.

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
