#!/bin/bash -e


# TODO: All the error and logging stuff explained
# set -euox pipefail
# TODO: Note, this script is only used under build_deb.sh.
# TODO: Rename to build_memgraph.sh

# TODO: This seems to be redundant and a bit wrong because of the abs path.
git config --global --add safe.directory /memgraph

# TODO: Make this configurable with env by default
source /opt/toolchain-v4/activate

# TODO: Abs paths with proper DIR
cd memgraph
# TODO: Showcase it's possible to use source to load a script and use functionality form there
./environment/os/debian-11.sh install MEMGRAPH_BUILD_DEPS
./init

mkdir -p build
cd build

#TODO: Make the build type configurable + add the ability to pass additional flags
cmake -DCMAKE_BUILD_TYPE=Release .. && make -j4 memgraph && make -j4 mgconsole

cd output
# TODO: Try to make the following command looked up based on the OS
cpack -G DEB --config "../CPackConfig.cmake"
