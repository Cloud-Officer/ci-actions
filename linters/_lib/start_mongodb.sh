#!/usr/bin/env bash

# Starts a MongoDB container (single node, or a one-member replica set): `launch` in the background, then `wait` until ready.

set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/background_launch.sh"

: "${MONGODB_VERSION:?MONGODB_VERSION must be set}"

phase="${1:-}"
port="${MONGODB_PORT:-27017}"
replica_set="${MONGODB_REPLICA_SET:-}"
db="${MONGODB_DB:-}"
username="${MONGODB_USERNAME:-}"
password="${MONGODB_PASSWORD:-}"
container="${MONGODB_CONTAINER_NAME:-mongodb}"
wait_seconds="${MONGODB_WAIT_SECONDS:-30}"
launch_wait_seconds="${MONGODB_LAUNCH_WAIT_SECONDS:-300}"
image="mongo:${MONGODB_VERSION}"

client=(mongosh --quiet)
major="${MONGODB_VERSION%%.*}"
if [[ "${major}" =~ ^[0-9]+$ ]] && ((major <= 4)); then
  client=(mongo --quiet)
fi

auth=()
if [[ -z "${replica_set}" && -n "${username}" ]]; then
  auth=(--username "${username}" --password "${password}")
fi

function mongo_eval()
{
  docker exec "${container}" "${client[@]}" --port "${port}" ${auth[@]+"${auth[@]}"} --eval "$1"
}

function wait_until()
{
  local what="$1" script="$2" waited=0

  until mongo_eval "${script}" > /dev/null 2>&1; do
    if ((waited >= wait_seconds)); then
      echo "::error::MongoDB ${what} within ${wait_seconds} seconds"
      docker logs "${container}" || true
      exit 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
}

function launch()
{
  local run_args=(run --detach --name "${container}" --publish "${port}:${port}")

  if [[ -z "${replica_set}" ]]; then
    [[ -n "${db}" ]] && run_args+=(--env "MONGO_INITDB_DATABASE=${db}")
    [[ -n "${username}" ]] && run_args+=(--env "MONGO_INITDB_ROOT_USERNAME=${username}")
    [[ -n "${password}" ]] && run_args+=(--env "MONGO_INITDB_ROOT_PASSWORD=${password}")
    run_args+=("${image}" --port "${port}")
    echo "Starting MongoDB ${MONGODB_VERSION} on port ${port} in the background"
  else
    run_args+=("${image}" --port "${port}" --replSet "${replica_set}")
    echo "Starting MongoDB ${MONGODB_VERSION} on port ${port} as replica set ${replica_set} in the background"
  fi

  launch_in_background "${container}" docker "${run_args[@]}"
}

function wait_ready()
{
  wait_for_launch "${container}" "${launch_wait_seconds}"
  wait_until "did not accept connections" 'db.runCommand({ ping: 1 })'
  [[ -z "${replica_set}" ]] && return 0
  mongo_eval "rs.initiate({ _id: '${replica_set}', members: [{ _id: 0, host: 'localhost:${port}' }] })"
  wait_until "replica set ${replica_set} did not elect a primary" 'quit(rs.status().myState === 1 ? 0 : 1)'
}

case "${phase}" in
  launch) launch ;;
  wait) wait_ready ;;
  *)
    echo "::error::usage: start_mongodb.sh launch|wait" >&2
    exit 2
    ;;
esac
