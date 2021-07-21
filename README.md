<p align="center">
  <img src="https://uploads-ssl.webflow.com/5e7ceb09657a69bdab054b3a/5e7ceb09657a6937ab054bba_Black_Original%20_Logo.png" width="300"/>
</p>
<p align="center">Download everything you need to run Memgraph.</p>

<p align="center">
  <a href="https://github.com/memgraph/memgraph-platform/LICENSE">
    <img src="https://img.shields.io/github/license/memgraph/memgraph-platform" alt="license" title="license"/>
  </a>
  <a href="https://github.com/memgraph/memgraph-platform">
    <img src="https://img.shields.io/github/languages/code-size/memgraph/memgraph-platform" alt="build" title="build"/>
  </a>
  <a href="https://github.com/memgraph/memgraph-platform/stargazers">
    <img src="https://img.shields.io/badge/maintainer-mastermedo-yellow" alt="maintainer" title="maintainer"/>
  </a>
</p>

<p align="center">
  <a href="https://github.com/memgraph/memgraph-platform">
    <img src="https://mislav.dev/assets/img/out.gif" alt="demo" title="demo"/>
  </a>
</p>

## :clipboard: description
This repository serves as a docker package builder for the Memgraph ecosystem.
It works by cramming memgraph, memgraph lab, and mage into one container and running processes with supervisor.
First, it builds memgraph lab in separate node containers and then transfers it to debian, where mage is built on top of a debian package.

## :zap: features
1. all-in-one
2. slow
3. bloat

## :chart_with_upwards_trend: analyse!
TODO

## :bulb: TODO
- ditch mage build tools after building
- remove unneccessary dependencies from lab and mage
- move everything to a smaller container base image (e.g. alpine)
- deal better with user permissions for the memgraph user

## :question: building
1. download latest `.deb` package from [memgraph.com](https://memgraph.com/dowload)
2. copy it into this directory `cp ~/downloads/memgraph*.deb .`
3. run `docker build . -t test --build-arg deb_release=memgraph*.deb`
4. run `docker run --rm -it -p 3000:3000 -p 7687:7687 test:latest`
5. go to `http://localhost:3000` and connect to memgraph

<p align="center">
  <a href="#">
    <img src="https://img.shields.io/badge/⬆️back_to_top_⬆️-white" alt="Back to top" title="Back to top"/>
  </a>
</p>
