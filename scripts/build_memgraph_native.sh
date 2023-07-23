#!/usr/bin/env bash
# NOTE: -u is not an option here because toolchain activate fails (a better
# ZSH_NAME check required).
set -eo pipefail
DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

MGPLAT_TOOLCHAIN_ROOT="${MGPLAT_TOOLCHAIN_ROOT:-/opt/toolchain-v4}"
MGPLAT_MG_ROOT="${MGPLAT_MG_ROOT:-$DIR/../mage/cpp/memgraph}"
MGPLAT_MG_TAG="${MGPLAT_MG_TAG:-master}"
MGPLAT_MG_BUILD_TYPE="${MGPLAT_MG_BUILD_TYPE:-RelWithDebInfo}"
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
MGPLAT_DIST_BINARY="$DIR/dist/binary"
# TODO(gitbuda): Update print_help
print_help() {
  echo -e "ENV VARS:"
  echo -e "\tMGPLAT_TOOLCHAIN_ROOT\t   -> root directory of the toolchain"
  echo -e "\tMGPLAT_MG_ROOT\t   -> root directory of memgraph"
  echo -e "\tMGPLAT_MG_TAG\t   -> git ref/branch of memgraph to build"
  echo -e "\tMGPLAT_MG_BUILD_TYPE -> Debug|Release|RelWithDebInfo"
  echo -e "\tMGPLAT_CORES\t\t   -> number of cores to build memgraph"
  echo -e "RUN:"
  echo -e "\t$0 [build|clean]"
  exit 1
}

pull_memgraph_and_os() {
  cd "$MGPLAT_MG_ROOT"
  git checkout "$MGPLAT_MG_TAG"
  git pull origin "$MGPLAT_MG_TAG"
  # shellcheck disable=SC1091
  source "$MGPLAT_MG_ROOT/environment/util.sh"
  # Required to get the underlying opearting system
  OPERATING_SYSTEM_FAMILY="$(operating_system | cut -d "-" -f 1)"
}

build() {
  pull_memgraph_and_os
  if [ "$(architecture)" = "arm64" ] || [ "$(architecture)" = "aarch64" ]; then
    OS_SCRIPT="$MGPLAT_MG_ROOT/environment/os/$(operating_system)-arm.sh"
  else
    OS_SCRIPT="$MGPLAT_MG_ROOT/environment/os/$(operating_system).sh"
  fi
  if [ "$EUID" -eq 0 ]; then # sudo or root -> it should be possible to just install deps
    "$OS_SCRIPT" install TOOLCHAIN_RUN_DEPS
    "$OS_SCRIPT" install MEMGRAPH_BUILD_DEPS
  else # regular user -> privilege escalation required to install the system level deps
    sudo "$OS_SCRIPT" install TOOLCHAIN_RUN_DEPS
    sudo "$OS_SCRIPT" install MEMGRAPH_BUILD_DEPS
  fi
  # shellcheck disable=SC1091
  source "$MGPLAT_TOOLCHAIN_ROOT/activate"
  ./init
  mkdir -p build && cd build
  if [ "$(architecture)" = "arm64" ] || [ "$(architecture)" = "aarch64" ]; then
    cmake -DCMAKE_BUILD_TYPE="$MGPLAT_MG_BUILD_TYPE" -DMG_ARCH="ARM64" ..
  else
    cmake -DCMAKE_BUILD_TYPE="$MGPLAT_MG_BUILD_TYPE" ..
  fi
  make -j"$MGPLAT_CORES" && make -j"$MGPLAT_CORES" mgconsole
  mkdir -p output && cd output
  ${MGPLAT_CPACK[$OPERATING_SYSTEM_FAMILY]}
}

clean() {
  # NOTE: The output package might be deleted as well (from our mounted dir).
  cd "$MGPLAT_MG_ROOT"
  rm -rf ./build/*
  # TODO(gitbuda): Doesn't work if package_deb is called because of root (SUDO)
  ./libs/cleanup.sh
}

copy_binary() {
  binary_name="$(basename $(readlink $MGPLAT_MG_ROOT/build/memgraph))"
  cp -L "$MGPLAT_MG_ROOT/build/memgraph" "$MGPLAT_DIST_BINARY/$binary_name"
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
    copy_binary)
      copy_binary
    ;;
    *)
      print_help
    ;;
  esac
fi
