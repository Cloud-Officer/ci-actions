#!/usr/bin/env bash

POLL_INTERVAL="${POLL_INTERVAL:-15}"
ALLOWED_FLAGS=" --redeploy-latest --patch-standalone --sequential_rollout --skip_scale_down --preserve_desired_capacity "
LOG_NEXT_TOKEN=""

function validate_inputs()
{
  local flag
  local flags

  [[ "${DEPLOY_ENVIRONMENT:-}" =~ ^(beta|rc|prod)[0-9]+$ ]] || { echo "::error::environment '${DEPLOY_ENVIRONMENT:-}' must look like beta1, rc5 or prod3"; return 1; }
  [[ "${DEPLOY_INSTANCES:-}" =~ ^(api|grpc|worker|ml)(,(api|grpc|worker|ml))*$ ]] || { echo "::error::instances '${DEPLOY_INSTANCES:-}' must list api, grpc, worker or ml, comma-separated"; return 1; }
  [[ "${PROJECT_NAME:-}" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{1,254}$ ]] || { echo "::error::project-name '${PROJECT_NAME:-}' is not a CodeBuild project name"; return 1; }
  [[ "${MONITOR_TIMEOUT_MINUTES:-}" =~ ^[1-9][0-9]*$ ]] || { echo "::error::monitor-timeout-minutes must be a positive integer, got '${MONITOR_TIMEOUT_MINUTES:-}'"; return 1; }

  read -r -a flags <<<"${DEPLOY_FLAGS:-}"

  for flag in "${flags[@]}"; do
    [[ "${ALLOWED_FLAGS}" == *" ${flag} "* ]] || { echo "::error::flag ${flag} is not allowed (allowed:${ALLOWED_FLAGS})"; return 1; }
  done
}

function overrides()
{
  jq -cn --arg environment "${DEPLOY_ENVIRONMENT}" --arg instances "${DEPLOY_INSTANCES}" --arg flags "${DEPLOY_FLAGS:-}" \
    '[{name: "DEPLOY_ENVIRONMENT", value: $environment, type: "PLAINTEXT"}, {name: "DEPLOY_INSTANCES", value: $instances, type: "PLAINTEXT"}, {name: "DEPLOY_FLAGS", value: $flags, type: "PLAINTEXT"}]'
}

function start_build()
{
  aws codebuild start-build --project-name "${PROJECT_NAME}" --environment-variables-override "$(overrides)" --query 'build.id' --output text
}

function print_new_log_lines()
{
  local group="$1"
  local stream="$2"
  local page

  [ -n "${group}" ] && [ "${group}" != "None" ] && [ -n "${stream}" ] && [ "${stream}" != "None" ] || return 0

  if [ -n "${LOG_NEXT_TOKEN}" ]; then
    page=$(aws logs get-log-events --log-group-name "${group}" --log-stream-name "${stream}" --start-from-head --next-token "${LOG_NEXT_TOKEN}" --output json 2>/dev/null) || return 0
  else
    page=$(aws logs get-log-events --log-group-name "${group}" --log-stream-name "${stream}" --start-from-head --output json 2>/dev/null) || return 0
  fi

  jq -r '.events[].message' <<<"${page}" | sed -e 's/[[:space:]]*$//'
  LOG_NEXT_TOKEN=$(jq -r '.nextForwardToken // empty' <<<"${page}")
}

# Returns: 0 = SUCCEEDED, 1 = failed, stopped or timed out in CodeBuild, 2 = not finished within the monitoring window.
function follow_build()
{
  local build="$1"
  local max_iterations="$2"
  local counter info status group stream

  for (( counter = 1; counter <= max_iterations; counter++ )); do
    info=$(aws codebuild batch-get-builds --ids "${build}" --query 'builds[0].[buildStatus,logs.groupName,logs.streamName]' --output text 2>/dev/null || echo "UNKNOWN")
    read -r status group stream <<<"${info}"
    print_new_log_lines "${group:-}" "${stream:-}"

    case ${status} in
      SUCCEEDED)
        echo "deploy-runner build ${build} succeeded"
        return 0
        ;;
      FAILED|FAULT|STOPPED|TIMED_OUT)
        echo "::error::deploy-runner build ${build} ${status}: see the log above (exit 2 means the rollout was rolled back, 3 that someone must check the environment)"
        return 1
        ;;
      *)
        sleep "${POLL_INTERVAL}"
        ;;
    esac
  done

  echo "::error::deploy-runner build ${build} did not finish within ${MONITOR_TIMEOUT_MINUTES} minutes; it keeps running in CodeBuild"
  return 2
}

function main()
{
  set -euo pipefail

  local build max_iterations exit_code

  validate_inputs
  [[ "${POLL_INTERVAL}" =~ ^[1-9][0-9]*$ ]] || { echo "::error::POLL_INTERVAL must be a positive integer"; exit 1; }
  build=$(start_build)
  echo "deploy-runner build ${build} started for ${DEPLOY_ENVIRONMENT} (${DEPLOY_INSTANCES})"
  max_iterations=$(( (MONITOR_TIMEOUT_MINUTES * 60 + POLL_INTERVAL - 1) / POLL_INTERVAL ))
  exit_code=0
  follow_build "${build}" "${max_iterations}" || exit_code=$?
  [ "${exit_code}" -eq 0 ] || exit 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
