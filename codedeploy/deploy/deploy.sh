#!/usr/bin/env bash

# CodeDeploy deployment driver, extracted from action.yml so the failure /
# timeout / transient-error classification can be exercised by the bats suite
# (a regression that swallowed a Failed status would otherwise produce a
# false-green deployment with nothing to catch it). The functions below are
# sourced by tests/deploy.bats; main() only runs when invoked directly.

# Seconds between get-deployment polls. Overridable so the test suite can keep
# the loop fast; defaults to the original hard-coded interval.
POLL_INTERVAL="${POLL_INTERVAL:-5}"

# Create the CodeDeploy deployment and echo its id. Kept as a function so the
# test suite can stub `aws` and assert the create arguments.
function create_deployment()
{
  aws deploy create-deployment \
    --application-name "${APPLICATION_NAME}" \
    --deployment-config-name "${DEPLOYMENT_STRATEGY}" \
    --deployment-group-name "${DEPLOYMENT_GROUP_NAME}" \
    --description "Deploy build ${GITHUB_RUN_NUMBER} via Github Actions" \
    --s3-location "bucket=${S3_BUCKET},bundleType=zip,key=${S3_KEY}" \
    --query 'deploymentId' --output text
}

# Poll a deployment to a terminal state.
# Usage: poll_deployment <deployment-id> <max-iterations>
# Returns: 0 = Succeeded, 1 = Failed/Stopped, 2 = timed out before terminal.
function poll_deployment()
{
  local deployment="$1"
  local max_iterations="$2"
  local counter status

  for (( counter = 1; counter <= max_iterations; counter++ )); do
    # Tolerate transient CodeDeploy API errors so a single blip does not
    # abort monitoring of an otherwise healthy deployment.
    status=$(aws deploy get-deployment --deployment-id "${deployment}" --query 'deploymentInfo.status' --output text 2>/dev/null || echo "Unknown")

    case ${status} in
      Succeeded)
      echo "Deployment succeeded"
      return 0
      ;;

      Failed|Stopped)
      # Fail the step so downstream jobs and notifications see the failure.
      echo "::error::CodeDeploy deployment ${status} (id=${deployment})"
      return 1
      ;;

      *)
      # Anything else (Created, Queued, InProgress, Ready, Baking, ...) is
      # non-terminal. "Ready" in blue/green still has BlockTraffic /
      # AllowTraffic / TerminateBlueInstances phases that can fail, so we
      # keep polling until a true terminal state is observed.
      echo "Deployment status=${status}... (${counter}/${max_iterations})"
      sleep "${POLL_INTERVAL}"
      ;;
    esac
  done

  # Timeout is a real failure signal: the deployment never reached a
  # terminal state within the monitoring window. Surface it instead of
  # reporting a green build for an in-flight or failed deployment.
  echo "::error::Deployment ${deployment} did not reach a terminal state within ${MONITOR_TIMEOUT_MINUTES} minutes. Check the AWS CodeDeploy console."
  return 2
}

# Create the deployment then monitor it to a terminal state. Wrapped in a
# function so the test suite can source this file for its helpers without
# launching a deployment.
function main()
{
  # Fail fast on any command error, unset variable, or failed pipe so a
  # broken create-deployment or environment surfaces instead of silently
  # proceeding. Scoped to main so sourcing this file for the test suite does
  # not change the caller's shell options.
  set -euo pipefail

  local deployment max_iterations exit_code

  deployment=$(create_deployment)
  echo "Deployment ID=${deployment}"

  max_iterations=$(( MONITOR_TIMEOUT_MINUTES * 60 / POLL_INTERVAL ))

  # Map terminal/timeout to a non-zero step exit; both 1 and 2 are failures.
  exit_code=0
  poll_deployment "${deployment}" "${max_iterations}" || exit_code=$?
  if [ "${exit_code}" -ne 0 ]; then
    exit 1
  fi
}

# Only run main when executed directly (via the action's bash invocation),
# not when sourced by the bats test suite.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
