#!/usr/bin/env bash

# Starts a RabbitMQ container and waits until the broker is running.

set -euo pipefail

: "${RABBITMQ_VERSION:?RABBITMQ_VERSION must be set}"

container="${RABBITMQ_CONTAINER_NAME:-rabbitmq}"
certificates="${RABBITMQ_CERTIFICATES:-}"
config="${RABBITMQ_CONFIG:-}"
definitions="${RABBITMQ_DEFINITIONS:-}"
plugins="${RABBITMQ_PLUGINS:-}"
wait_seconds="${RABBITMQ_WAIT_SECONDS:-60}"

run_args=(run --detach --name "${container}")

read -r -a ports <<< "${RABBITMQ_PORTS:-}"
for mapping in ${ports[@]+"${ports[@]}"}; do
  run_args+=(--publish "${mapping}")
done

[[ -n "${certificates}" ]] && run_args+=(--volume "${certificates}:/rabbitmq-certs:ro")
[[ -n "${config}" ]] && run_args+=(--volume "${config}:/etc/rabbitmq/rabbitmq.conf:ro")
if [[ -n "${definitions}" ]]; then
  run_args+=(--volume "${definitions}:/etc/rabbitmq/definitions.json:ro")
  run_args+=(--env "RABBITMQ_SERVER_ADDITIONAL_ERL_ARGS=-rabbitmq_management load_definitions '/etc/rabbitmq/definitions.json'")
fi

run_args+=("rabbitmq:${RABBITMQ_VERSION}")

if [[ -n "${plugins}" ]]; then
  # shellcheck disable=SC2016 # $1 is expanded by the container's shell, not this one.
  run_args+=(sh -c 'printf "[%s].\n" "$1" > /etc/rabbitmq/enabled_plugins && exec docker-entrypoint.sh rabbitmq-server' sh "${plugins}")
fi

echo "Starting RabbitMQ ${RABBITMQ_VERSION} as container ${container}"
docker "${run_args[@]}"

waited=0
until docker exec --user rabbitmq "${container}" rabbitmq-diagnostics --quiet check_running > /dev/null 2>&1; do
  if ((waited >= wait_seconds)); then
    echo "::error::RabbitMQ did not start within ${wait_seconds} seconds"
    docker logs "${container}" || true
    exit 1
  fi
  sleep 1
  waited=$((waited + 1))
done
