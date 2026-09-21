#!/usr/bin/env bash

# Runs a command up to RETRY_ATTEMPTS times (default 3), backing off between attempts.
#
# Usage (from a composite action step):
#   run: bash "${GITHUB_ACTION_PATH}/../_lib/retry.sh" gem install --no-document rubocop

set -uo pipefail

attempts="${RETRY_ATTEMPTS:-3}"
delay="${RETRY_DELAY:-10}"

if [ "$#" -eq 0 ]; then
  echo "::error::usage: retry.sh COMMAND [ARGS...]" >&2
  exit 2
fi

for attempt in $(seq 1 "${attempts}"); do
  "$@"
  status=$?
  if [ "${status}" -eq 0 ]; then
    exit 0
  fi
  if [ "${attempt}" -lt "${attempts}" ]; then
    echo "::warning::'$*' failed with status ${status} (attempt ${attempt}/${attempts}); retrying in $(( attempt * delay ))s" >&2
    sleep $(( attempt * delay ))
  fi
done

echo "::error::'$*' failed after ${attempts} attempts" >&2
exit "${status}"
