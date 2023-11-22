#!/bin/bash
set -eo pipefail
DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

MGPLAT_ROOT="$DIR/../"
MGPLAT_GHA_PAT_TOKEN="${MGPLAT_GHA_PAT_TOKEN:-github_personal_access_token}"
print_help() {
  echo -e "Builds memgraph platform Docker image."
  echo -e ""
  echo -e "Env vars:"
  echo -e "  MGPLAT_GHA_PAT_TOKEN -> Github PAT token to download Lab's NPM package"
  echo -e ""
  echo -e "How to run?"
  echo -e "  $0 [-h|build src_package_path image_name target_arch]"
  exit 1
}

# TODO(gitbuda): An option to build wihout mage.
build() {
  src_package=$1
  image_name=$2
  target_arch=$3
  platform_package_file="memgraph-$target_arch.deb"
  cp $src_package \
     $MGPLAT_ROOT/$platform_package_file
  cd $MGPLAT_ROOT
  docker buildx build --platform="linux/$target_arch" -t ${image_name} \
    --build-arg NPM_PACKAGE_TOKEN="${MGPLAT_GHA_PAT_TOKEN}" \
    -f Dockerfile .
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
