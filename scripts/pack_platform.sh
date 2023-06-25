#!/bin/bash
set -euo pipefail
DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PLATFORM_DIR="$DIR/../"

MGPLAT_NPM_TOKEN="${MGPLAT_NPM_TOKEN:-npm_token}"

# TODO(gitbuda): Deduce memgraph package from dist or inject it.
# TODO(gitbuda): The default image name should simply be memgraph_platform_current_time
image_name="memgraph_platform_2023-06-24"
# TODO(gitbuda): take latest from the resources file, memgraph-${target_arch}_amd64.deb (DERIVE)
target_arch="2.8.0+22~3cd674701-1"
# TODO(gitbuda): An option build wihout mage.

cp "$DIR/dist/package/memgraph_${target_arch}_amd64.deb" \
   "$PLATFORM_DIR/memgraph-${target_arch}_amd64.deb"
cd "$PLATFORM_DIR"
docker buildx build --platform=linux/amd64 -t ${image_name} \
  --build-arg TARGETARCH=${target_arch}_amd64 \
  --build-arg NPM_PACKAGE_TOKEN=${MGPLAT_NPM_TOKEN} \
  -f Dockerfile .
mkdir -p "$DIR/dist/docker"
docker save ${image_name} | gzip -f > "$DIR/dist/docker/${image_name}.tar.gz"

# TODO(gitbuda): option for cleanup (docker rmi + tar.gz remove)
