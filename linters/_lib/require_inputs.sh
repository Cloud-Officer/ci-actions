#!/usr/bin/env bash

# Shared "required inputs are actually present" gate.
#
# Usage (from a composite action step):
#   env:
#     SHELL_COMMANDS: ${{ inputs.shell-commands }}
#   run: bash "${GITHUB_ACTION_PATH}/../_lib/require_inputs.sh" \
#          "shell-commands=${SHELL_COMMANDS}"
#
# GitHub Actions does not enforce `required: true` for composite or local
# actions -- it is documentation only. An unset or misspelled secret reference
# such as ${{ secrets.MISNAMED }} interpolates to an empty string with no
# warning, so an action that hands that value to a nested interpreter runs
# nothing and still exits 0: a green build that did no work, and a Slack
# notification reporting success. This gate turns that into a loud failure.
#
# Values arrive as NAME=VALUE pairs so the error message can name every empty
# input at once rather than failing on the first. Pass them through `env:` and
# quote the expansion; never interpolate ${{ }} directly into the run: block.
#
# CFG-002.

set -euo pipefail

missing=()

for pair in "$@"; do
  name="${pair%%=*}"
  value="${pair#*=}"

  # Whitespace-only counts as empty: that is the shape a typo'd or unset
  # secret actually takes once the surrounding YAML is trimmed.
  if [[ -z "${value//[[:space:]]/}" ]]; then
    missing+=("${name}")
  fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "::error::required input(s) empty: ${missing[*]}"
  exit 1
fi
