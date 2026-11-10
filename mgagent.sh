#!/bin/sh
#
# mgagent quick start: Memgraph's AI assistant, next to a fresh Memgraph.
#
#   curl -sSf https://install.memgraph.com/mgagent | sh
#
# Starts the latest Memgraph MAGE image (memgraph/memgraph-mage:latest) and then
# the latest mgagent image (memgraph/mgagent:latest), already connected to it.
# Both share a private Docker network; Memgraph is also published on the host
# (localhost:7687, 7444) for Memgraph Lab, mgconsole or your own drivers.
#
# LLM provider settings already exported in your shell are passed on to mgagent:
#   ANTHROPIC_API_KEY  ANTHROPIC_BASE_URL
#   OPENAI_API_KEY     OPENAI_BASE_URL
#   GEMINI_API_KEY     GOOGLE_API_KEY
#   DEEPSEEK_API_KEY   XAI_API_KEY   MISTRAL_API_KEY
#   OLLAMA_HOST        OLLAMA_BASE_URL
# plus MGAGENT_TELEMETRY (set it to "off" to opt out of usage statistics).
# A base URL on localhost / 127.0.0.1 / 0.0.0.0 is rewritten to
# host.docker.internal, since localhost inside the container is the container.
# With none of these set, mgagent asks for a provider and key on first run and
# keeps it in the "mgagent" Docker volume.
#
# Requirements: Docker.
#
# Options (environment variables):
#   MGAGENT_WORKDIR=<dir>   mount <dir> at /work and start mgagent there, so it
#                           can read and import your files (it writes as uid 65532)
#   MEMGRAPH_PORT=<port>    host port for Memgraph's Bolt endpoint (default 7687)
#
# Arguments after `sh -s --` go to mgagent, e.g. a one-off headless question:
#   curl -sSf https://install.memgraph.com/mgagent | sh -s -- -p "how many nodes are there?"
#
# Tear down (Memgraph keeps running after mgagent exits):
#   curl -sSf https://install.memgraph.com/mgagent | sh -s -- clean
#   (or: docker rm -f mgagent-memgraph; docker network rm mgagent-net)

set -eu

MAGE_IMAGE="memgraph/memgraph-mage:latest"
MGAGENT_IMAGE="memgraph/mgagent:latest"

NET="mgagent-net"
MEMGRAPH="mgagent-memgraph"
VOLUME="mgagent"
MEMGRAPH_PORT="${MEMGRAPH_PORT:-7687}"

# Every variable mgagent reads its provider from (apps/cli/src/config.ts).
KEY_VARS="ANTHROPIC_API_KEY OPENAI_API_KEY GEMINI_API_KEY GOOGLE_API_KEY DEEPSEEK_API_KEY XAI_API_KEY MISTRAL_API_KEY"
URL_VARS="ANTHROPIC_BASE_URL OPENAI_BASE_URL OLLAMA_HOST OLLAMA_BASE_URL"
OTHER_VARS="MGAGENT_TELEMETRY"

if [ -t 1 ]; then
  BOLD="$(printf '\033[1m')"; CYAN="$(printf '\033[1;36m')"; GREEN="$(printf '\033[1;32m')"
  YELLOW="$(printf '\033[1;33m')"; RESET="$(printf '\033[0m')"
else
  BOLD=""; CYAN=""; GREEN=""; YELLOW=""; RESET=""
fi

log()  { printf '\n%s==> %s%s\n' "$CYAN" "$*" "$RESET"; }
warn() { printf '%sWarning:%s %s\n' "$YELLOW" "$RESET" "$*" >&2; }
die()  { printf '%sError:%s %s\n' "$BOLD" "$RESET" "$*" >&2; exit 1; }

# Value of the variable named $1, empty when unset (works under set -u).
value_of() { eval "printf '%s' \"\${$1:-}\""; }

# A key shown as its first and last few characters, never the whole thing.
mask() {
  _len=$(printf '%s' "$1" | wc -c | tr -d ' ')
  if [ "$_len" -le 12 ]; then
    printf '****'
  else
    printf '%s…%s' "$(printf '%s' "$1" | cut -c1-6)" "$(printf '%s' "$1" | cut -c"$((_len - 3))"-)"
  fi
}

# localhost in a URL (with or without a scheme, as OLLAMA_HOST often is) points
# at the host when seen from inside the container.
to_container_url() {
  printf '%s' "$1" | sed -E 's#^(([A-Za-z][A-Za-z0-9+.-]*://)?)(localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1\])([:/]|$)#\1host.docker.internal\4#'
}

teardown() {
  log "Removing $MEMGRAPH and the $NET network"
  docker rm -f "$MEMGRAPH" >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
  printf 'Cleaned up. mgagent settings and history stay in the "%s" volume:\n' "$VOLUME"
  printf '  docker volume rm %s\n' "$VOLUME"
}

# ---- Requirements -----------------------------------------------------------
command -v docker >/dev/null 2>&1 || die "Docker is required: https://docs.docker.com/get-docker/"
docker info >/dev/null 2>&1 || die "Docker is installed but not reachable. Is the Docker daemon running (and can this user use it)?"

if [ "${1:-}" = "clean" ]; then
  teardown
  exit 0
fi

# mgagent is a terminal UI: it needs a TTY. Piped into sh, stdin is the script
# itself, so the terminal is taken from /dev/tty instead.
TTY_FLAGS=""
if [ -t 0 ] && [ -t 1 ]; then
  TTY_FLAGS="-it"
  TTY_IN=""
elif [ -t 1 ] && (: </dev/tty) 2>/dev/null; then
  TTY_FLAGS="-it"
  TTY_IN="/dev/tty"
elif [ $# -gt 0 ]; then
  # No terminal at all (CI, a pipe): only headless use (-p ...) can work.
  TTY_IN=""
else
  die "no terminal to run mgagent's UI in. Run this from a terminal, or pass a headless question: sh -s -- -p \"...\""
fi

# ---- Provider settings from the environment ---------------------------------
ENV_FLAGS=""
found_provider=0
log "Looking for LLM provider settings in your environment"
for var in $KEY_VARS; do
  val="$(value_of "$var")"
  [ -n "$val" ] || continue
  printf '  %s✔%s %s = %s\n' "$GREEN" "$RESET" "$var" "$(mask "$val")"
  ENV_FLAGS="$ENV_FLAGS -e $var"
  found_provider=1
done
for var in $URL_VARS; do
  val="$(value_of "$var")"
  [ -n "$val" ] || continue
  new="$(to_container_url "$val")"
  if [ "$new" != "$val" ]; then
    printf '  %s✔%s %s = %s %s(was %s)%s\n' "$GREEN" "$RESET" "$var" "$new" "$BOLD" "$val" "$RESET"
    eval "$var=\$new"
  else
    printf '  %s✔%s %s = %s\n' "$GREEN" "$RESET" "$var" "$val"
  fi
  export "${var?}"
  ENV_FLAGS="$ENV_FLAGS -e $var"
  # A base URL alone is a provider for a local server (Ollama, vLLM, LM Studio…).
  case "$var" in OPENAI_BASE_URL | OLLAMA_*) found_provider=1 ;; esac
done
for var in $OTHER_VARS; do
  val="$(value_of "$var")"
  [ -n "$val" ] || continue
  printf '  %s✔%s %s = %s\n' "$GREEN" "$RESET" "$var" "$val"
  ENV_FLAGS="$ENV_FLAGS -e $var"
done
if [ "$found_provider" -eq 0 ]; then
  printf '  none found - mgagent will ask for a provider and key on first run\n'
  printf '  (or export one first, e.g. ANTHROPIC_API_KEY or OPENAI_API_KEY, and re-run)\n'
fi

# ---- Images -----------------------------------------------------------------
log "Pulling $MAGE_IMAGE and $MGAGENT_IMAGE"
# Offline, or behind a registry hiccup, a copy already on this machine will do.
pull() {
  docker pull "$1" && return 0
  docker image inspect "$1" >/dev/null 2>&1 || die "could not pull $1"
  warn "could not pull $1; using the copy already on this machine"
}
pull "$MAGE_IMAGE"
pull "$MGAGENT_IMAGE"

# ---- Memgraph ---------------------------------------------------------------
docker network inspect "$NET" >/dev/null 2>&1 || docker network create "$NET" >/dev/null

running_image="$(docker inspect -f '{{if .State.Running}}{{.Config.Image}}{{end}}' "$MEMGRAPH" 2>/dev/null || true)"
latest_id="$(docker image inspect -f '{{.Id}}' "$MAGE_IMAGE")"
current_id="$(docker inspect -f '{{.Image}}' "$MEMGRAPH" 2>/dev/null || true)"

if [ "$running_image" = "$MAGE_IMAGE" ] && [ "$current_id" = "$latest_id" ]; then
  log "Memgraph is already running ($MEMGRAPH), reusing it"
else
  if [ -n "$current_id" ]; then
    log "Replacing the previous $MEMGRAPH container with the latest image"
    docker rm -f "$MEMGRAPH" >/dev/null
  fi
  log "Starting Memgraph ($MAGE_IMAGE) on localhost:$MEMGRAPH_PORT"
  # A port already in use (another Memgraph?) fails the run, so fall back to
  # Bolt alone (7444 only streams logs to Lab), then to no host ports at all:
  # mgagent reaches Memgraph over the Docker network either way.
  started=0
  for ports in "-p $MEMGRAPH_PORT:7687 -p 7444:7444" "-p $MEMGRAPH_PORT:7687" ""; do
    # shellcheck disable=SC2086 # $ports is a list of words
    if docker run -d --name "$MEMGRAPH" --network "$NET" $ports \
        "$MAGE_IMAGE" --schema-info-enabled=True >/dev/null 2>&1; then
      started=1
      break
    fi
    docker rm -f "$MEMGRAPH" >/dev/null 2>&1 || true
    case "$ports" in
      *7444*) warn "port 7444 is in use on the host; starting Memgraph without it (only Lab's log view needs it)" ;;
      -p*) warn "port $MEMGRAPH_PORT is in use on the host; starting Memgraph without host ports (set MEMGRAPH_PORT to pick another)" ;;
    esac
  done
  [ "$started" -eq 1 ] || die "could not start Memgraph (try: docker run --rm $MAGE_IMAGE)"
fi

log "Waiting for Memgraph to accept connections"
tries=0
until docker exec "$MEMGRAPH" bash -c 'echo > /dev/tcp/127.0.0.1/7687' >/dev/null 2>&1; do
  tries=$((tries + 1))
  if [ "$tries" -ge 60 ]; then
    warn "Memgraph is not answering yet; starting mgagent anyway (see: docker logs $MEMGRAPH)"
    break
  fi
  if [ -z "$(docker inspect -f '{{if .State.Running}}up{{end}}' "$MEMGRAPH" 2>/dev/null)" ]; then
    docker logs --tail 20 "$MEMGRAPH" >&2 || true
    die "Memgraph exited during startup (logs above)"
  fi
  sleep 1
done

# ---- mgagent ----------------------------------------------------------------
# The docker command is built in "$@" by prepending to the arguments meant for
# mgagent, so paths with spaces survive (POSIX sh has no arrays).
set -- "$MGAGENT_IMAGE" -c "bolt://$MEMGRAPH:7687" "$@"

if [ -n "${MGAGENT_WORKDIR:-}" ]; then
  [ -d "$MGAGENT_WORKDIR" ] || die "MGAGENT_WORKDIR is not a directory: $MGAGENT_WORKDIR"
  WORK_DIR="$(cd "$MGAGENT_WORKDIR" && pwd)"
  set -- -v "$WORK_DIR:/work" -w /work "$@"
  log "Mounting $WORK_DIR at /work"
fi

log "Starting mgagent ($MGAGENT_IMAGE), connected to bolt://$MEMGRAPH:7687"
# ENV_FLAGS and TTY_FLAGS are intentionally unquoted: each is a list of plain
# words. The -e flags carry only variable names, so key values never show up
# in `ps`.
# shellcheck disable=SC2086
set -- docker run $TTY_FLAGS --rm \
  --network "$NET" \
  --add-host=host.docker.internal:host-gateway \
  -v "$VOLUME":/home/nonroot/.mgagent \
  $ENV_FLAGS "$@"

status=0
if [ -n "$TTY_IN" ]; then
  "$@" <"$TTY_IN" || status=$?
else
  "$@" || status=$?
fi

# ---- Wrap up ----------------------------------------------------------------
# Ask Docker rather than trusting MEMGRAPH_PORT: a reused container keeps the
# ports it was started with.
host_port="$(docker port "$MEMGRAPH" 7687/tcp 2>/dev/null | sed -n '1s/.*://p')"
printf '\n%sMemgraph is still running%s (%s)' "$BOLD" "$RESET" "$MEMGRAPH"
if [ -n "$host_port" ]; then
  printf ' at bolt://localhost:%s\n' "$host_port"
else
  printf ', reachable only on the %s Docker network\n' "$NET"
fi
cat <<EOF

Start mgagent again (settings and history are kept in the "$VOLUME" volume):
  curl -sSf https://install.memgraph.com/mgagent | sh

Explore the graph in Memgraph Lab:
  docker run -d --rm --name mgagent-lab --network $NET -p 3000:3000 \\
    -e QUICK_CONNECT_MG_HOST=$MEMGRAPH -e QUICK_CONNECT_MG_PORT=7687 memgraph/lab:latest
  open http://localhost:3000

Tear everything down:
  curl -sSf https://install.memgraph.com/mgagent | sh -s -- clean
EOF
exit "$status"
