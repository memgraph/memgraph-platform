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
print_help() {
  echo -e "env vars:"
  echo -e "  MGPLAT_TOOLCHAIN_ROOT -> root directory of the toolchain"
  echo -e "  MGPLAT_MG_ROOT        -> root directory of memgraph"
  echo -e "  MGPLAT_MG_TAG         -> git ref/branch of memgraph to build"
  echo -e "  MGPLAT_MG_BUILD_TYPE  -> Debug|Release|RelWithDebInfo"
  echo -e "  MGPLAT_CORES          -> number of cores to build memgraph"
  echo -e ""
  echo -e "how to run?"
  echo -e " $0 [build|copy_binary|copy_package|cleanup]"
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

cleanup() {
  cd "$MGPLAT_MG_ROOT"
  rm -rf ./build/*
  ./libs/cleanup.sh
}

copy_binary() {
  if [ ! -f "$MGPLAT_MG_ROOT/build/memgraph" ]; then
    echo "Unable to find memgraph under the build folder"
    exit 1
  fi
  binary_name="$(basename $(readlink "$MGPLAT_MG_ROOT"/build/memgraph))"
  cp -L "$MGPLAT_MG_ROOT/build/memgraph" "$MGPLAT_DIST_BINARY/$binary_name"
}

copy_package() {
  # NOTE: dist/package is mounted -> root is required -> think about better way
  sudo cp "$MGPLAT_MG_ROOT"/build/output/memgraph* "$DIR/dist/package"
}

if [ "$#" == 0 ]; then
  # if we source this script to get access to the env vars.
  echo "NOTE: running $0 with 0 args -> pass"
else
  case "$1" in
    build)
      build
    ;;
    copy_binary)
      copy_binary
    ;;
    copy_package)
      copy_package
    ;;
    cleanup)
      clean
    ;;
    *)
      print_help
    ;;
  esac
fi
