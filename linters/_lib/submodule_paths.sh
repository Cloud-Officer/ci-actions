#!/usr/bin/env bash

# Prints each submodule path declared in ./.gitmodules, one per line, and nothing when there is none.
#
# Usage (sourced):
#   source "$(dirname "${BASH_SOURCE[0]}")/submodule_paths.sh"
#   while IFS= read -r path; do ...; done < <(submodule_paths)

function submodule_paths()
{
  [[ -f .gitmodules ]] || return 0

  local record
  while IFS= read -r -d '' record; do
    [[ "${record}" == *$'\n'* ]] || continue
    printf '%s\n' "${record#*$'\n'}"
  done < <(git config --file .gitmodules -z --get-regexp '^submodule\..*\.path$' 2>/dev/null)
}
