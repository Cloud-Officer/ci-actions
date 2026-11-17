#!/usr/bin/env bash

# Writes dir=<apt cache directory> and key=<cache key> to GITHUB_OUTPUT for the actions/cache step that follows.
# The key changes with the runner image and the sorted, de-duplicated APT_PACKAGES list.
#
# Usage (from a composite action step with `id: apt-cache-key`):
#   env:
#     APT_PACKAGES: ${{ inputs.apt-packages }}
#   run: bash "${GITHUB_ACTION_PATH}/../_lib/apt_cache_key.sh"

set -euo pipefail

: "${APT_PACKAGES?APT_PACKAGES must be set}"

# shellcheck disable=SC2086 # APT_PACKAGES is word-split on purpose: one input carries several packages.
hash="$(printf '%s\n' ${APT_PACKAGES} | LC_ALL=C sort -u | sha256sum | cut -c1-16)"

{
  echo "dir=${HOME}/.cache/ci-actions/apt"
  echo "key=apt-v4-${ImageOS:-unknown}-${ImageVersion:-unknown}-${RUNNER_ARCH:-unknown}-${hash}"
} >> "${GITHUB_OUTPUT}"
