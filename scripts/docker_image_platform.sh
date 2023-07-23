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
  echo -e "  $0 [-h|build src_package_path image_name]"
  exit 1
}

# TODO(gitbuda): An option to build wihout mage.
build() {
  src_package="$1"
  image_name="$2"
  package_file="$(basename $src_package)"
  platform_package_file="memgraph-${package_file#memgraph_}"
  package_file_name="${package_file%.*}"
  target_arch="${package_file_name#memgraph_}"
  arch_suffix="${target_arch##*_}"
  cp "$src_package" \
     "$MGPLAT_ROOT/$platform_package_file"
  cd "$MGPLAT_ROOT"
  docker buildx build --platform="linux/$arch_suffix" -t ${image_name} \
    --build-arg TARGETARCH="$target_arch" \
    --build-arg NPM_PACKAGE_TOKEN="${MGPLAT_GHA_PAT_TOKEN}" \
    -f Dockerfile .
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
