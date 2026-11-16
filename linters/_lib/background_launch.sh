#!/usr/bin/env bash

# Runs a command detached from the current step so a later step can collect its output and exit status.

function launch_dir()
{
  echo "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/background-launch"
}

function launch_in_background()
{
  local name="$1" dir
  shift
  dir="$(launch_dir)"
  mkdir -p "${dir}"
  rm -f "${dir}/${name}.status" "${dir}/${name}.log"

  # shellcheck disable=SC2016 # expanded by the detached shell, not this one.
  nohup bash -c 'log="$1" status="$2"; shift 2; "$@" > "${log}" 2>&1; echo "$?" > "${status}.tmp" && mv "${status}.tmp" "${status}"' \
    bash "${dir}/${name}.log" "${dir}/${name}.status" "$@" < /dev/null > /dev/null 2>&1 &
}

function wait_for_launch()
{
  local name="$1" timeout="$2" dir waited=0 status
  dir="$(launch_dir)"

  until [[ -f "${dir}/${name}.status" ]]; do
    if ((waited >= timeout)); then
      echo "::error::${name} did not finish launching within ${timeout} seconds"
      cat "${dir}/${name}.log" 2> /dev/null || true
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done

  status="$(cat "${dir}/${name}.status")"
  [[ "${status}" =~ ^[0-9]+$ ]] || status=1
  cat "${dir}/${name}.log"
  if ((status != 0)); then
    echo "::error::${name} failed to launch (exit ${status})"
  fi
  return "${status}"
}
