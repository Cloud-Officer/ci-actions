#!/usr/bin/env bash

# Writes dir=<package manager cache directory> to GITHUB_OUTPUT for the actions/cache step that follows, resolved the
# way actions/setup-node does for NODE_CACHE (npm, yarn or pnpm). Writes nothing for a Yarn 2+ project that commits
# its .yarn/cache, since the repository already carries the packages.
#
# Usage (from a composite action step with `id: node-cache-dir`):
#   env:
#     NODE_CACHE: ${{ inputs.node-cache }}
#     NODE_CACHE_DEPENDENCY_PATH: ${{ inputs.node-cache-dependency-path }}   # optional
#   run: bash "${GITHUB_ACTION_PATH}/../linters/_lib/node_cache_dir.sh"

set -euo pipefail

: "${NODE_CACHE?NODE_CACHE must be set}"

project_dir="."
first_path="$(printf '%s\n' "${NODE_CACHE_DEPENDENCY_PATH:-}" | sed -n '/[^[:space:]]/{s/^[[:space:]]*//;s/[[:space:]]*$//;p;q;}')"

if [ -n "${first_path}" ] && [ -f "${first_path}" ]; then
  project_dir="$(dirname "${first_path}")"
fi

cd "${project_dir}"

case "${NODE_CACHE}" in
  npm)
    dir="$(npm config get cache)" || { echo "::error::npm is not available - cannot resolve the npm cache directory"; exit 1; }
    ;;
  pnpm)
    dir="$(pnpm store path --silent)" || { echo "::error::pnpm is not available - cannot resolve the pnpm store directory"; exit 1; }
    ;;
  yarn)
    version="$(yarn --version)" || { echo "::error::yarn is not available - cannot resolve the Yarn cache directory"; exit 1; }

    if [[ "${version}" == 1.* ]]; then
      dir="$(yarn cache dir)"
    elif [ -d .yarn/cache ]; then
      echo "Yarn ${version} cache is committed in ${project_dir}/.yarn/cache - not caching it"
      exit 0
    else
      dir="$(yarn config get cacheFolder)"
    fi
    ;;
  *)
    echo "::error::node-cache '${NODE_CACHE}' is not supported - use npm, yarn or pnpm"
    exit 1
    ;;
esac

[ -n "${dir}" ] || { echo "::error::${NODE_CACHE} returned an empty cache directory"; exit 1; }
[[ "${dir}" == /* && "${dir}" != *$'\n'* ]] || { echo "::error::${NODE_CACHE} returned a cache directory that is not a single absolute path"; exit 1; }
echo "dir=${dir}" >> "${GITHUB_OUTPUT}"
