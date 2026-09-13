#!/usr/bin/env bats

# Setup: source the real deploy.sh for its function definitions. The script
# guards its main body behind `[[ "${BASH_SOURCE[0]}" == "${0}" ]]`, so sourcing
# here loads create_deployment / poll_deployment without launching a real AWS
# deployment.
setup() {
  export APPLICATION_NAME="app"
  export DEPLOYMENT_GROUP_NAME="group"
  export DEPLOYMENT_STRATEGY="CodeDeployDefault.OneAtATime"
  export S3_BUCKET="bucket"
  export S3_KEY="key.zip"
  export GITHUB_RUN_NUMBER=100
  export MONITOR_TIMEOUT_MINUTES=30
  # Non-zero so main()'s `max_iterations = MINUTES*60/POLL_INTERVAL` never
  # divides by zero; the loop is kept instant by the stubbed sleep instead.
  export POLL_INTERVAL=1

  source "${BATS_TEST_DIRNAME}/../deploy/deploy.sh"

  # Never actually sleep during the polling loop (sourced unit tests).
  sleep() { :; }
}

# Build a throwaway PATH dir with fake `aws` / `sleep` executables so the
# end-to-end tests can drive the real deploy.sh as a subprocess (mirroring the
# variables.bats subprocess pattern) rather than a re-implementation.
make_fake_bin() {
  local create_out="$1" get_out="$2"
  local bin="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${bin}"
  cat > "${bin}/aws" <<EOF
#!/usr/bin/env bash
if [ "\$2" = "create-deployment" ]; then echo "${create_out}"; else echo "${get_out}"; fi
EOF
  printf '#!/usr/bin/env bash\nexit 0\n' > "${bin}/sleep"
  chmod +x "${bin}/aws" "${bin}/sleep"
  echo "${bin}"
}

# ============================================================================
# create_deployment
# ============================================================================

@test "create_deployment returns the deployment id from aws" {
  aws() { echo "d-ABC123"; }
  run create_deployment
  [ "$status" -eq 0 ]
  [ "$output" = "d-ABC123" ]
}

@test "create_deployment passes the build number in the description" {
  # Echo the args so we can assert the create-deployment invocation shape.
  aws() { echo "$*"; }
  run create_deployment
  [ "$status" -eq 0 ]
  [[ "$output" == *"create-deployment"* ]]
  [[ "$output" == *"--application-name app"* ]]
  [[ "$output" == *"Deploy build 100 via Github Actions"* ]]
  [[ "$output" == *"bucket=bucket,bundleType=zip,key=key.zip"* ]]
}

# ============================================================================
# poll_deployment: terminal states
# ============================================================================

@test "poll_deployment returns 0 when deployment Succeeded" {
  aws() { echo "Succeeded"; }
  run poll_deployment "d-1" 5
  [ "$status" -eq 0 ]
  [[ "$output" == *"Deployment succeeded"* ]]
}

@test "poll_deployment returns 1 when deployment Failed" {
  aws() { echo "Failed"; }
  run poll_deployment "d-1" 5
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::CodeDeploy deployment Failed (id=d-1)"* ]]
}

@test "poll_deployment returns 1 when deployment Stopped" {
  aws() { echo "Stopped"; }
  run poll_deployment "d-1" 5
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::CodeDeploy deployment Stopped (id=d-1)"* ]]
}

# ============================================================================
# poll_deployment: non-terminal progression and transient errors
# ============================================================================

@test "poll_deployment keeps polling through non-terminal states then succeeds" {
  # InProgress, then InProgress, then Succeeded across three polls.
  cat > "${BATS_TEST_TMPDIR:-/tmp}/calls" <<< "0"
  aws() {
    local n
    n=$(cat "${BATS_TEST_TMPDIR:-/tmp}/calls")
    n=$(( n + 1 ))
    echo "${n}" > "${BATS_TEST_TMPDIR:-/tmp}/calls"
    if [ "${n}" -lt 3 ]; then echo "InProgress"; else echo "Succeeded"; fi
  }
  run poll_deployment "d-1" 5
  [ "$status" -eq 0 ]
  [[ "$output" == *"Deployment status=InProgress... (1/5)"* ]]
  [[ "$output" == *"Deployment status=InProgress... (2/5)"* ]]
  [[ "$output" == *"Deployment succeeded"* ]]
}

@test "poll_deployment tolerates a transient aws error then succeeds" {
  cat > "${BATS_TEST_TMPDIR:-/tmp}/calls" <<< "0"
  aws() {
    local n
    n=$(cat "${BATS_TEST_TMPDIR:-/tmp}/calls")
    n=$(( n + 1 ))
    echo "${n}" > "${BATS_TEST_TMPDIR:-/tmp}/calls"
    # First call simulates an API failure (non-zero, no stdout): the script's
    # `|| echo "Unknown"` must absorb it and keep polling.
    if [ "${n}" -eq 1 ]; then return 255; fi
    echo "Succeeded"
  }
  run poll_deployment "d-1" 5
  [ "$status" -eq 0 ]
  [[ "$output" == *"Deployment status=Unknown... (1/5)"* ]]
  [[ "$output" == *"Deployment succeeded"* ]]
}

# ============================================================================
# poll_deployment: timeout
# ============================================================================

@test "poll_deployment returns 2 and errors when it never reaches a terminal state" {
  aws() { echo "InProgress"; }
  run poll_deployment "d-1" 3
  [ "$status" -eq 2 ]
  [[ "$output" == *"Deployment status=InProgress... (3/3)"* ]]
  [[ "$output" == *"::error::Deployment d-1 did not reach a terminal state within 30 minutes"* ]]
}

# ============================================================================
# End-to-end: main() maps a failed deployment to a non-zero step exit
# ============================================================================

@test "main exits 1 when the deployment Fails (no false-green)" {
  local bin
  bin=$(make_fake_bin "d-FAIL" "Failed")
  run env PATH="${bin}:${PATH}" bash "${BATS_TEST_DIRNAME}/../deploy/deploy.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::CodeDeploy deployment Failed (id=d-FAIL)"* ]]
}

@test "main exits 0 when the deployment Succeeds" {
  local bin
  bin=$(make_fake_bin "d-OK" "Succeeded")
  run env PATH="${bin}:${PATH}" bash "${BATS_TEST_DIRNAME}/../deploy/deploy.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Deployment ID=d-OK"* ]]
  [[ "$output" == *"Deployment succeeded"* ]]
}

@test "main exits 1 when the deployment times out" {
  local bin
  bin=$(make_fake_bin "d-SLOW" "InProgress")
  run env PATH="${bin}:${PATH}" MONITOR_TIMEOUT_MINUTES=1 POLL_INTERVAL=1 \
    bash "${BATS_TEST_DIRNAME}/../deploy/deploy.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"did not reach a terminal state"* ]]
}

# ============================================================================
# Input validation: monitor-timeout-minutes and POLL_INTERVAL
# ============================================================================

make_logging_aws() {
  local bin="${BATS_TEST_TMPDIR}/logbin"
  mkdir -p "${bin}"
  cat > "${bin}/aws" <<LOG
#!/usr/bin/env bash
echo "\$*" >> "${BATS_TEST_TMPDIR}/aws.log"
if [ "\$2" = "create-deployment" ]; then echo "d-NEW"; else echo "Succeeded"; fi
LOG
  printf '#!/usr/bin/env bash\nexit 0\n' > "${bin}/sleep"
  chmod +x "${bin}/aws" "${bin}/sleep"
  echo "${bin}"
}

@test "require_positive_integer accepts positive integers" {
  run require_positive_integer monitor-timeout-minutes 1
  [ "$status" -eq 0 ]
  run require_positive_integer monitor-timeout-minutes 30
  [ "$status" -eq 0 ]
}

@test "require_positive_integer rejects empty, zero, negative, decimal, padded and non-numeric values" {
  local value
  for value in '' 0 -5 1.5 ' 30' 030 abc; do
    run require_positive_integer monitor-timeout-minutes "${value}"
    [ "$status" -eq 1 ]
    [[ "$output" == *"::error::monitor-timeout-minutes must be a positive integer, got '${value}'"* ]]
  done
}

@test "main fails before creating a deployment when monitor-timeout-minutes is empty" {
  local bin
  bin=$(make_logging_aws)
  run env PATH="${bin}:${PATH}" MONITOR_TIMEOUT_MINUTES='' bash "${BATS_TEST_DIRNAME}/../deploy/deploy.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::monitor-timeout-minutes must be a positive integer, got ''"* ]]
  [ ! -e "${BATS_TEST_TMPDIR}/aws.log" ]
}

@test "main fails before creating a deployment when monitor-timeout-minutes is not a number" {
  local bin
  bin=$(make_logging_aws)
  run env PATH="${bin}:${PATH}" MONITOR_TIMEOUT_MINUTES='thirty' bash "${BATS_TEST_DIRNAME}/../deploy/deploy.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be a positive integer, got 'thirty'"* ]]
  [ ! -e "${BATS_TEST_TMPDIR}/aws.log" ]
}

@test "main fails before creating a deployment when POLL_INTERVAL is zero" {
  local bin
  bin=$(make_logging_aws)
  run env PATH="${bin}:${PATH}" POLL_INTERVAL=0 bash "${BATS_TEST_DIRNAME}/../deploy/deploy.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::POLL_INTERVAL must be a positive integer, got '0'"* ]]
  [ ! -e "${BATS_TEST_TMPDIR}/aws.log" ]
}

@test "main polls for the whole window when the interval does not divide it evenly" {
  local bin
  bin=$(make_fake_bin "d-SLOW" "InProgress")
  run env PATH="${bin}:${PATH}" MONITOR_TIMEOUT_MINUTES=1 POLL_INTERVAL=7 \
    bash "${BATS_TEST_DIRNAME}/../deploy/deploy.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Deployment status=InProgress... (9/9)"* ]]
}
