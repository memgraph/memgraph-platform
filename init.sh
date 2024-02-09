#!/bin/sh -eu
CMD_PREFIX="/bin"

msg_out() {
  $CMD_PREFIX/echo -e "$1\n"
}

err_out() {
  msg_out "Error: $1" >&2 && exit 1
}

check_cmd_dep() {
  if [ "$2" = "--err" ]; then
    command -v $CMD_PREFIX/$1 >/dev/null 2>&1 || err_out "you need to have '$1' installed"
  elif [ "$2" = "--no-err" ]; then
    command -v $CMD_PREFIX/$1 >/dev/null 2>&1
  fi
}

check_running_container() {
  $CMD_PREFIX/docker container inspect $1 > /dev/null 2>&1 && \
  msg_out "Container $1 is already running on this machine"
}

check_port_availability() {
  $CMD_PREFIX/lsof -i | $CMD_PREFIX/grep LISTEN | $CMD_PREFIX/grep :$1 > /dev/null 2>&1 && \
  msg_out "Another process on this machine is already using port $1"
}

# Check for required commands
check_cmd_dep "docker" --err
check_cmd_dep "grep" --err
check_cmd_dep "lsof" --err
check_cmd_dep "mkdir" --err
check_cmd_dep "pwd" --err

# Check for curl or wget commands
if check_cmd_dep "curl" --no-err; then
    _download_cmd=curl
elif check_cmd_dep "wget" --no-err; then
    _download_cmd=wget
else
    err_out "you need to have 'curl' or 'wget' installed"
fi

# Check for docker compose or docker-compose
if $CMD_PREFIX/docker compose version >/dev/null 2>&1; then
  _compose_cmd="docker compose"
elif check_cmd_dep "docker-compose"; then
  _compose_cmd="docker-compose"
else
  err_out "you need to have 'docker compose' or 'docker-compose' installed"
fi

DIR=$($CMD_PREFIX/pwd)
MGPLAT_DIR="$DIR/memgraph-platform"
MGPLAT_COMPOSE_PATH="$MGPLAT_DIR/docker-compose.yml"
DOCKER_COMPOSE_URL="https://raw.githubusercontent.com/memgraph/memgraph-platform/add-docker-compose/docker-compose.yml"

# Check if compose file already exists
if [ -f "$MGPLAT_COMPOSE_PATH" ]; then
  msg_out "Overwriting docker compose file found at $MGPLAT_COMPOSE_PATH"
elif [ ! -d $MGPLAT_DIR ]; then
  $CMD_PREFIX/mkdir -p $MGPLAT_DIR
fi

msg_out "Downloading docker compose file to $MGPLAT_COMPOSE_PATH"
$CMD_PREFIX/$_download_cmd $DOCKER_COMPOSE_URL -o "$MGPLAT_DIR/docker-compose.yml" > /dev/null 2>&1 || \
err_out "something went wrong when dowloading docker-compose.yml from $DOCKER_COMPOSE_URL"

# Check if containers with the same names are already running
check_running_container "memgraph-lab"
check_running_container "memgraph-mage"

# Check if ports are in use
# check_port_availability 3000
# check_port_availability 7687
# check_port_availability 7444

# Run compose
$CMD_PREFIX/docker compose up -d
