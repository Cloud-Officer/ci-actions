#!/usr/bin/env bash

# Removes submodule checkouts (except `scripts`) and every directory named DIR_NAME before a whole-checkout lint.
#
# Usage (from a composite action step):
#   run: bash "${GITHUB_ACTION_PATH}/../_lib/clean_workspace.sh" [DIR_NAME...]

set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/submodule_paths.sh"

# github-build symlinks the root linter configs into the `scripts` submodule, so it must survive.
function remove_submodules()
{
  [[ -f .gitmodules ]] || return 0

  local -a paths=()
  local path

  while IFS= read -r path; do
    [[ -n "${path}" ]] || continue
    [[ "${path}" == *scripts* ]] && continue

    # .gitmodules is attacker-controlled on a fork PR.
    case "${path}" in
      /* | *..*)
        echo "::warning::skipping out-of-workspace submodule path '${path}'"
        continue
        ;;
    esac

    paths+=("${path}")
  done < <(submodule_paths)

  if [[ ${#paths[@]} -gt 0 ]]; then
    rm -rf -- "${paths[@]}"
  fi
}

function remove_directories()
{
  local name

  for name in "$@"; do
    find . -type d -name "${name}" -prune -exec rm -rf {} +
  done
}

function main()
{
  remove_submodules
  remove_directories "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
