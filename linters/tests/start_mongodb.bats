#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../_lib/start_mongodb.sh"
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
  printf '#!/usr/bin/env bash\n' > "${BIN}/sleep"
  chmod +x "${BIN}/docker" "${BIN}/sleep"
  export PATH="${BIN}:${PATH}"
  unset MONGODB_REPLICA_SET MONGODB_PORT MONGODB_DB MONGODB_USERNAME MONGODB_PASSWORD MONGODB_WAIT_SECONDS
}

teardown() {
  rm -rf "${BIN}"
}

@test "starts a single node on the requested port and waits for a ping" {
  MONGODB_VERSION=7.0 MONGODB_PORT=27018 run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "${LOG}")" = 'run|--detach|--name|mongodb|--publish|27018:27018|mongo:7.0|--port|27018|' ]
  [ "$(sed -n 2p "${LOG}")" = 'exec|mongodb|mongosh|--quiet|--port|27018|--eval|db.runCommand({ ping: 1 })|' ]
  [ "$(wc -l < "${LOG}" | tr -d ' ')" = 2 ]
}

@test "creates the root user and database and authenticates the readiness probe" {
  MONGODB_VERSION=8.0 MONGODB_PORT=27017 MONGODB_DB=app MONGODB_USERNAME=root MONGODB_PASSWORD='s3 cret' run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "${LOG}")" = 'run|--detach|--name|mongodb|--publish|27017:27017|--env|MONGO_INITDB_DATABASE=app|--env|MONGO_INITDB_ROOT_USERNAME=root|--env|MONGO_INITDB_ROOT_PASSWORD=s3 cret|mongo:8.0|--port|27017|' ]
  [ "$(sed -n 2p "${LOG}")" = 'exec|mongodb|mongosh|--quiet|--port|27017|--username|root|--password|s3 cret|--eval|db.runCommand({ ping: 1 })|' ]
}

@test "uses the legacy mongo shell for MongoDB 4 and older" {
  MONGODB_VERSION=4.4 run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ "$(sed -n 2p "${LOG}")" = 'exec|mongodb|mongo|--quiet|--port|27017|--eval|db.runCommand({ ping: 1 })|' ]
}

@test "uses mongosh for MongoDB 10 and for non-numeric tags" {
  MONGODB_VERSION=10.0 run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$(sed -n 2p "${LOG}")" == 'exec|mongodb|mongosh|'* ]]
  rm -f "${LOG}"
  MONGODB_VERSION=latest run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$(sed -n 2p "${LOG}")" == 'exec|mongodb|mongosh|'* ]]
}

@test "starts a replica set, initiates it and waits for a primary" {
  MONGODB_VERSION=7.0 MONGODB_REPLICA_SET=rs0 MONGODB_PORT=27017 MONGODB_USERNAME=ignored run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "${LOG}")" = 'run|--detach|--name|mongodb|--publish|27017:27017|mongo:7.0|--port|27017|--replSet|rs0|' ]
  [ "$(sed -n 2p "${LOG}")" = 'exec|mongodb|mongosh|--quiet|--port|27017|--eval|db.runCommand({ ping: 1 })|' ]
  [ "$(sed -n 3p "${LOG}")" = "exec|mongodb|mongosh|--quiet|--port|27017|--eval|rs.initiate({ _id: 'rs0', members: [{ _id: 0, host: 'localhost:27017' }] })|" ]
  [ "$(sed -n 4p "${LOG}")" = 'exec|mongodb|mongosh|--quiet|--port|27017|--eval|quit(rs.status().myState === 1 ? 0 : 1)|' ]
}

@test "retries the readiness probe until MongoDB answers" {
  MONGODB_VERSION=7.0 DOCKER_EXEC_FAILURES=3 run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^exec|' "${LOG}")" = 4 ]
}

@test "fails and prints the container logs when MongoDB never answers" {
  MONGODB_VERSION=7.0 MONGODB_WAIT_SECONDS=2 DOCKER_EXEC_FAILURES=99 run bash "${SCRIPT}"
  [ "$status" -eq 1 ]
  [[ "$output" == *'::error::MongoDB did not accept connections within 2 seconds'* ]]
  [ "$(tail -n 1 "${LOG}")" = 'logs|mongodb|' ]
}

@test "fails without waiting when the container does not start" {
  printf '#!/usr/bin/env bash\nprintf "%%s|" "$@" >> "%s"\nexit 125\n' "${LOG}" > "${BIN}/docker"
  MONGODB_VERSION=7.0 run bash "${SCRIPT}"
  [ "$status" -eq 125 ]
  [ "$(cat "${LOG}")" = 'run|--detach|--name|mongodb|--publish|27017:27017|mongo:7.0|--port|27017|' ]
}

@test "fails when MONGODB_VERSION is not set" {
  run env -u MONGODB_VERSION bash "${SCRIPT}"
  [ "$status" -ne 0 ]
  [ ! -e "${LOG}" ]
}
