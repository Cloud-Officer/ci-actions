#!/usr/bin/env bash

# Writes dir=<Composer cache-files-dir> to GITHUB_OUTPUT for the actions/cache step that follows.
#
# Usage (from a composite action step with `id: composer-cache`):
#   run: bash "${GITHUB_ACTION_PATH}/../_lib/composer_cache_dir.sh"

set -euo pipefail

dir="$(composer config cache-files-dir)" || { echo "::error::composer is not available - cannot resolve the Composer cache directory"; exit 1; }
[ -n "${dir}" ] || { echo "::error::composer config cache-files-dir returned empty"; exit 1; }
echo "dir=${dir}" >> "${GITHUB_OUTPUT}"
