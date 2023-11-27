#!/usr/bin/env bash
set -eo pipefail
DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# NOTE: The builder container image defines for which operating system Memgraph will be built.
MGPLAT_CNT_IMAGE="${MGPLAT_CNT_IMAGE:-memgraph/memgraph-builder:v4_debian-11}"
MGPLAT_CNT_NAME="${MGPLAT_CNT_NAME:-mgbuild_builder}"
MGPLAT_CNT_MG_ROOT="${MGPLAT_CNT_MG_ROOT:-/platform/mage/cpp/memgraph}"
MGPLAT_CNT_OUTPUT_DIR="/memgraph/build/output"
MGPLAT_MG_TAG="${MGPLAT_MG_TAG:-master}"
MGPLAT_MG_BUILD_TYPE="${MGPLAT_MG_BUILD_TYPE:-RelWithDebInfo}"
MGPLAT_DIST_BINARY="$DIR/dist/binary"
MGPLAT_DIST_PACKAGE="$DIR/dist/package"
print_help() {
  echo -e "Builds memgraph binary and package via Docker build container."
  echo -e ""
  echo -e "Env vars:"
  echo -e "  MGPLAT_CNT_IMAGE     -> Docker image used to build and pack memgraph"
  echo -e "  MGPLAT_CNT_NAME      -> the name of builder Docker container"
  echo -e "  MGPLAT_CNT_MG_ROOT   -> memgraph root directory inside the container"
  echo -e "  MGPLAT_MG_TAG        -> git ref/branch of memgraph to build"
  echo -e "  MGPLAT_MG_BUILD_TYPE -> Debug|Release|RelWithDebInfo"
  echo -e ""
  echo -e "How to run?"
  echo -e "  $0 [pack|cleanup|copy_binary|copy_package]"
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
      docker run -d --network host --name "$cnt_name" "$cnt_image"
        # -v "$DIR/..:/platform" \
        # -v "$DIR/dist/package:$MGPLAT_CNT_MG_ROOT/build/output" \
  fi
  echo "The $cnt_image container is active under $cnt_name name!"
}

docker_stop_rm() {
  docker stop "$MGPLAT_CNT_NAME"
  docker rm "$MGPLAT_CNT_NAME"
}

docker_exec() {
  cnt_cmd="$1"
  docker exec "$MGPLAT_CNT_NAME" bash -c "$cnt_cmd"
}

build_pack() {
  cd "$DIR"
  # shellcheck disable=SC1091
  source build_memgraph_native.sh
  docker_run "$MGPLAT_CNT_NAME" "$MGPLAT_CNT_IMAGE"
  docker cp "$MGPLAT_CNT_MG_ROOT" "$MGPLAT_CNT_NAME:/"
  docker cp "$DIR/build_memgraph_native.sh" "$MGPLAT_CNT_NAME:/"
  docker_exec "git config --global --add safe.directory /memgraph"
  mg_root="MGPLAT_MG_ROOT=/memgraph"
  mg_tag="MGPLAT_MG_TAG=$MGPLAT_MG_TAG"
  mg_build_type="MGPLAT_MG_BUILD_TYPE=$MGPLAT_MG_BUILD_TYPE"
  docker_exec "$mg_root $mg_build_type $mg_tag /build_memgraph_native.sh build"
}

cleanup() {
  docker_stop_rm $MGPLAT_CNT_NAME
}

copy_package() {
  mkdir -p $MGPLAT_DIST_PACKAGE
  last_package_name=$(docker exec "$MGPLAT_CNT_NAME" bash -c "cd $MGPLAT_CNT_OUTPUT_DIR && ls -t memgraph* | head -1")
  package_host_destination="$MGPLAT_DIST_PACKAGE/$last_package_name"
  docker cp "$MGPLAT_CNT_NAME:$MGPLAT_CNT_OUTPUT_DIR/$last_package_name" "$package_host_destination"
  echo "Package $last_package_name saved to $package_host_destination."
}

copy_binary() {
  mkdir -p $MGPLAT_DIST_BINARY
  cnt_cmd="echo \$(readlink $MGPLAT_CNT_MG_ROOT/build/memgraph)"
  cnt_binary_path=$(docker exec "$MGPLAT_CNT_NAME" bash -c "$cnt_cmd")
  binary_name="$(basename $cnt_binary_path)"
  src_cnt_binary_path="$MGPLAT_CNT_NAME:$cnt_binary_path"
  docker cp -L "$src_cnt_binary_path" "$MGPLAT_DIST_BINARY"
}

if [ "$#" == 0 ]; then
  build_pack
else
  case "$1" in
    pack)
      build_pack
    ;;
    # NOTE: The output package might be deleted as well (from our mounted dir).
    cleanup)
      cleanup
    ;;
    # Useful if you need memgraph binary for a specific operating system, e.g.
    # Debian 10 binary to run under Jepsen
    copy_binary)
      copy_binary
    ;;
    copy_package)
      copy_package
    ;;
    *)
      print_help
    ;;
  esac
fi
