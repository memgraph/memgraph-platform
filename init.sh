#/bin/bash
set -eo pipefail

CMD_PREFIX="/bin"

DIR=$( cd -- "$( $CMD_PREFIX/dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && $CMD_PREFIX/pwd )
MGPLAT_DIR="$DIR/memgraph-platform"
MGPLAT_COMPOSE_PATH="$MGPLAT_DIR/docker-compose.yml"
DOCKER_COMPOSE_URL="https://raw.githubusercontent.com/memgraph/memgraph-platform/add-docker-compose/docker-compose.yml"

msg_out() {
  $CMD_PREFIX/echo -e "$1"
}

err_out() {
  msg_out "\nError: $1" >&2 && exit 1
}


# Check for required commands
declare -a required_commands=("dirname" "docker" "mkdir" "pwd")
for cmd in "${required_commands[@]}"
do
  command -v $CMD_PREFIX/$cmd >/dev/null 2>&1 || \
   err_out "you need to have '$cmd' installed"
done

# Check for curl or wget commands
if command -v $CMD_PREFIX/curl >/dev/null 2>&1; then
    _download_cmd=curl
elif command -v $CMD_PREFIX/wget >/dev/null 2>&1; then
    _download_cmd=wget
else
    err_out "you need to have 'curl' or 'wget' installed"
fi

# Check for docker compose or docker-compose
if $CMD_PREFIX/docker compose version >/dev/null 2>&1; then
  _compose_cmd="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  _compose_cmd="docker-compose"
else
  err_out "you need to have 'docker compose' or 'docker-compose' installed"
fi

# Check if compose file already exists
_download_compose=1
if [ -f "$MGPLAT_COMPOSE_PATH" ]; then
    read -p "Docker compose file already exists at $MGPLAT_COMPOSE_PATH. Overwrite? [y/N] " overwrite
    if [ "$overwrite" = "y" -o "$overwrite" = "Y" ]; then
        $CMD_PREFIX/rm -f $MGPLAT_COMPOSE_PATH
    else
      _download_compose=0
    fi
elif [ ! -d $MGPLAT_DIR ]; then
  $CMD_PREFIX/mkdir -p $MGPLAT_DIR
fi

if [ $_download_compose -eq 1 ]; then
  $CMD_PREFIX/curl $DOCKER_COMPOSE_URL -o "$MGPLAT_DIR/docker-compose.yml" > /dev/null 2>&1 || \
  err_out "something went wrong when dowloading docker-compose.yml from $DOCKER_COMPOSE_URL"
fi

# Check if containers with the same names are already running
declare -a containers=("memgraph-lab" "memgraph-mage")
for cnt_name in "${containers[@]}"
do
  $CMD_PREFIX/docker container inspect $cnt_name > /dev/null 2>&1 && \
  msg_out "\nContainer $cnt_name is already running on this machine"
done

# Check if ports are in use
declare -a ports=("3000" "7687" "7444")
for p in "${ports[@]}"
do
  $CMD_PREFIX/lsof -i | $CMD_PREFIX/grep LISTEN | $CMD_PREFIX/grep $p > /dev/null 2>&1 && \
  msg_out "\nAnother process on this machine is already using port $p"
done

# Run compose
$CMD_PREFIX/docker compose up -d
