#!/usr/bin/env bats

# Drives the real asg-rollout/rollout.sh with a fake aws CLI that plays back build statuses and log pages.
setup() {
  export DEPLOY_ENVIRONMENT=beta1 DEPLOY_INSTANCES=api,worker DEPLOY_FLAGS="" PROJECT_NAME=deploy-runner MONITOR_TIMEOUT_MINUTES=180 POLL_INTERVAL=1
  BIN="${BATS_TEST_TMPDIR}/bin"
  CALLS="${BATS_TEST_TMPDIR}/calls"
  STATUSES="${BATS_TEST_TMPDIR}/statuses"
  mkdir -p "${BIN}"
  : >"${CALLS}"
  printf '%s\n' IN_PROGRESS SUCCEEDED >"${STATUSES}"
  export CALLS STATUSES
  cat >"${BIN}/aws" <<'AWS'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${CALLS}"
case "$1 $2" in
  "codebuild start-build") [ -z "${STUB_START_FAIL:-}" ] || exit 254; echo "deploy-runner:build-1" ;;
  "codebuild batch-get-builds")
    status=$(head -n 1 "${STATUSES}")
    [ "$(wc -l <"${STATUSES}")" -le 1 ] || sed -i.bak '1d' "${STATUSES}"
    printf '%s\t%s\t%s\n' "${status}" /aws/codebuild/deploy-runner stream-1 ;;
  "logs get-log-events")
    if [[ "$*" == *"--next-token token-1"* ]]; then
      echo '{"events":[{"message":"rollout done\n"}],"nextForwardToken":"token-2"}'
    else
      echo '{"events":[{"message":"deploy-runner: deploy --profile bre\n"}],"nextForwardToken":"token-1"}'
    fi ;;
esac
AWS
  printf '#!/usr/bin/env bash\nexit 0\n' >"${BIN}/sleep"
  chmod +x "${BIN}/aws" "${BIN}/sleep"
}

run_rollout() {
  run env PATH="${BIN}:${PATH}" bash "${BATS_TEST_DIRNAME}/../asg-rollout/rollout.sh"
}

start_call() {
  grep '^codebuild start-build' "${CALLS}"
}

@test "starts deploy-runner with the run inputs only" {
  run_rollout
  [ "$status" -eq 0 ]
  [ "$(start_call)" = 'codebuild start-build --project-name deploy-runner --environment-variables-override [{"name":"DEPLOY_ENVIRONMENT","value":"beta1","type":"PLAINTEXT"},{"name":"DEPLOY_INSTANCES","value":"api,worker","type":"PLAINTEXT"},{"name":"DEPLOY_FLAGS","value":"","type":"PLAINTEXT"}] --query build.id --output text' ]
}

@test "passes the allowed flags" {
  export DEPLOY_FLAGS="--redeploy-latest --sequential_rollout"
  run_rollout
  [ "$status" -eq 0 ]
  [[ "$(start_call)" == *'{"name":"DEPLOY_FLAGS","value":"--redeploy-latest --sequential_rollout","type":"PLAINTEXT"}'* ]]
}

@test "streams the build log into the job once" {
  run_rollout
  [ "$status" -eq 0 ]
  [ "$(grep -c 'deploy-runner: deploy --profile bre' <<<"$output")" -eq 1 ]
  [[ "$output" == *"rollout done"* ]]
  [[ "$output" == *"deploy-runner build deploy-runner:build-1 succeeded"* ]]
}

@test "fails the job when the build fails, is stopped or times out" {
  local status_name

  for status_name in FAILED FAULT STOPPED TIMED_OUT; do
    printf '%s\n' IN_PROGRESS "${status_name}" >"${STATUSES}"
    run_rollout
    [ "$status" -eq 1 ]
    [[ "$output" == *"::error::deploy-runner build deploy-runner:build-1 ${status_name}"* ]]
  done
}

@test "keeps following through a transient CodeBuild error" {
  printf '%s\n' UNKNOWN IN_PROGRESS SUCCEEDED >"${STATUSES}"
  run_rollout
  [ "$status" -eq 0 ]
  [ "$(grep -c '^codebuild batch-get-builds' "${CALLS}")" -eq 3 ]
}

@test "gives up after the monitoring window, leaving the build running" {
  export MONITOR_TIMEOUT_MINUTES=1 POLL_INTERVAL=30
  printf '%s\n' IN_PROGRESS >"${STATUSES}"
  run_rollout
  [ "$status" -eq 1 ]
  [[ "$output" == *"did not finish within 1 minutes; it keeps running in CodeBuild"* ]]
  [ "$(grep -c '^codebuild batch-get-builds' "${CALLS}")" -eq 2 ]
}

@test "fails when the build cannot start" {
  export STUB_START_FAIL=1
  run_rollout
  [ "$status" -ne 0 ]
  [ -z "$(grep '^codebuild batch-get-builds' "${CALLS}")" ]
}

@test "refuses flags deploy-runner does not allow" {
  local flag

  for flag in --skip-rollback --skip-lock --reset-instances "--resize m5.large" '$(id)'; do
    : >"${CALLS}"
    export DEPLOY_FLAGS="${flag}"
    run_rollout
    [ "$status" -eq 1 ]
    [[ "$output" == *"is not allowed"* ]]
    [ ! -s "${CALLS}" ]
  done
}

@test "refuses malformed inputs before calling AWS" {
  local input

  for input in DEPLOY_ENVIRONMENT=beta DEPLOY_ENVIRONMENT="beta1;id" DEPLOY_INSTANCES= DEPLOY_INSTANCES=web DEPLOY_INSTANCES="api,worker,"  PROJECT_NAME="x y" MONITOR_TIMEOUT_MINUTES=0; do
    : >"${CALLS}"
    run env "${input}" PATH="${BIN}:${PATH}" bash "${BATS_TEST_DIRNAME}/../asg-rollout/rollout.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == "::error::"* ]]
    [ ! -s "${CALLS}" ]
  done
}

@test "prints nothing for a build without a log stream yet" {
  source "${BATS_TEST_DIRNAME}/../asg-rollout/rollout.sh"
  run print_new_log_lines None None
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
