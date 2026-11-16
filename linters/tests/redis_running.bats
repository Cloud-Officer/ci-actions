#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../_lib/redis_running.sh"
  WORK="$(mktemp -d)"
  export GITHUB_OUTPUT="${WORK}/github_output"
  touch "${GITHUB_OUTPUT}"
}

teardown() {
  if [ -n "${LISTENER:-}" ]; then
    kill "${LISTENER}" 2>/dev/null || true
  fi
  rm -rf "${WORK}"
}

free_port() {
  python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'
}

start_listener() {
  REPLY_BYTES="$1" python3 -c 'import os, socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
s.listen(5)
print(s.getsockname()[1], flush=True)
reply = os.environ["REPLY_BYTES"].encode().decode("unicode_escape").encode()
s.settimeout(30)
while True:
    c, _ = s.accept()
    c.recv(64)
    if reply:
        c.sendall(reply)
    c.close()' > "${WORK}/port" &
  LISTENER=$!
  for _ in $(seq 50); do
    [ -s "${WORK}/port" ] && break
    sleep 0.1
  done
}

@test "reports running=true when the listener answers PING with +PONG" {
  start_listener '+PONG\r\n'
  port="$(cat "${WORK}/port")"
  run env PORT="${port}" bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ "$(cat "${GITHUB_OUTPUT}")" = 'running=true' ]
  [ "$output" = "Redis is already running on port ${port}" ]
}

@test "reports running=true when Redis requires auth" {
  start_listener '-NOAUTH Authentication required.\r\n'
  run env PORT="$(cat "${WORK}/port")" bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ "$(cat "${GITHUB_OUTPUT}")" = 'running=true' ]
}

@test "reports running=false when the listener is not Redis" {
  start_listener 'HTTP/1.1 400 Bad Request\r\n'
  run env PORT="$(cat "${WORK}/port")" bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ "$(cat "${GITHUB_OUTPUT}")" = 'running=false' ]
}

@test "reports running=false when the listener closes without replying" {
  start_listener ''
  run env PORT="$(cat "${WORK}/port")" bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ "$(cat "${GITHUB_OUTPUT}")" = 'running=false' ]
}

@test "reports running=false when nothing listens on the port" {
  run env PORT="$(free_port)" bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ "$(cat "${GITHUB_OUTPUT}")" = 'running=false' ]
}

@test "fails with an error when PORT is not set" {
  run env -u PORT bash "${SCRIPT}"
  [ "$status" -eq 1 ]
  [[ "$output" == *'::error::PORT is required'* ]]
  [ ! -s "${GITHUB_OUTPUT}" ]
}
