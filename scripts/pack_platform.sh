#!/bin/bash
set -euo pipefail
DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

MGPLAT_NPM_TOKEN="${MGPLAT_NPM_TOKEN:-npm_token}"

# TODO: Deduce memgraph package from resources/output or inject it.
PLATFORM_DIR="$DIR/../"
image_name="memgraph_platform_2023-06-24"
# TODO(gitbuda): take latest from the resources file, memgraph-${target_arch}_amd64.deb (DERIVE)
target_arch="2.8.0+22~3cd674701-1"
# npmjs.com access token -> required for the lab deps.
# TODO: An option build wihout lab.

cp "$DIR/resources/output/memgraph_${target_arch}_amd64.deb" \
   "$PLATFORM_DIR/memgraph-${target_arch}_amd64.deb"
cd "$PLATFORM_DIR"
docker buildx build --platform=linux/amd64 -t ${image_name} \
  --build-arg TARGETARCH=${target_arch}_amd64 \
  --build-arg NPM_PACKAGE_TOKEN=${MGPLAT_NPM_TOKEN} \
  -f Dockerfile .
docker save ${image_name} | gzip -f > "$DIR/resources/output/${image_name}.tar.gz"

# TODO(gitbuda): option for cleanup
