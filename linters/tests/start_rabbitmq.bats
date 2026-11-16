#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../_lib/start_rabbitmq.sh"
  BIN="$(mktemp -d)"
  LOG="${BIN}/docker.log"
  COUNT="${BIN}/exec.count"
  cat > "${BIN}/docker" <<EOF
#!/usr/bin/env bash
printf '%s|' "\$@" >> "${LOG}"
printf '\n' >> "${LOG}"
if [ "\$1" = exec ]; then
  n=\$((\$(cat "${COUNT}" 2>/dev/null || echo 0) + 1))
  echo "\${n}" > "${COUNT}"
  if [ "\${n}" -le "\${DOCKER_EXEC_FAILURES:-0}" ]; then exit 1; fi
fi
EOF
  printf '#!/usr/bin/env bash\nexec /bin/sleep 0.01\n' > "${BIN}/sleep"
  chmod +x "${BIN}/docker" "${BIN}/sleep"
  export PATH="${BIN}:${PATH}"
  export RUNNER_TEMP="${BIN}"
  unset RABBITMQ_PORTS RABBITMQ_CERTIFICATES RABBITMQ_CONFIG RABBITMQ_DEFINITIONS RABBITMQ_PLUGINS RABBITMQ_CONTAINER_NAME RABBITMQ_WAIT_SECONDS
}

start_service() {
  bash "${SCRIPT}" launch > /dev/null && bash "${SCRIPT}" wait
}

teardown() {
  rm -rf "${BIN}"
}

@test "publishes each port mapping and waits until the broker runs" {
  RABBITMQ_VERSION=4.1 RABBITMQ_PORTS='5672:5672 15672:15672' RABBITMQ_CONTAINER_NAME=rabbitmq run start_service
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "${LOG}")" = 'run|--detach|--name|rabbitmq|--publish|5672:5672|--publish|15672:15672|rabbitmq:4.1|' ]
  [ "$(sed -n 2p "${LOG}")" = 'exec|--user|rabbitmq|rabbitmq|rabbitmq-diagnostics|--quiet|check_running|' ]
  [ "$(wc -l < "${LOG}" | tr -d ' ')" = 2 ]
}

@test "mounts certificates, config and definitions read-only and loads the definitions" {
  RABBITMQ_VERSION=4.1-management RABBITMQ_PORTS='5672:5672' RABBITMQ_CERTIFICATES=/certs RABBITMQ_CONFIG=/cfg/rabbitmq.conf \
    RABBITMQ_DEFINITIONS=/cfg/definitions.json RABBITMQ_CONTAINER_NAME=broker run start_service
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "${LOG}")" = "run|--detach|--name|broker|--publish|5672:5672|--volume|/certs:/rabbitmq-certs:ro|--volume|/cfg/rabbitmq.conf:/etc/rabbitmq/rabbitmq.conf:ro|--volume|/cfg/definitions.json:/etc/rabbitmq/definitions.json:ro|--env|RABBITMQ_SERVER_ADDITIONAL_ERL_ARGS=-rabbitmq_management load_definitions '/etc/rabbitmq/definitions.json'|rabbitmq:4.1-management|" ]
  [ "$(sed -n 2p "${LOG}")" = 'exec|--user|rabbitmq|broker|rabbitmq-diagnostics|--quiet|check_running|' ]
}

@test "writes the enabled plugins before starting the server" {
  RABBITMQ_VERSION=4.1 RABBITMQ_PLUGINS='rabbitmq_management,rabbitmq_mqtt' run start_service
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "${LOG}")" = 'run|--detach|--name|rabbitmq|rabbitmq:4.1|sh|-c|printf "[%s].\n" "$1" > /etc/rabbitmq/enabled_plugins && exec docker-entrypoint.sh rabbitmq-server|sh|rabbitmq_management,rabbitmq_mqtt|' ]
}

@test "the plugins command writes an Erlang list then starts the server" {
  printf '#!/usr/bin/env bash\necho "started $*"\n' > "${BIN}/docker-entrypoint.sh"
  chmod +x "${BIN}/docker-entrypoint.sh"
  RABBITMQ_VERSION=4.1 RABBITMQ_PLUGINS='rabbitmq_management,rabbitmq_mqtt' run start_service
  command="$(sed -n 1p "${LOG}" | cut -d'|' -f8)"
  out="${BIN}/enabled_plugins"
  run sh -c "${command//\/etc\/rabbitmq\/enabled_plugins/${out}}" sh 'rabbitmq_management,rabbitmq_mqtt'
  [ "$status" -eq 0 ]
  [ "$output" = 'started rabbitmq-server' ]
  [ "$(cat "${out}")" = '[rabbitmq_management,rabbitmq_mqtt].' ]
}

@test "retries until the broker runs" {
  RABBITMQ_VERSION=4.1 DOCKER_EXEC_FAILURES=5 run start_service
  [ "$status" -eq 0 ]
  [ "$(grep -c '^exec|' "${LOG}")" = 6 ]
}

@test "fails and prints the container logs when the broker never starts" {
  RABBITMQ_VERSION=4.1 RABBITMQ_WAIT_SECONDS=2 DOCKER_EXEC_FAILURES=99 run start_service
  [ "$status" -eq 1 ]
  [[ "$output" == *'::error::RabbitMQ did not start within 2 seconds'* ]]
  [ "$(tail -n 1 "${LOG}")" = 'logs|rabbitmq|' ]
}

@test "fails without waiting when the container does not start" {
  printf '#!/usr/bin/env bash\nprintf "%%s|" "$@" >> "%s"\nexit 125\n' "${LOG}" > "${BIN}/docker"
  RABBITMQ_VERSION=4.1 run start_service
  [ "$status" -eq 125 ]
  [ "$(cat "${LOG}")" = 'run|--detach|--name|rabbitmq|rabbitmq:4.1|' ]
}

@test "fails when RABBITMQ_VERSION is not set" {
  run env -u RABBITMQ_VERSION bash "${SCRIPT}" launch
  [ "$status" -ne 0 ]
  [ ! -e "${LOG}" ]
}

@test "launch starts the container in the background without probing it" {
  RABBITMQ_VERSION=4.1 run bash "${SCRIPT}" launch
  [ "$status" -eq 0 ]
  [ "$output" = 'Starting RabbitMQ 4.1 as container rabbitmq in the background' ]
  until [ -e "${BIN}/background-launch/rabbitmq.status" ]; do /bin/sleep 0.01; done
  [ "$(cat "${LOG}")" = 'run|--detach|--name|rabbitmq|rabbitmq:4.1|' ]
}

@test "rejects a missing or unknown phase" {
  RABBITMQ_VERSION=4.1 run bash "${SCRIPT}"
  [ "$status" -eq 2 ]
  RABBITMQ_VERSION=4.1 run bash "${SCRIPT}" start
  [ "$status" -eq 2 ]
  [ ! -e "${LOG}" ]
}
