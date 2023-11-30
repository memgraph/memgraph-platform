#!/bin/bash
set -eo pipefail
DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

MGPLAT_ROOT="$DIR/.."
MGPLAT_GHA_PAT_TOKEN="${MGPLAT_GHA_PAT_TOKEN:-github_personal_access_token}"
TARGET_ARCH="${TARGET_ARCH:-amd64}"
MG_PACKAGE_PATH="${MG_PACKAGE_PATH:-$MGPLAT_ROOT/memgraph.deb}"
MGPLAT_IMAGE="${MGPLAT_IMAGE:-memgraph-platform_$TARGET_ARCH}"
MGPLAT_TAR="${MGPLAT_TAR:-memgraph-platform_$TARGET_ARCH.tar.gz}"
CLEANUP="${CLEANUP:-false}"

print_help() {
  echo -e "Builds memgraph platform Docker image."
  echo -e ""
  echo -e "Env vars:"
  echo -e "  MGPLAT_GHA_PAT_TOKEN -> Github PAT token to download Lab's NPM package"
  echo -e "  TARGET_ARCH -> Target architecture for the build (amd64/arm64)"
  echo -e "  MG_PACKAGE_PATH -> Path to the memgraph deb pacakage"
  echo -e "  MGPLAT_IMAGE -> Name for the resulting docker image"
  echo -e "  MGPLAT_TAR -> Name of the resulting .tar.gz of the image"
  echo -e "  CLEANUP -> Cleanup docker images created during build, also the tar.gz mage image if --mage-from-tar is passed (true/false)"
  echo -e ""
  echo -e "How to run?"
  echo -e "  $0 [-h|build --mage-from-tar mage_tar_path|build --mage-from-image mage_image_with_tag|build --mage-from-src|build --no-mage]"
  exit 1
}

build() {
  dockerfile="Dockerfile"
  case "$1" in
    --no-mage)
      dockerfile="memgraph_and_lab.Dockerfile"
    ;;
    --mage-from-src)
      dockerfile="mage_from_src.Dockerfile"
    ;;
    --mage-from-image)
      mage_image=$2
    ;;
    --mage-from-tar)
      docker_load_out=$(docker load < $2)
      mage_image=${docker_load_out#Loaded image:}
    ;;
    *)
      print_help
    ;;
  esac

  platform_package_file="memgraph-$TARGET_ARCH.deb"
  cp $MG_PACKAGE_PATH \
     $MGPLAT_ROOT/$platform_package_file
  cd $MGPLAT_ROOT
  docker buildx build \
    --platform="linux/$TARGET_ARCH" \
    -t ${MGPLAT_IMAGE} \
    --build-arg NPM_PACKAGE_TOKEN="${MGPLAT_GHA_PAT_TOKEN}" \
    --build-arg MAGE_IMAGE="${mage_image}"
    -f ${dockerfile} .
  mkdir -p "$DIR/dist/docker"

  mgplat_tar=$MGPLAT_TAR
  mgplat_tar_ext=${MGPLAT_TAR#*.}
  echo $mgplat_tar_ext
  if [[ "$mgplat_tar_ext" != "tar.gz" ]]; then
    mgplat_tar="$MGPLAT_TAR.tar.gz"
  fi
  docker save $MAGE_IMAGE | gzip -f > "$DIR/dist/docker/$mgplat_tar"

  if [[ "$CLEANUP" == "true" ]]; then
    docker image rm $MGPLAT_IMAGE
    if [[ "$1" == "--mage-from-tar" || "$1" == "--mage-from-image" ]]; then
      docker image rm $mage_image
    fi
    if [[ "$1" == "--mage-from-tar" ]]; then
      rm $2
    fi
  fi
}

if [[ "$#" -eq 0 ]]; then
  print_help
else
  case "$1" in
    build)
      if [[ "$#" -lt 2 || "$#" -gt 3 ]]; then
        print_help
      fi
      build $2 $3
    ;;
    *)
      print_help
    ;;
  esac
fi
