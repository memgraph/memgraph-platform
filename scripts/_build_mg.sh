#!/bin/bash

git config --global --add safe.directory /memgraph

source /opt/toolchain-v4/activate

cd memgraph
./environment/os/debian-11.sh install MEMGRAPH_BUILD_DEPS
./init

mkdir -p build
cd build

cmake -DCMAKE_BUILD_TYPE=Release .. && make -j4 memgraph && make -j4 mgconsole

cd output
cpack -G DEB --config "../CPackConfig.cmake"
