#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../_lib/background_launch.sh"
  RUNNER_TEMP="$(mktemp -d)"
  export RUNNER_TEMP
  GATE="${RUNNER_TEMP}/gate"
  BLOCKED="${RUNNER_TEMP}/blocked"
  printf '#!/usr/bin/env bash\nuntil [ -e "%s" ]; do sleep 0.01; done\necho "finished $1"\nexit "$2"\n' "${GATE}" > "${BLOCKED}"
  chmod +x "${BLOCKED}"
}

teardown() {
  touch "${GATE}"
  if [ -e "${RUNNER_TEMP}/background-launch/svc.log" ]; then
    wait_for_launch svc 50 > /dev/null || true
  fi
  rm -rf "${RUNNER_TEMP}"
}

@test "returns before the command finishes" {
  launch_in_background svc "${BLOCKED}" one 0
  [ ! -e "${RUNNER_TEMP}/background-launch/svc.status" ]
  touch "${GATE}"
  run wait_for_launch svc 50
  [ "$status" -eq 0 ]
  [ "$output" = 'finished one' ]
}

@test "returns the command's exit status and prints its output on failure" {
  touch "${GATE}"
  launch_in_background svc "${BLOCKED}" two 125
  run wait_for_launch svc 50
  [ "$status" -eq 125 ]
  [[ "$output" == *'finished two'* ]]
  [[ "$output" == *'::error::svc failed to launch (exit 125)'* ]]
}

@test "fails with the partial output when the command does not finish in time" {
  launch_in_background svc bash -c 'echo pulling; until [ -e "$1" ]; do sleep 0.01; done' _ "${GATE}"
  run wait_for_launch svc 1
  [ "$status" -eq 1 ]
  [[ "$output" == *'::error::svc did not finish launching within 1 seconds'* ]]
  [[ "$output" == *'pulling'* ]]
}

@test "fails when nothing was launched" {
  run wait_for_launch missing 0
  [ "$status" -eq 1 ]
  [ "$output" = '::error::missing did not finish launching within 0 seconds' ]
}

@test "a new launch discards the previous result" {
  touch "${GATE}"
  launch_in_background svc "${BLOCKED}" first 3
  wait_for_launch svc 50 || true
  rm -f "${GATE}"
  launch_in_background svc "${BLOCKED}" second 0
  [ ! -e "${RUNNER_TEMP}/background-launch/svc.status" ]
  touch "${GATE}"
  run wait_for_launch svc 50
  [ "$status" -eq 0 ]
  [ "$output" = 'finished second' ]
}

@test "treats a non-numeric status as a failure" {
  mkdir -p "${RUNNER_TEMP}/background-launch"
  : > "${RUNNER_TEMP}/background-launch/svc.log"
  echo 'x[$(touch pwned)]' > "${RUNNER_TEMP}/background-launch/svc.status"
  cd "${RUNNER_TEMP}"
  run wait_for_launch svc 5
  [ "$status" -eq 1 ]
  [ ! -e pwned ]
}
