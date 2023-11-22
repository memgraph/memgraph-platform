#!/bin/bash
set -eo pipefail
DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

MAGE_DIR="$DIR/../mage"
print_help() {
  echo -e "Builds memgraph mage Docker image."
  echo -e ""
  echo -e "How to run?"
  echo -e "  $0 [-h|build src_package_path image_name target_arch]"
  exit 1
}

build() {
  src_package=$1
  image_name=$2
  target_arch=$3
  mage_package_file="memgraph-$target_arch.deb"
  cp $src_package \
     $MAGE_DIR/$mage_package_file
  cd $MAGE_DIR
  docker buildx build --target prod --platform="linux/$target_arch" -t $image_name -f Dockerfile.release .
  mkdir -p "$DIR/dist/docker"
  docker save $image_name | gzip -f > "$DIR/dist/docker/$image_name.tar.gz"
}

if [ "$#" == 0 ]; then
  print_help
else
  case "$1" in
    build)
      if [ "$#" -ne 4 ]; then
        print_help
      fi
      build $2 $3 $4
    ;;
    *)
      print_help
    ;;
  esac
fi
