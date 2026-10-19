#!/usr/bin/env bash

# Fails naming every NAME=VALUE pair whose value is blank; composite actions do not enforce `required: true`.
#
# Usage (from a composite action step):
#   env:
#     SHELL_COMMANDS: ${{ inputs.shell-commands }}
#   run: bash "${GITHUB_ACTION_PATH}/../_lib/require_inputs.sh" \
#          "shell-commands=${SHELL_COMMANDS}"

set -euo pipefail

missing=()

for pair in "$@"; do
  name="${pair%%=*}"
  value="${pair#*=}"

  if [[ -z "${value//[[:space:]]/}" ]]; then
    missing+=("${name}")
  fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "::error::required input(s) empty: ${missing[*]}"
  exit 1
fi
