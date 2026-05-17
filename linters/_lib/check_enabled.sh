#!/usr/bin/env bash

# Shared "is this linter enabled" gate for every linters/*/action.yml.
#
# Usage (from a composite action step):
#   run: bash "${GITHUB_ACTION_PATH}/../_lib/check_enabled.sh" LINTER_NAME
#
# Reads the space-separated LINTERS list from the environment and writes
# continue=true|false to GITHUB_OUTPUT so subsequent steps can gate on
# steps.check.outputs.continue. Centralised here so a change to the gating
# logic is one edit instead of 19.

set -euo pipefail

linter_name="${1:?usage: check_enabled.sh LINTER_NAME}"

if echo "${LINTERS:-}" | grep -- "${linter_name}" &> /dev/null; then
  echo "continue=true" >> "${GITHUB_OUTPUT}"
else
  echo "continue=false" >> "${GITHUB_OUTPUT}"
fi
