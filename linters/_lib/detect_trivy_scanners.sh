#!/usr/bin/env bash

# Writes scanners=<list> for the workspace in the current directory to GITHUB_OUTPUT.
#
# Usage (from linters/trivy/action.yml):
#   run: bash "${GITHUB_ACTION_PATH}/../_lib/detect_trivy_scanners.sh"

set -eo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/lock_files.sh"

scanners="secret"

submodule_paths=()
if [ -f .gitmodules ]; then
  while IFS= read -r line; do
    submodule_paths+=("-path" "./${line}" "-prune" "-o")
  done < <(grep 'path = ' .gitmodules | sed 's/.*path = //')
fi

if echo "${LINTERS}" | grep -qE "CFNLINT|HADOLINT" || \
   find . "${submodule_paths[@]}" '(' -name "*.tf" -o -name "Dockerfile*" ')' -print -quit 2>/dev/null | grep -q .; then
  scanners="${scanners},misconfig"
fi

for lock_file in "${TRIVY_LOCK_FILES[@]}"; do
  if find . "${submodule_paths[@]}" -name "${lock_file}" -print -quit 2>/dev/null | grep -q .; then
    scanners="${scanners},vuln"
    break
  fi
done

echo "scanners=${scanners}" >> "${GITHUB_OUTPUT}"
echo "Trivy scanners: ${scanners}"
