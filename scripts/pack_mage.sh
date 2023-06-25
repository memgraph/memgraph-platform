#!/bin/bash
set -euo pipefail
DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PLATFORM_DIR="$DIR/../"
MAGE_DIR="$PLATFORM_DIR/mage"

# TODO(gitbuda): Deduce memgraph package from dist or inject it
# TODO(gitbuda): The default image name should simply be memgraph_mage_current_time
image_name="memgraph_mage_2023-06-24"
# TODO(gitbuda): take latest from the resources file, memgraph-${target_arch}_amd64.deb (DERIVE)
target_arch="2.8.0+22~3cd674701-1"
# TODO(gitbuda): Add option to exclude large large packages like pytorch

cp "$DIR/dist/package/memgraph_${target_arch}_amd64.deb" \
   "$MAGE_DIR/memgraph-${target_arch}_amd64.deb"
cd ${MAGE_DIR}
docker buildx build --target prod --platform=linux/amd64 -t "$image_name" --build-arg TARGETARCH="${target_arch}_amd64" -f "$MAGE_DIR/Dockerfile.release" .
mkdir -p "$DIR/dist/docker"
docker save ${image_name} | gzip -f > "$DIR/dist/docker/${image_name}.tar.gz"

# TODO(gitbuda): option for cleanup (docker rmi + tar.gz remove) + add a prompt for each command because the build process take long time.
