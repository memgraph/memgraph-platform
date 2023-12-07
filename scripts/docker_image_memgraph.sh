#!/bin/bash
set -eo pipefail
DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

MEMGRAPH_DOCKER_DIR="$DIR/../mage/cpp/memgraph/release/docker"
TARGET_ARCH="${TARGET_ARCH:-amd64}"
MG_PACKAGE_PATH="${MG_PACKAGE_PATH:-$DIR/../memgraph.deb}"
MEMGRAPH_IMAGE="${MEMGRAPH_IMAGE:-memgraph/memgraph:latest}"
MEMGRAPH_TAR="${MEMGRAPH_TAR:-memgraph_$TARGET_ARCH.tar.gz}"
CLEANUP="${CLEANUP:-false}"

print_help() {
  echo -e "Builds memgraph Docker image."
  echo -e ""  
  echo -e "Env vars:"
  echo -e "  TARGET_ARCH -> Target architecture for the build (amd64/arm64)"
  echo -e "  MG_PACKAGE_PATH -> Path to the memgraph deb pacakage"
  echo -e "  MEMGRAPH_IMAGE -> Name for the resulting docker image"
  echo -e "  MEMGRAPH_TAR -> Name of the resulting .tar.gz of the image"
  echo -e "  CLEANUP -> Cleanup docker images created during build (true/false)"
  echo -e ""
  echo -e "How to run?"
  echo -e "  $0 [-h|build]"
  exit 1
}

build() {
  dockerfile="memgraph_deb.dockerfile"

  memgraph_package_file="memgraph-$TARGET_ARCH.deb"
  cp $MG_PACKAGE_PATH \
     $MEMGRAPH_DOCKER_DIR/$memgraph_package_file
  cd $MEMGRAPH_DOCKER_DIR

  docker buildx build \
    --platform="linux/$TARGET_ARCH" \
    -tag $MEMGRAPH_IMAGE \
    --build-arg BINARY_NAME="memgraph-" \
    --build-arg EXTENSION="deb"
    --file $dockerfile .
  mkdir -p "$DIR/dist/docker"

  memgraph_tar=$MEMGRAPH_TAR
  memgraph_tar_ext=${MEMGRAPH_TAR#*.}
  echo $memgraph_tar_ext
  if [[ "$memgraph_tar_ext" != "tar.gz" ]]; then
    memgraph_tar="$MEMGRAPH_TAR.tar.gz"
  fi
  docker save $MEMGRAPH_IMAGE | gzip -f > "$DIR/dist/docker/$memgraph_tar"

  if [[ "$CLEANUP" == "true" ]]; then
    docker image rm $MEMGRAPH_IMAGE
  fi
}

if [ "$#" == 0 ]; then
  print_help
else
  case "$1" in
    build)
      if [ "$#" -ne 1 ]; then
        print_help
      fi
      build
    ;;
    *)
      print_help
    ;;
  esac
fi
