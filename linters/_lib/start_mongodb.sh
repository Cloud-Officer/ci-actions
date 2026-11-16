#!/usr/bin/env bash

# Starts a MongoDB container (single node, or a one-member replica set) and waits until it accepts connections.

set -euo pipefail

: "${MONGODB_VERSION:?MONGODB_VERSION must be set}"

port="${MONGODB_PORT:-27017}"
replica_set="${MONGODB_REPLICA_SET:-}"
db="${MONGODB_DB:-}"
username="${MONGODB_USERNAME:-}"
password="${MONGODB_PASSWORD:-}"
container="${MONGODB_CONTAINER_NAME:-mongodb}"
wait_seconds="${MONGODB_WAIT_SECONDS:-30}"
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

run_args=(run --detach --name "${container}" --publish "${port}:${port}")

if [[ -z "${replica_set}" ]]; then
  [[ -n "${db}" ]] && run_args+=(--env "MONGO_INITDB_DATABASE=${db}")
  [[ -n "${username}" ]] && run_args+=(--env "MONGO_INITDB_ROOT_USERNAME=${username}")
  [[ -n "${password}" ]] && run_args+=(--env "MONGO_INITDB_ROOT_PASSWORD=${password}")
  echo "Starting MongoDB ${MONGODB_VERSION} on port ${port}"
  docker "${run_args[@]}" "${image}" --port "${port}"
  wait_until "did not accept connections" 'db.runCommand({ ping: 1 })'
  exit 0
fi

echo "Starting MongoDB ${MONGODB_VERSION} on port ${port} as replica set ${replica_set}"
docker "${run_args[@]}" "${image}" --port "${port}" --replSet "${replica_set}"
wait_until "did not accept connections" 'db.runCommand({ ping: 1 })'
mongo_eval "rs.initiate({ _id: '${replica_set}', members: [{ _id: 0, host: 'localhost:${port}' }] })"
wait_until "replica set ${replica_set} did not elect a primary" 'quit(rs.status().myState === 1 ? 0 : 1)'
