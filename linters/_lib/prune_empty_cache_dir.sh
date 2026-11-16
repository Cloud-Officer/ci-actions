#!/usr/bin/env bash

# Removes CACHE_DIR when it holds no files, so the post-job actions/cache save skips it instead of storing an empty
# archive under a key that later jobs would then hit and never refresh.
#
# Usage (from a composite action step, after a cache miss):
#   env:
#     CACHE_DIR: ${{ steps.node-cache-dir.outputs.dir }}
#   run: bash "${GITHUB_ACTION_PATH}/../linters/_lib/prune_empty_cache_dir.sh"

set -euo pipefail

: "${CACHE_DIR:?CACHE_DIR must be set}"

if [ -d "${CACHE_DIR}" ] && [ -z "$(find "${CACHE_DIR}" -type f -print -quit)" ]; then
  rm -rf "${CACHE_DIR}"
  echo "Removed empty cache directory ${CACHE_DIR}"
fi
