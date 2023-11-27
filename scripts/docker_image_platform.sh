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
  echo -e "  $0 [-h|build src_package_path image_name target_arch [--no-mage]]"
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
  dockerfile="Dockerfile"
  if [[ "$#" -eq 4 ]]; then
    if [ "$4" == "--no-mage" ]; then
      dockerfile="memgraph_and_lab.Dockerfile"
    else
      print_help
    fi
  fi
  echo "-----Using dockerfile $dockerfile-----"
  docker buildx build --platform="linux/$target_arch" -t ${image_name} \
    --build-arg NPM_PACKAGE_TOKEN="${MGPLAT_GHA_PAT_TOKEN}" \
    -f ${dockerfile} .
  mkdir -p "$DIR/dist/docker"
  docker save $image_name | gzip -f > "$DIR/dist/docker/$image_name.tar.gz"
}

if [[ "$#" -eq 0 ]]; then
  print_help
else
  case "$1" in
    build)
      if [[ "$#" -lt 4 || "$#" -gt 5 ]]; then
        print_help
      fi
      build $2 $3 $4 $5
    ;;
    *)
      print_help
    ;;
  esac
fi
