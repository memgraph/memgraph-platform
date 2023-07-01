#!/bin/bash
set -eo pipefail
DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# NOTE: The builder container image defines for which operating system Memgraph will be built.
# TODO(gitbuda): Take from env variable
MGPLAT_CNT_IMAGE="memgraph/memgraph-builder:v4_debian-10"
MGPLAT_CNT_NAME="mgbuild_builder"
MGPLAT_MEMGRAPH_ROOT="${MGPLAT_MEMGRAPH_ROOT:-$DIR/../mage/cpp/memgraph}"
MGPLAT_CNT_MG_DIR="/platform/mage/cpp/memgraph"
MGPLAT_MEMGRAPH_TAG="${MGPLAT_MEMGRAPH_TAG:-master}"
MGPLAT_MEMGRAPH_BUILD_TYPE="${MGPLAT_MEMGRAPH_BUILD_TYPE:-RelWithDebInfo}"
MGPLAT_MG_DIST_BIN_NAME="${MGPLAT_MG_DIST_BIN_NAME:-memgraph}"
# TODO(gitbuda): Comput the latest binary name
MGPLAT_MG_BIN_NAME="memgraph-2.8.0+29~84721f7e0_RelWithDebInfo"

cd "$DIR"
# shellcheck disable=SC1091
source build_memgraph.sh
mkdir -p dist/binary

docker_run () {
  cnt_name="$1"
  cnt_image="$2"
  if [ ! "$(docker ps -q -f name="$cnt_name")" ]; then
      if [ "$(docker ps -aq -f status=exited -f name="$cnt_name")" ]; then
          echo "Cleanup of the old exited container..."
          docker rm "$cnt_name"
      fi
      docker run -d \
        -v "$DIR/..:/platform" \
        -v "$DIR/dist/package:$MGPLAT_CNT_MG_DIR/build/output" \
        --network host --name "$cnt_name" "$cnt_image"
  fi
  echo "The $cnt_image container is active under $cnt_name name!"
}

docker_stop_rm() {
  docker stop "$MGPLAT_CNT_NAME"
  docker rm "$MGPLAT_CNT_NAME"
}

docker_exec() {
  cnt_cmd="$1"
  docker exec -it "$MGPLAT_CNT_NAME" bash -c "$cnt_cmd"
}

docker_run "$MGPLAT_CNT_NAME" "$MGPLAT_CNT_IMAGE"
docker cp "$DIR/build_memgraph.sh" "$MGPLAT_CNT_NAME:/"
docker_exec "git config --global --add safe.directory $MGPLAT_CNT_MG_DIR"
mg_root="MGPLAT_MEMGRAPH_ROOT=$MGPLAT_CNT_MG_DIR"
mg_tag="MGPLAT_MEMGRAPH_TAG=$MGPLAT_MEMGRAPH_TAG"
mg_build_type="MGPLAT_MEMGRAPH_BUILD_TYPE=$MGPLAT_MEMGRAPH_BUILD_TYPE"
docker_exec "$mg_root $mg_build_type $mg_tag /build_memgraph.sh build"

# TODO(gitbuda): copy/put somehow memgraph binary to the dist repo
docker cp "$MGPLAT_CNT_NAME:$MGPLAT_CNT_MG_DIR/build/$MGPLAT_MG_BIN_NAME" "$DIR/dist/binary/$MGPLAT_MG_DIST_BIN_NAME"

# # TODO(gitbuda): option for cleanup (docker rmi builder + package) + add a prompt for each command because the build process take long time.
# cd "$MGPLAT_MEMGRAPH_ROOT/build"
# sudo rm -rf ./*
# cd "$MGPLAT_MEMGRAPH_ROOT/libs"
# sudo ./cleanup.sh
