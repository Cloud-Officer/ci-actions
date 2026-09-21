#!/usr/bin/env bash

# Runs shellcheck over every shell script in the workspace and reports the findings through reviewdog.
#
# Usage (from linters/shellcheck/action.yml, with shellcheck and reviewdog on PATH):
#   env:
#     REVIEWDOG_GITHUB_API_TOKEN: ${{ inputs.reviewdog-token }}
#   run: bash "${GITHUB_ACTION_PATH}/../_lib/run_shellcheck.sh"

SHELLCHECK_EXCLUDES=(
  -not -path './.git/*'
  -not -path './.vendor/*'
  -not -path './vendor/*'
  -not -path './node_modules/*'
  -not -path './Libraries/*'
  -not -path './Pods/*'
  -not -name '*.bats'
)

# Prints NUL-separated `*.sh` files plus any other file whose first line is a shell shebang.
function shellcheck_files()
{
  find . "${SHELLCHECK_EXCLUDES[@]}" -type f -name '*.sh' -print0
  find . "${SHELLCHECK_EXCLUDES[@]}" -type f -not -name '*.sh' -print0 \
    | xargs -0 -r awk 'FNR == 1 { if (/^#!.*sh/) printf "%s%c", FILENAME, 0; nextfile }'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -uo pipefail

  mapfile -d '' files < <(shellcheck_files)

  if [ "${#files[@]}" -eq 0 ]; then
    echo "No shell scripts found to check."
    exit 0
  fi

  shellcheck --version

  shellcheck -f json --external-sources "${files[@]}" \
    | jq -r '.[] | "\(.file):\(.line):\(.column):\(.level):\(.message) [SC\(.code)](https://github.com/koalaman/shellcheck/wiki/SC\(.code))"' \
    | reviewdog -efm="%f:%l:%c:%t%*[^:]:%m" -name="shellcheck" -reporter="github-pr-review" -filter-mode="nofilter" -fail-level="any" -level="info"
  findings=$?

  shellcheck -f diff --external-sources "${files[@]}" \
    | reviewdog -name="shellcheck (suggestion)" -f=diff -f.diff.strip=1 -reporter="github-pr-review" -filter-mode="nofilter" -fail-level="any"
  suggestions=$?

  [ "${findings}" -eq 0 ] && [ "${suggestions}" -eq 0 ]
fi
