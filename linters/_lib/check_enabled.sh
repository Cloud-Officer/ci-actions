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

# -w (whole word) + -F (fixed string) so a linter name can only match a complete
# token in the space-separated list, never a substring of another. Without -wF a
# future linter whose name is a substring of another (or of a LINTERS token)
# would silently mis-enable.
if echo "${LINTERS:-}" | grep -qwF -- "${linter_name}"; then
  echo "continue=true" >> "${GITHUB_OUTPUT}"
else
  echo "continue=false" >> "${GITHUB_OUTPUT}"
fi
