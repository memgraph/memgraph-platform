#!/bin/sh
# POSIX sh: works with `curl ... | sh` on Linux (dash) and macOS (/bin/sh).
set -eu

ESC=$(printf '\033')
CHECK_UNICODE=$(printf '\342\234\224')

msg_out() {
  printf '%b\n' "$1"
}

err_out() {
  msg_out "$(bold "ERROR"): $1" >&2
  exit 1
}

bold() {
  printf '%s' "${ESC}[1m${1}${ESC}[0m"
}

check_cmd_dep() {
  check_cmd="command -V $1"
  if [ "$1" = "docker compose" ]; then
    check_cmd="docker compose version"
  fi
  if $check_cmd > /dev/null 2>&1; then
    msg_out "$1 $CHECK_UNICODE"
    return 0
  else
    msg_out "$1 $(bold "x")"
    $check_cmd || true
    return 1
  fi
}

# Check required commands
msg_out "$(bold "Checking for requirements on this machine:")"
check_deps=1
if check_cmd_dep "curl"; then
  _download_cmd=curl
elif check_cmd_dep "wget"; then
  _download_cmd=wget
else
  check_deps=0
  err_out "you need to have 'curl' or 'wget' installed"
fi
check_cmd_dep "docker" || check_deps=0
check_cmd_dep "docker compose" || check_deps=0
check_cmd_dep "mkdir" || check_deps=0
check_cmd_dep "pwd" || check_deps=0
if [ "$check_deps" -eq 0 ]; then
  err_out "All requirements must be satisfied to run this script!"
fi

DIR=$(pwd)
MGPLAT_DIR="$DIR/memgraph-platform"
MGPLAT_COMPOSE_PATH="$MGPLAT_DIR/docker-compose.yml"
DOCKER_COMPOSE_URL="https://raw.githubusercontent.com/memgraph/memgraph-platform/main/docker-compose.yml"

# Check if compose file already exists
if [ -f "$MGPLAT_COMPOSE_PATH" ]; then
  msg_out "\n$(bold "Overwriting docker compose file found at:") $MGPLAT_COMPOSE_PATH"
elif [ ! -d "$MGPLAT_DIR" ]; then
  mkdir -p "$MGPLAT_DIR"
fi

# Download compose file
msg_out "\n$(bold "Downloading docker compose file to:") $MGPLAT_COMPOSE_PATH"
if [ "$_download_cmd" = "curl" ]; then
  curl -fsSL "$DOCKER_COMPOSE_URL" -o "$MGPLAT_COMPOSE_PATH"
else
  wget -q "$DOCKER_COMPOSE_URL" -O "$MGPLAT_COMPOSE_PATH"
fi || err_out "Something went wrong when downloading docker-compose.yml from $DOCKER_COMPOSE_URL"

# Run compose
cd "$MGPLAT_DIR"
msg_out "\n$(bold "Spinning up memgraph lab and memgraph with mage using docker compose file from:") $MGPLAT_COMPOSE_PATH"
docker compose up
