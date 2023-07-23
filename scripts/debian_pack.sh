#!/usr/bin/env bash
set -eox pipefail
DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# NOTE: The builder container image defines for which operating system Memgraph will be built.
MGPLAT_CNT_IMAGE="${MGPLAT_CNT_IMAGE:-memgraph/memgraph-builder:v4_debian-10}"
MGPLAT_CNT_NAME="${MGPLAT_CNT_NAME:-mgbuild_builder}"
MGPLAT_MG_ROOT="${MGPLAT_MG_ROOT:-$DIR/../mage/cpp/memgraph}"
MGPLAT_CNT_MG_ROOT="${MGPLAT_CNT_MG_ROOT:-/platform/mage/cpp/memgraph}"
MGPLAT_MG_TAG="${MGPLAT_MG_TAG:-master}"
MGPLAT_MG_BUILD_TYPE="${MGPLAT_MG_BUILD_TYPE:-RelWithDebInfo}"
# TODO(gitbuda): Comput the latest binary name, sym link is enough it just has to be followed
MGPLAT_MG_BIN_NAME="memgraph-2.8.0+29~84721f7e0_RelWithDebInfo"
# TODO(gitbuda): Update print_help
print_help() {
  echo -e "$0 [copy]"
  exit 1
}

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
        -v "$DIR/dist/package:$MGPLAT_CNT_MG_ROOT/build/output" \
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

build_pack() {
  cd "$DIR"
  # shellcheck disable=SC1091
  # TODO(gitbuda): This is a problem because the initial loading -> move at the top of the script.
  source build_memgraph.sh
  mkdir -p dist/binary
  docker_run "$MGPLAT_CNT_NAME" "$MGPLAT_CNT_IMAGE"
  docker cp "$DIR/build_memgraph.sh" "$MGPLAT_CNT_NAME:/"
  docker_exec "git config --global --add safe.directory $MGPLAT_CNT_MG_ROOT"
  mg_root="MGPLAT_MG_ROOT=$MGPLAT_CNT_MG_ROOT"
  mg_tag="MGPLAT_MG_TAG=$MGPLAT_MG_TAG"
  mg_build_type="MGPLAT_MG_BUILD_TYPE=$MGPLAT_MG_BUILD_TYPE"
  docker_exec "$mg_root $mg_build_type $mg_tag /build_memgraph.sh build"
}

if [ "$#" == 0 ]; then
  build_pack
else
  case "$1" in
    copy)
      cnt_binary_paths="$(docker exec "$MGPLAT_CNT_NAME" bash -c "ls $MGPLAT_CNT_MG_DIR/build/memgraph-*")"
      for cnt_binary_path in $cnt_binary_paths; do
        src_cnt_binary_path="$MGPLAT_CNT_NAME:$cnt_binary_path"
        docker cp "$src_cnt_binary_path" "$DIR/dist/binary/"
      done
    ;;
    *)
      print_help
    ;;
  esac
fi

# # TODO(gitbuda): option for cleanup (docker rmi builder + package) + add a prompt for each command because the build process take long time.
# cd "$MGPLAT_MEMGRAPH_ROOT/build"
# sudo rm -rf ./*
# cd "$MGPLAT_MEMGRAPH_ROOT/libs"
# sudo ./cleanup.sh
