#!/usr/bin/env bash

# Writes continue=true|false to GITHUB_OUTPUT: whether LINTER_NAME is in the space-separated LINTERS list.
#
# Usage (from a composite action step):
#   run: bash "${GITHUB_ACTION_PATH}/../_lib/check_enabled.sh" LINTER_NAME

set -euo pipefail

linter_name="${1:?usage: check_enabled.sh LINTER_NAME}"

if echo "${LINTERS:-}" | grep -qwF -- "${linter_name}"; then
  echo "continue=true" >> "${GITHUB_OUTPUT}"
else
  echo "continue=false" >> "${GITHUB_OUTPUT}"
fi
