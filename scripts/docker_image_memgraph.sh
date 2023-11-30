#!/bin/bash
set -eo pipefail
DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

MEMGRAPH_DOCKER_DIR="$DIR/../mage/cpp/memgraph/release/docker"
MAGE_ROOT="$DIR/../mage"
MEMGRAPH_TARGET_ARCH="${MEMGRAPH_TARGET_ARCH:-amd64}"
MEMGRAPH_PACKAGE_PATH="${MEMGRAPH_PACKAGE_PATH:-$DIR/memgraph.deb}"
MEMGRAPH_IMAGE_NAME="${MEMGRAPH_IMAGE_NAME:-mage_$MEMGRAPH_TARGET_ARCH}"
CLEANUP="${CLEANUP:-false}"

print_help() {
  echo -e "Builds memgraph Docker image."
  echo -e ""
  echo -e "How to run?"
  echo -e "  $0 [-h|build src_package_path]"
  exit 1
}

# memgraph_2.12.0+8~72d47fc3b-1_amd64.deb

build() {
  src_package="memgraph_2.12.0+8~72d47fc3b-1_amd64.deb"
  
  package_file="$(basename $src_package)"

  package_file_no_prefix="${package_file#memgraph_}"
  
  memgraph_version="${package_file_no_prefix%-1*}"
  
  dockerize_memgraph_version="$(echo "$memgraph_version" | sed 's/+/_/g' | sed 's/~/_/g')"  

  echo $package_file
  echo $package_file_no_prefix
  echo $memgraph_version
  echo $dockerize_memgraph_version

  exit 0

  $MEMGRAPH_DOCKER_DIR/package_docker "$src_package"
  
  mkdir -p "$DIR/dist/docker"
  
  cp "$MEMGRAPH_DOCKER_DIR/memgraph-${dockerize_memgraph_version}-docker.tar.gz" "$DIR/dist/docker"
}

if [ "$#" == 0 ]; then
  print_help
else
  case "$1" in
    build)
      if [ "$#" -ne 2 ]; then
        print_help
      fi
      build "$2"
    ;;
    *)
      print_help
    ;;
  esac
fi
