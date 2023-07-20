#!/bin/bash
# TODO(gitbuda): /bin/bash doesn't work on Mac -> figure out
# TODO(gitbuda): Put set -e back
set -ox pipefail
DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

MGPLAT_TOOLCHAIN_ROOT="${MGPLAT_TOOLCHAIN_ROOT:-/opt/toolchain-v4}"
MGPLAT_MEMGRAPH_ROOT="${MGPLAT_MEMGRAPH_ROOT:-$DIR/../mage/cpp/memgraph}"
# TODO(gitbuda): build_memgraph put master
MGPLAT_MEMGRAPH_TAG="${MGPLAT_MEMGRAPH_TAG:-master}"
MGPLAT_MEMGRAPH_BUILD_TYPE="${MGPLAT_MEMGRAPH_BUILD_TYPE:-RelWithDebInfo}"
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  MGPLAT_CORES="${MGPLAT_CORES:-$(nproc)}"
elif [[ "$OSTYPE" == "darwin"* ]]; then
  MGPLAT_CORES="${MGPLAT_CORES:-$(sysctl -n hw.physicalcpu)}"
else
  MGPLAT_CORES="${MGPLAT_CORES:-8}"
fi
declare -A MGPLAT_CPACK
MGPLAT_CPACK[ubuntu]="cpack -G DEB --config ../CPackConfig.cmake"
MGPLAT_CPACK[debian]="cpack -G DEB --config ../CPackConfig.cmake"
# Required to get the underlying opearting system
# shellcheck disable=SC1091
# TODO(gitbuda): operating_system doesn't work on Mac -> extend and improve
source "$MGPLAT_MEMGRAPH_ROOT/environment/util.sh"
# OPERATING_SYSTEM_FAMILY="$(operating_system | cut -d "-" -f 1)"
OPERATING_SYSTEM_FAMILY="debian"

print_help() {
  echo -e "ENV VARS:"
  echo -e "\tMGPLAT_TOOLCHAIN_ROOT\t   -> root directory of the toolchain"
  echo -e "\tMGPLAT_MEMGRAPH_ROOT\t   -> root directory of memgraph"
  echo -e "\tMGPLAT_MEMGRAPH_TAG\t   -> git ref/branch of memgraph to build"
  echo -e "\tMGPLAT_MEMGRAPH_BUILD_TYPE -> Debug|Release|RelWithDebInfo"
  echo -e "\tMGPLAT_CORE\t\t   -> number of cores to build memgraph"
  echo -e "RUN:"
  echo -e "\t$0 [build|clean]"
  exit 1
}

build() {
  # shellcheck disable=SC1091
  source "$MGPLAT_TOOLCHAIN_ROOT/activate"
  cd "$MGPLAT_MEMGRAPH_ROOT"
  git checkout "$MGPLAT_MEMGRAPH_TAG"
  # TODO(gitbuda): build_memgraph run install instead of check (SUDO)
  # TODO(gitbuda): operating_system system here is empty if source is not called
  ./environment/os/"$(operating_system)".sh install TOOLCHAIN_RUN_DEPS
  ./environment/os/"$(operating_system)".sh install MEMGRAPH_BUILD_DEPS
  # TODO(gitbuda): if install fails -> everything cascades -> make sure each of these commands stops the build
  ./init
  mkdir -p build && cd build
  cmake -DCMAKE_BUILD_TYPE="$MGPLAT_MEMGRAPH_BUILD_TYPE" .. && \
    make -j"$MGPLAT_CORES" && make -j"$MGPLAT_CORES" mgconsole
  mkdir -p output && cd output
  ${MGPLAT_CPACK[$OPERATING_SYSTEM_FAMILY]}
}

clean() {
  # TODO(gitbuda): Package will be deleted as well -> do we want that?
  cd "$MGPLAT_MEMGRAPH_ROOT"
  rm -rf ./build
  # TODO(gitbuda): Doesn't work if package_deb is called because of root (SUDO)
  ./libs/cleanup.sh
}

if [ "$#" == 0 ]; then
  # if we source this script to get access to the env vars.
  echo "NOTE: running $0 with 0 args -> pass"
else
  case "$1" in
    build)
      build
    ;;
    clean)
      clean
    ;;
    *)
      print_help
    ;;
  esac
fi
