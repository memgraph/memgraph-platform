#!/bin/bash
set -eo pipefail
DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

MEMGRAPH_DOCKER_DIR="$DIR/../mage/cpp/memgraph/release/docker"
print_help() {
  echo -e "Builds memgraph Docker image."
  echo -e ""
  echo -e "How to run?"
  echo -e "  $0 [-h|build src_package_path]"
  exit 1
}

build() {
  src_package="$1"
  package_file="$(basename $src_package)"
  package_file_no_prefix="${package_file#memgraph_}"
  memgraph_version="${package_file_no_prefix%-1*}"
  dockerize_memgraph_version="$(echo "$memgraph_version" | sed 's/+/_/g' | sed 's/~/_/g')"
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
