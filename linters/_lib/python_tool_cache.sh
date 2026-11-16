#!/usr/bin/env bash

# Writes path=<tool cache directories> and key=<cache key> to GITHUB_OUTPUT for the actions/cache step that runs before
# actions/setup-python, so an exact CPython version the runner image does not ship is restored instead of downloaded.
# Writes nothing on a non-Linux runner, for version ranges, PyPy or free-threaded builds, or when every requested version
# is already in the tool cache.
#
# Usage (from a composite action step with `id: python-tool-cache`):
#   env:
#     PYTHON_VERSION: ${{ inputs.python-version }}            # 'none' or empty to read PYTHON_VERSION_FILE
#     PYTHON_VERSION_FILE: ${{ inputs.python-version-file }}
#     PYTHON_ARCHITECTURE: ${{ inputs.python-architecture }}  # optional, defaults to the runner architecture
#   run: bash "${GITHUB_ACTION_PATH}/../linters/_lib/python_tool_cache.sh"

set -euo pipefail

: "${RUNNER_TOOL_CACHE?RUNNER_TOOL_CACHE must be set}"

if [ "${RUNNER_OS:-}" != "Linux" ]; then
  echo "Python tool cache is only restored on Linux runners"
  exit 0
fi

requested="${PYTHON_VERSION:-}"

if [[ -z "${requested}" || "${requested}" == "none" ]]; then
  requested=""
  file="${PYTHON_VERSION_FILE:-}"

  if [ -n "${file}" ] && [ -f "${file}" ]; then
    if [[ "$(basename "${file}")" == ".tool-versions" ]]; then
      requested="$(awk '$1 == "python" { for (i = 2; i <= NF; i++) print $i }' "${file}")"
    else
      requested="$(cat "${file}")"
    fi
  fi
fi

arch="${PYTHON_ARCHITECTURE:-${RUNNER_ARCH:-x64}}"
arch="$(printf '%s' "${arch}" | tr '[:upper:]' '[:lower:]')"
missing=()

while IFS= read -r version; do
  version="$(printf '%s' "${version}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

  [[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue

  if [ -f "${RUNNER_TOOL_CACHE}/Python/${version}/${arch}.complete" ]; then
    echo "Python ${version} (${arch}) is already in the tool cache"
  else
    missing+=("${version}")
  fi
done < <(printf '%s\n' "${requested}" | LC_ALL=C sort -u)

if [ "${#missing[@]}" -eq 0 ]; then
  exit 0
fi

versions="$(IFS=-; echo "${missing[*]}")"

{
  echo "key=python-${ImageOS:-unknown}-${ImageVersion:-unknown}-${arch}-${versions}"
  echo "path<<PYTHON_TOOL_CACHE_EOF"
  for version in "${missing[@]}"; do
    echo "${RUNNER_TOOL_CACHE}/Python/${version}"
  done
  echo "PYTHON_TOOL_CACHE_EOF"
} >> "${GITHUB_OUTPUT}"
