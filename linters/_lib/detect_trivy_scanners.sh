#!/usr/bin/env bash

# Writes scanners=<list> for the workspace in the current directory to GITHUB_OUTPUT.
#
# Usage (from linters/trivy/action.yml):
#   run: bash "${GITHUB_ACTION_PATH}/../_lib/detect_trivy_scanners.sh"

set -eo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/lock_files.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/submodule_paths.sh"

scanners="secret"

prune_args=()
while IFS= read -r path; do
  if [ -n "${path}" ]; then
    prune_args+=("-path" "./${path}" "-prune" "-o")
  fi
done < <(submodule_paths)

if echo "${LINTERS}" | grep -qE "CFNLINT|HADOLINT" || \
   find . "${prune_args[@]}" '(' -name "*.tf" -o -name "Dockerfile*" ')' -print -quit 2>/dev/null | grep -q .; then
  scanners="${scanners},misconfig"
fi

for lock_file in "${TRIVY_LOCK_FILES[@]}"; do
  if find . "${prune_args[@]}" -name "${lock_file}" -print -quit 2>/dev/null | grep -q .; then
    scanners="${scanners},vuln"
    break
  fi
done

echo "scanners=${scanners}" >> "${GITHUB_OUTPUT}"
echo "Trivy scanners: ${scanners}"
