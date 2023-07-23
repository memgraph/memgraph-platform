#!/bin/bash
set -eo pipefail
DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

MAGE_DIR="$DIR/../mage"
print_help() {
  echo -e "Builds memgraph mage Docker image."
  echo -e ""
  echo -e "How to run?"
  echo -e "  $0 [-h|build src_package_path image_name]"
  exit 1
}

build() {
  src_package="$1"
  image_name="$2"
  package_file="$(basename $src_package)"
  mage_package_file="memgraph-${package_file#memgraph_}"
  package_file_name="${package_file%.*}"
  target_arch="${package_file_name#memgraph_}"
  arch_suffix="${target_arch##*_}"
  cp "$src_package" \
     "$MAGE_DIR/$mage_package_file"
  cd ${MAGE_DIR}
  docker buildx build --target prod --platform="linux/$arch_suffix" -t "$image_name" --build-arg TARGETARCH="$target_arch" -f "$MAGE_DIR/Dockerfile.release" .
  mkdir -p "$DIR/dist/docker"
  docker save ${image_name} | gzip -f > "$DIR/dist/docker/${image_name}.tar.gz"
}

if [ "$#" == 0 ]; then
  print_help
else
  case "$1" in
    build)
      if [ "$#" -ne 3 ]; then
        print_help
      fi
      build "$2" "$3"
    ;;
    *)
      print_help
    ;;
  esac
fi
