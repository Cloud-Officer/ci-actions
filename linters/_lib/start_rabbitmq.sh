#!/usr/bin/env bash

# Starts a RabbitMQ container: `launch` in the background, then `wait` until the broker is running.

set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/background_launch.sh"

: "${RABBITMQ_VERSION:?RABBITMQ_VERSION must be set}"

phase="${1:-}"
container="${RABBITMQ_CONTAINER_NAME:-rabbitmq}"
certificates="${RABBITMQ_CERTIFICATES:-}"
config="${RABBITMQ_CONFIG:-}"
definitions="${RABBITMQ_DEFINITIONS:-}"
plugins="${RABBITMQ_PLUGINS:-}"
wait_seconds="${RABBITMQ_WAIT_SECONDS:-60}"
launch_wait_seconds="${RABBITMQ_LAUNCH_WAIT_SECONDS:-300}"

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

case "${phase}" in
  launch)
    echo "Starting RabbitMQ ${RABBITMQ_VERSION} as container ${container} in the background"
    launch_in_background "${container}" docker "${run_args[@]}"
    exit 0
    ;;
  wait) wait_for_launch "${container}" "${launch_wait_seconds}" ;;
  *)
    echo "::error::usage: start_rabbitmq.sh launch|wait" >&2
    exit 2
    ;;
esac

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
