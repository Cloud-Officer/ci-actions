#!/usr/bin/env bash

# Creates the virtualenv in VENV_DIR with PYTHON unless a working one was restored there, then activates it for the
# later steps of the job, so a plain `pip3 install` installs into it.
#
# Usage (from a composite action step, after the actions/cache restore):
#   env:
#     VENV_DIR: ${{ steps.python-venv-key.outputs.dir }}
#     PYTHON: ${{ steps.setup-python.outputs.python-path }}
#   run: bash "${GITHUB_ACTION_PATH}/../linters/_lib/python_venv_activate.sh"

set -euo pipefail

: "${VENV_DIR:?VENV_DIR must be set}"
: "${PYTHON:?PYTHON must be set}"

if [ -x "${VENV_DIR}/bin/python" ] && "${VENV_DIR}/bin/python" -c '' 2>/dev/null; then
  echo "Reusing the virtualenv in ${VENV_DIR}"
else
  rm -rf "${VENV_DIR}"
  "${PYTHON}" -m venv "${VENV_DIR}" || { echo "::error::${PYTHON} could not create a virtualenv in ${VENV_DIR}"; exit 1; }
  echo "Created a virtualenv in ${VENV_DIR}"
fi

echo "VIRTUAL_ENV=${VENV_DIR}" >> "${GITHUB_ENV}"
echo "${VENV_DIR}/bin" >> "${GITHUB_PATH}"
