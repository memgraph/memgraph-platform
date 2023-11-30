#!/bin/bash
set -eo pipefail
DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

MAGE_ROOT="$DIR/../mage"
TARGET_ARCH="${TARGET_ARCH:-amd64}"
MG_PACKAGE_PATH="${MG_PACKAGE_PATH:-$MAGE_ROOT/memgraph.deb}"
MAGE_IMAGE="${MAGE_IMAGE:-memgraph/mage:latest}"
MAGE_TAR="${MAGE_TAR:-mage_$TARGET_ARCH.tar.gz}"
CLEANUP="${CLEANUP:-false}"

print_help() {
  echo -e "Builds memgraph mage Docker image."
  echo -e ""  
  echo -e "Env vars:"
  echo -e "  TARGET_ARCH -> Target architecture for the build (amd64/arm64)"
  echo -e "  MG_PACKAGE_PATH -> Path to the memgraph deb pacakage"
  echo -e "  MAGE_IMAGE -> Name for the resulting docker image"
  echo -e "  MAGE_TAR -> Name of the resulting .tar.gz of the image"
  echo -e "  CLEANUP -> Cleanup docker images created during build (true/false)"
  echo -e ""
  echo -e "How to run?"
  echo -e "  $0 [-h|build [--no-ml]]"
  exit 1
}

build() {
  dockerfile="Dockerfile.release"
  if [[ "$#" -eq 1 ]]; then
    if [ "$1" == "--no-ml" ]; then
      dockerfile="Dockerfile.no_ML"
    else
      print_help
    fi
  fi

  mage_package_file="memgraph-$TARGET_ARCH.deb"
  cp $MG_PAKCAGE_PATH \
     $MAGE_ROOT/$mage_package_file
  cd $MAGE_ROOT

  docker buildx build \
    --target prod \
    --platform="linux/$TARGET_ARCH" \
    -t $MAGE_IMAGE \
    -f $dockerfile .
  mkdir -p "$DIR/dist/docker"

  mage_tar=$MAGE_TAR
  mage_tar_ext=${MAGE_TAR#*.}
  echo $mage_tar_ext
  if [[ "$mage_tar_ext" != "tar.gz" ]]; then
    mage_tar="$MAGE_TAR.tar.gz"
  fi
  docker save $MAGE_IMAGE | gzip -f > "$DIR/dist/docker/$mage_tar"
  
  if [[ "$CLEANUP" == "true" ]]; then
    docker image rm $MAGE_IMAGE
  fi
}

if [ "$#" == 0 ]; then
  print_help
else
  case "$1" in
    build)
      if [[ "$#" -gt 2 ]]; then
        print_help
      fi
      build $2
    ;;
    *)
      print_help
    ;;
  esac
fi
