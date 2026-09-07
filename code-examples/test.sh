#!/usr/bin/env bash
#
# Test harness for the Unix (Linux / macOS) code examples.
#
# Runs each example end to end against a real Docker daemon and asserts on what
# it actually printed -- an exit code of 0 is not enough, because every example
# exists to show specific query results (a ranked plan, a retrieved
# neighbourhood, a recalled memory). Each example is therefore checked twice:
#
#   1. it must exit 0
#   2. its output must contain every marker the walkthrough promises
#
# Examples are run one at a time, never in parallel: they all publish Bolt on
# host port 7687/7688 and would collide. Each run is preceded and followed by
# that example's own 'clean' subcommand, so a failed run cannot leak containers
# into the next one.
#
# Requirements: the union of what the examples need -- Docker, git and
# Python 3.10-3.13 -- plus curl, used here to check that the MCP endpoint really
# answers. No API keys: OPENAI_API_KEY is deliberately unset, so agentic-graphrag
# stops after its three atomic pipelines instead of launching the interactive
# Streamlit app.
#
# Usage:
#   ./test.sh                       # run all three examples
#   ./test.sh ai-memory             # run one (or several, space separated)
#   ./test.sh --keep agentic-ai     # leave the containers up for inspection
#   ./test.sh clean                 # tear down every example, run nothing

set -uo pipefail   # NB: no -e; a failing example must be recorded, not fatal

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$DIR/test-logs-unix"
ALL_EXAMPLES="agentic-ai agentic-graphrag ai-memory"

# ---- Output helpers ---------------------------------------------------------
# ANSI-C quoting ($'...') so each variable holds a real escape character. With
# plain quotes these stay the literal text "\033[1;32m", which printf expands in
# a format string but NOT in a %s argument -- and the summary below passes them
# as arguments.
if [ -t 1 ]; then
  C_HEAD=$'\033[1;36m'; C_OK=$'\033[1;32m'; C_BAD=$'\033[1;31m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_HEAD=''; C_OK=''; C_BAD=''; C_DIM=''; C_OFF=''
fi

log()  { printf "\n${C_HEAD}==> %s${C_OFF}\n" "$*"; }
pass() { printf "  ${C_OK}PASS${C_OFF} %s\n" "$*"; PASSED=$((PASSED + 1)); }
fail() { printf "  ${C_BAD}FAIL${C_OFF} %s\n" "$*"; FAILED=$((FAILED + 1)); FAILURES="$FAILURES
  - $CURRENT: $*"; }
note() { printf "  ${C_DIM}%s${C_OFF}\n" "$*"; }

PASSED=0
FAILED=0
FAILURES=""
CURRENT=""

# ---- Assertions -------------------------------------------------------------
# want <description> <extended-regex>   -- the example must have printed it
want() {
  if grep -Eq -- "$2" "$LOG"; then
    pass "$1"
  else
    fail "$1 (no match for /$2/)"
  fi
}

# reject <description> <extended-regex>  -- the example must NOT have printed it
reject() {
  if grep -Eq -- "$2" "$LOG"; then
    fail "$1 (unexpected match for /$2/ -- see $LOG)"
    grep -En -m3 -- "$2" "$LOG" | sed 's/^/       /'
  else
    pass "$1"
  fi
}

# Every example prints Cypher results through mgconsole. A silent failure there
# (a syntax error, a missing procedure) shows up as an error line, not a bad
# exit code, because the result is piped and the exit status belongs to the pipe.
want_no_query_errors() {
  reject "no query/client errors in output" \
    "Client received an error|failed to prepare|Query failed|Traceback \(most recent call last\)|SyntaxError|Unbound variable|Unknown function|There is no procedure"
}

# The examples hand you endpoints to keep using after they exit, so the
# containers behind those endpoints must still be up when the script returns.
# Run these before the teardown step.
want_running() {
  for c in "$@"; do
    if [ "$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" = "true" ]; then
      pass "container $c still running after the example exited"
    else
      fail "container $c is not running"
      docker logs --tail 15 "$c" 2>&1 | sed 's/^/       /' || true
    fi
  done
}

# ...and be gone again after 'clean'. Run these after the teardown step.
want_gone() {
  for c in "$@"; do
    if docker inspect "$c" >/dev/null 2>&1; then
      fail "container $c survived 'clean'"
    else
      pass "container $c removed by 'clean'"
    fi
  done
}

# 'clean' also promises to remove the work directory it created next to the script.
want_absent_path() {
  if [ -e "$1" ]; then
    fail "$(basename "$1") survived 'clean'"
  else
    pass "$(basename "$1") removed by 'clean'"
  fi
}

# An HTTP endpoint the example advertises must actually answer. Any status code
# counts as an answer: FastMCP redirects a bare GET of /mcp/ to /mcp (307), which
# already proves a server is listening there rather than a dead port. Only a
# connection failure (curl reports 000) is a failure.
want_http() {
  code="$(curl -s -o /dev/null -m 10 -w '%{http_code}' "$2" 2>/dev/null)"
  if [ -n "$code" ] && [ "$code" != "000" ]; then
    pass "$1 (HTTP $code)"
  else
    fail "$1 (no HTTP response from $2)"
  fi
}

# ---- Per-example expectations ----------------------------------------------
# Each block asserts on the substance of the example, not just its banner.
check_agentic_ai() {
  want "shared layer came up (Memgraph, Postgres, MemGQL)" \
    "Starting MemGQL"
  want "connectors registered" \
    "Registering connectors"
  # Federated read: enterprise customers live in Postgres, reached via MemGQL.
  want "federated Postgres read returned Ada Lovelace" "Ada Lovelace"
  want "federated Postgres read returned Grace H." "Grace H\."
  want "federated read joined through to the company" "Acme Corp"
  # Plan 1: weighted traversal ranks whole plans by expected value.
  want "weighted traversal ranked the plans" "expected_value"
  # Match the plan and its score on the SAME result row: 'Resolved' and '0.8'
  # both occur elsewhere in the output, so checking for them separately would
  # pass even if the ranking were wrong.
  want "top-ranked plan is Ticket received -> Assess severity -> Auto-resolve -> Resolved, at 0.8" \
    "\"Ticket received\", \"Assess severity\", \"Auto-resolve\", \"Resolved\"\] +\| +0\.8 +\|"
  # Plan 2: weighted shortest path. cost = (1-1.0) + (1-0.87) + (1-0.92) = 0.21.
  want "weighted shortest path returned that same route, at cost 0.21" \
    "\"Auto-resolve\", \"Resolved\"\] +\| +0\.21 +\|"
  # Plan 3: MAGE betweenness centrality. 'Assess severity' is the only state every
  # plan must pass through, so it is the one that must score non-zero.
  want "betweenness centrality ran" "centrality"
  want "'Assess severity' scored a non-zero centrality" \
    "\"Assess severity\" +\| +0*\.?[0-9]*[1-9]"
  # Plan 4: MAGE community detection. Community 1 existing proves it split the
  # graph rather than returning one lump.
  want "community detection ran" "community_id"
  want "community detection split the states into more than one group" \
    "^\| 1 +\| \[\""
  want "final banner" "Agents planned over the reasoning graph"
  want_no_query_errors
  # The wrap-up text tells you to keep querying bolt://localhost:7688, so all
  # three containers behind that endpoint must survive the script.
  want_running zero-demo-memgraph zero-demo-postgres zero-demo-memgql
}

check_clean_agentic_ai() {
  want_gone zero-demo-memgraph zero-demo-postgres zero-demo-memgql
  want_absent_path "$DIR/.memgql-work"
}

check_agentic_graphrag() {
  want "official demo repo was fetched" "Fetching the official Agentic GraphRAG demo"
  want "Memgraph started" "Starting Memgraph"
  want "knowledge graph was imported" "Importing the AskNews finance knowledge graph"
  # The import must actually land data -- 'Imported. Memgraph now holds 0 nodes.'
  # is the failure mode this catches.
  want "import reported a non-zero node count" \
    "Imported\. Memgraph now holds [1-9][0-9]* nodes\."
  want "MCP server started" "MCP endpoint: http://localhost:8000/mcp/"
  # For each pipeline, check the column header AND at least one data row. A
  # header alone is printed even when the query matches nothing, which is the
  # failure this example would most easily hide.
  # Pipeline 1: Text2Cypher / analytical -- (type, count).
  want "pipeline 1 (analytical) returned organization types" "organization_type"
  want "pipeline 1 returned at least one (type, count) row" \
    "^\| \"[^\"]+\" +\| +[0-9]+ +\|$"
  # Pipeline 2: pivot search + relevance expansion / local -- (entity, type).
  want "pipeline 2 (local) returned a neighbourhood of the pivot" "related_entity"
  want "pipeline 2 returned at least one (entity, type) row" \
    "^\| \"[^\"]+\" +\| \"[^\"]+\" +\|$"
  # Pipeline 3: query-focused summarisation / global -- (theme, type, rank).
  want "pipeline 3 (global) ranked themes with PageRank" "importance"
  want "pipeline 3 returned at least one ranked theme" \
    "^\| \"[^\"]+\" +\| \"[^\"]+\" +\| +0\.[0-9]+ +\|$"
  want "final banner reports the node count" \
    "GraphRAG retrieval pipelines ran against [1-9][0-9]* nodes"
  want "prints how to attach a harness over MCP" "mcpServers"
  # No key in the environment, so it must stop here rather than block on Streamlit.
  want "stopped before the optional agentic app" "To also run the agentic app"
  want_no_query_errors
  want_running agenticgraphrag-memgraph agenticgraphrag-mcp
  # The MCP endpoint is the whole point of step 1b -- printing the URL is not
  # evidence that the server came up.
  want_http "MCP endpoint answers on http://localhost:8000/mcp/" \
    "http://localhost:8000/mcp/"
}

check_clean_agentic_graphrag() {
  want_gone agenticgraphrag-memgraph agenticgraphrag-mcp
  want_absent_path "$DIR/.agentic-graphrag-work"
}

check_ai_memory() {
  want "Memgraph came up" "Memgraph is up on bolt://localhost:7687"
  want "Context Graph packages were installed" \
    "installing sessions-graph, actions-graph, skills-graph"
  # Episodic write (actions-graph).
  want "episodic memory was written" \
    "Wrote 2 Sessions, 4 Actions"
  # Semantic write (sessions-graph).
  want "semantic memory was written" "Wrote 1 Memory\."
  # Procedural write (skills-graph).
  want "procedural memory was written" "Wrote 1 Skill, 1 USED_SKILL usage\."
  # Recall must return content, not empty rows.
  want "semantic recall returned the client facts" "Dana Lee"
  want "episodic recall returned the latest session" \
    "session session-acme-followup"
  want "episodic recall listed the tool call and its result" \
    "tool=schedule_meeting"
  want "procedural recall returned the skill body" "Send a calendar invite"
  # The interconnected traversal is the whole point of the example: one query
  # joining semantic + episodic + procedural. All four fields must be populated.
  want "joined recall: client facts" "client_facts  : .*Acme Corp"
  want "joined recall: last session" "last_session  : session-acme-followup"
  want "joined recall: skill" "skill         : schedule-follow-up"
  want "joined recall: how-to" "how_to        : 1\. Book a calendar slot"
  reject "joined recall has no null fields" \
    "^(client_facts|last_session|skill|how_to) +: *(Null|None)? *$"
  # SHOW SCHEMA INFO must return the ontology the walkthrough's table promises --
  # all three memory types and the relationships that join them. The previous
  # check for the string "schema" matched the script's own heading.
  for token in Memory Session Skill Action \
               HAS_MEMORY HAD_SESSION HAS_ACTION USED_SKILL FOLLOWED_BY; do
    want "schema info lists $token" "\\\\\"$token\\\\\""
  done
  want "final banner" "AI memory is live"
  want_no_query_errors
  want_running aimemory-memgraph
}

check_clean_ai_memory() {
  want_gone aimemory-memgraph
  want_absent_path "$DIR/.ai-memory-venv"
}

# ---- Runner -----------------------------------------------------------------
# Portable timeout: GNU coreutils on Linux, gtimeout from Homebrew coreutils on
# macOS, otherwise run unbounded and say so.
TIMEOUT_BIN=""
for cand in timeout gtimeout; do
  command -v "$cand" >/dev/null 2>&1 && { TIMEOUT_BIN="$cand"; break; }
done

clean_example() {
  # Best effort: a failed run may have left the example's own clean path broken.
  "$DIR/$1.sh" clean >/dev/null 2>&1 || true
}

# Generous per-example ceilings: these pull images, clone a repo, import ~3.5k
# Cypher statements and build a virtualenv, all on a cold cache.
timeout_for() {
  case "$1" in
    agentic-graphrag) echo 1800 ;;
    *)                echo 900 ;;
  esac
}

run_example() {
  name="$1"
  script="$DIR/$name.sh"
  LOG="$WORK/$name.log"
  CURRENT="$name"

  log "$name"
  if [ ! -x "$script" ]; then
    if [ -f "$script" ]; then
      fail "$name.sh is not executable (chmod +x $script)"
    else
      fail "$name.sh not found"
    fi
    return
  fi

  note "tearing down any leftovers from an earlier run"
  clean_example "$name"

  limit="$(timeout_for "$name")"
  if [ -n "$TIMEOUT_BIN" ]; then
    note "running: $name.sh  (timeout ${limit}s, log: $LOG)"
    # OPENAI_API_KEY is unset on purpose -- see the header.
    env -u OPENAI_API_KEY "$TIMEOUT_BIN" "$limit" "$script" >"$LOG" 2>&1
    status=$?
  else
    note "running: $name.sh  (no timeout command available, log: $LOG)"
    env -u OPENAI_API_KEY "$script" >"$LOG" 2>&1
    status=$?
  fi

  if [ "$status" -eq 0 ]; then
    pass "$name.sh exited 0"
  elif [ "$status" -eq 124 ] && [ -n "$TIMEOUT_BIN" ]; then
    fail "$name.sh timed out after ${limit}s"
  else
    fail "$name.sh exited $status"
    printf "       last 20 lines of %s:\n" "$LOG"
    tail -20 "$LOG" | sed 's/^/       /'
  fi

  # Assert on the output even when the exit code was bad: knowing how far it got
  # is more useful than a single FAIL line.
  "check_$(printf '%s' "$name" | tr '-' '_')"

  if [ "$KEEP" -eq 1 ]; then
    note "--keep: leaving $name's containers running"
  else
    note "tearing down"
    if "$script" clean >>"$LOG" 2>&1; then
      pass "$name.sh clean exited 0"
    else
      fail "$name.sh clean failed"
    fi
    "check_clean_$(printf '%s' "$name" | tr '-' '_')"
  fi
}

# ---- Argument parsing -------------------------------------------------------
KEEP=0
SELECTED=""
for arg in "$@"; do
  case "$arg" in
    --keep) KEEP=1 ;;
    clean)
      for name in $ALL_EXAMPLES; do
        printf 'Cleaning %s\n' "$name"
        clean_example "$name"
      done
      rm -rf "$WORK"
      echo "Cleaned up."
      exit 0
      ;;
    -h|--help)
      sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      echo "Unknown option: $arg" >&2
      exit 2
      ;;
    *)
      case " $ALL_EXAMPLES " in
        *" $arg "*)
          if [ -z "$SELECTED" ]; then SELECTED="$arg"; else SELECTED="$SELECTED $arg"; fi
          ;;
        *) echo "Unknown example: $arg (known: $ALL_EXAMPLES)" >&2; exit 2 ;;
      esac
      ;;
  esac
done
[ -n "$SELECTED" ] || SELECTED="$ALL_EXAMPLES"

# agentic-graphrag and ai-memory both publish Bolt on host port 7687, so keeping
# one example's containers alive makes the next one fail to start. Refuse the
# combination rather than reporting it as a broken example.
if [ "$KEEP" -eq 1 ]; then
  case "$SELECTED" in
    *" "*)
      echo "--keep takes a single example: the examples share host ports" >&2
      echo "7687/7688, so a kept container blocks the next run." >&2
      echo "Try: ./test.sh --keep ${SELECTED%% *}" >&2
      exit 2
      ;;
  esac
fi

# ---- Prerequisites ----------------------------------------------------------
for tool in docker git curl; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "Missing prerequisite: $tool" >&2
    exit 1
  }
done
docker info >/dev/null 2>&1 || {
  echo "Docker is installed but its engine is not responding; start it first." >&2
  exit 1
}

mkdir -p "$WORK"

log "Testing: $SELECTED"
note "logs: $WORK"
[ -n "$TIMEOUT_BIN" ] || note "no timeout/gtimeout found -- examples run unbounded"

for name in $SELECTED; do
  run_example "$name"
done

# ---- Summary ----------------------------------------------------------------
log "Summary"
printf '  %d passed, %d failed\n' "$PASSED" "$FAILED"
if [ "$FAILED" -ne 0 ]; then
  printf '%sFailures:%s%s\n' "$C_BAD" "$C_OFF" "$FAILURES"
  printf '\nFull logs: %s\n' "$WORK"
  exit 1
fi
printf '\n%sAll examples passed.%s\n' "$C_OK" "$C_OFF"
