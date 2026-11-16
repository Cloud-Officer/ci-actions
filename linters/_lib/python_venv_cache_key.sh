#!/usr/bin/env bash

# Writes dir=<virtualenv directory> and key=<cache key> to GITHUB_OUTPUT for the actions/cache step that follows.
# The key changes with the runner image, the exact Python version and the hash of the dependency files.
#
# Usage (from a composite action step with `id: python-venv-key`):
#   env:
#     PYTHON_VERSION: ${{ steps.setup-python.outputs.python-version }}
#     DEPENDENCY_HASH: ${{ hashFiles(...) }}
#   run: bash "${GITHUB_ACTION_PATH}/../linters/_lib/python_venv_cache_key.sh"

set -euo pipefail

: "${PYTHON_VERSION:?PYTHON_VERSION must be set}"

[[ "${PYTHON_VERSION}" =~ ^[A-Za-z0-9._+-]+$ ]] || { echo "::error::unexpected Python version '${PYTHON_VERSION}'"; exit 1; }
[[ "${DEPENDENCY_HASH:-}" =~ ^[0-9a-f]*$ ]] || { echo "::error::DEPENDENCY_HASH must be a hex digest"; exit 1; }

{
  echo "dir=${HOME}/.cache/ci-actions/python-venv"
  echo "key=python-venv-${RUNNER_OS:-unknown}-${ImageOS:-unknown}-${ImageVersion:-unknown}-${RUNNER_ARCH:-unknown}-${PYTHON_VERSION}-${DEPENDENCY_HASH:-none}"
} >> "${GITHUB_OUTPUT}"
