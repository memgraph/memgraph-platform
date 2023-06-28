#!/bin/bash
set -euo pipefail
DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PLATFORM_DIR="$DIR/../"
MEMGRAPH_DOCKER_DIR="$PLATFORM_DIR/mage/cpp/memgraph/release/docker"

# TODO(gitbuda): Deduce memgraph package from dist or inject it
# TODO(gitbuda): take latest from the resources file, memgraph-${target_arch}_amd64.deb (DERIVE)
target_arch="2.8.0+22~3cd674701-1"
# TODO(gitbuda): Docker tag can't have chars like + or ~ -> take the logic from memgraph/release/docker/package_docker
docker_tag_arch="2.8.0_22_3cd674701"

cd "$DIR"
$MEMGRAPH_DOCKER_DIR/package_docker "$DIR/dist/package/memgraph_${target_arch}_amd64.deb"
mkdir -p "$DIR/dist/docker"
cp "$MEMGRAPH_DOCKER_DIR/memgraph-${docker_tag_arch}-docker.tar.gz" "$DIR/dist/docker"

# TODO(gitbuda): option for cleanup (docker rmi + tar.gz remove) + add a prompt for each command because the build process take long time.
