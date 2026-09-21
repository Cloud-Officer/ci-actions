#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../_lib/retry.sh"
  WORK="$(mktemp -d)"
  export RETRY_DELAY=0
}

teardown() {
  rm -rf "${WORK}"
}

flaky() {
  printf '#!/usr/bin/env bash\ncount="$(cat "%s/count" 2>/dev/null || echo 0)"\necho $((count + 1)) > "%s/count"\n[ "$((count + 1))" -ge "$1" ] || exit 7\n' \
    "${WORK}" "${WORK}" > "${WORK}/flaky"
  chmod +x "${WORK}/flaky"
}

@test "succeeds without retrying when the command succeeds" {
  flaky
  run bash "${SCRIPT}" "${WORK}/flaky" 1
  [ "$status" -eq 0 ]
  [ "$(cat "${WORK}/count")" = 1 ]
}

@test "retries until the command succeeds" {
  flaky
  run bash "${SCRIPT}" "${WORK}/flaky" 3
  [ "$status" -eq 0 ]
  [ "$(cat "${WORK}/count")" = 3 ]
  [[ "$output" == *'attempt 1/3'* ]]
  [[ "$output" == *'attempt 2/3'* ]]
}

@test "gives up after the configured attempts with the command's status" {
  flaky
  RETRY_ATTEMPTS=2 run bash "${SCRIPT}" "${WORK}/flaky" 5
  [ "$status" -eq 7 ]
  [ "$(cat "${WORK}/count")" = 2 ]
  [[ "$output" == *'failed after 2 attempts'* ]]
}

@test "passes arguments through unchanged" {
  run bash "${SCRIPT}" printf '%s|' 'a b' c
  [ "$status" -eq 0 ]
  [ "$output" = 'a b|c|' ]
}

@test "fails with usage when no command is given" {
  run bash "${SCRIPT}"
  [ "$status" -eq 2 ]
  [[ "$output" == *'usage'* ]]
}
