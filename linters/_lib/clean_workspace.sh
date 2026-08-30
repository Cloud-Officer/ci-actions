#!/usr/bin/env bash

# Shared workspace cleanup for the linters that lint the whole checkout rather
# than a language-specific subset (markdownlint, yamllint). Both actions check
# out with `submodules: recursive`, so third-party code lands in the workspace
# and would otherwise be reported as this repository's lint findings.
#
# Usage (from a composite action step):
#   run: bash "${GITHUB_ACTION_PATH}/../_lib/clean_workspace.sh" [DIR_NAME...]
#
# Always removes the submodule checkouts listed in .gitmodules (see the
# `scripts` exception below). Each optional DIR_NAME is additionally removed
# anywhere it appears in the tree (markdownlint passes vendor, node_modules and
# Libraries; yamllint passes nothing). Centralised here so the pipeline and its
# rationale live in one place instead of being duplicated per action.
#
# QUAL-006 (#262).

set -euo pipefail

# Delete every submodule checkout except the shared `scripts` submodule.
#
# The `scripts` exclusion is deliberate: github-build symlinks a consumer repo's
# linter config files (.markdownlint-cli2.yaml, .yamllint.yml, ...) to
# <scripts-submodule>/linters/<config> when that submodule provides them
# (GHB::LinterJobBuilder#copy_single_config). Deleting the submodule here would
# leave those root-level symlinks dangling and the linter would silently run
# with its default rules instead of the shared ones. The match is on the
# submodule path containing "scripts", mirroring the generator's own detection.
function remove_submodules()
{
  [[ -f .gitmodules ]] || return 0

  local -a paths=()
  local path

  # Parse with `git config` rather than grep/awk. The old `grep path .gitmodules`
  # was unanchored, so any line merely containing the word "path" -- a url such as
  # https://example.com/path-in-url.git -- was treated as a submodule entry. The
  # keyed lookup below matches only real `submodule.<name>.path` values.
  while IFS= read -r path; do
    [[ -n "${path}" ]] || continue
    [[ "${path}" == *scripts* ]] && continue

    # Reject anything that could escape the workspace before it reaches `rm -rf`.
    # .gitmodules is attacker-controlled content on a fork PR, and a `path = /`
    # or `path = ../../_temp` entry would otherwise delete outside the checkout.
    case "${path}" in
      /* | *..*)
        echo "::warning::skipping out-of-workspace submodule path '${path}'"
        continue
        ;;
    esac

    paths+=("${path}")
  done < <(git config --file .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | cut -d' ' -f2-)

  if [[ ${#paths[@]} -gt 0 ]]; then
    rm -rf -- "${paths[@]}"
  fi
}

# Delete every directory named after one of the given names.
#
# -prune stops find from descending into a directory it is about to delete;
# without it the old `-exec rm -rf {} \;` form always ended with find failing on
# the entries it had just removed ("No such file or directory"), which is why
# the callers needed a `|| true` that also masked genuine rm failures.
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
