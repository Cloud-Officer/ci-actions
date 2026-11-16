#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../_lib/python_venv_activate.sh"
  WORK="$(mktemp -d)"
  export GITHUB_ENV="${WORK}/github_env" GITHUB_PATH="${WORK}/github_path"
  export VENV_DIR="${WORK}/venv"
  PYTHON="$(command -v python3)"
  export PYTHON
  touch "${GITHUB_ENV}" "${GITHUB_PATH}"
}

teardown() {
  rm -rf "${WORK}"
}

@test "creates a virtualenv and activates it for later steps" {
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Created a virtualenv in ${VENV_DIR}"* ]]
  [ "$("${VENV_DIR}/bin/python" -c 'import sys; print(sys.prefix != sys.base_prefix)')" = True ]
  [ "$(cat "${GITHUB_ENV}")" = "VIRTUAL_ENV=${VENV_DIR}" ]
  [ "$(cat "${GITHUB_PATH}")" = "${VENV_DIR}/bin" ]
}

@test "reuses a restored virtualenv and keeps what it holds" {
  "${PYTHON}" -m venv "${VENV_DIR}"
  touch "${VENV_DIR}/restored"
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Reusing the virtualenv in ${VENV_DIR}"* ]]
  [ -f "${VENV_DIR}/restored" ]
  [ "$(cat "${GITHUB_PATH}")" = "${VENV_DIR}/bin" ]
}

@test "recreates a restored virtualenv whose interpreter no longer runs" {
  mkdir -p "${VENV_DIR}/bin"
  printf '#!/bin/sh\nexit 1\n' > "${VENV_DIR}/bin/python"
  chmod +x "${VENV_DIR}/bin/python"
  touch "${VENV_DIR}/stale"
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Created a virtualenv in ${VENV_DIR}"* ]]
  [ ! -e "${VENV_DIR}/stale" ]
  "${VENV_DIR}/bin/python" -c ''
}

@test "fails with an error when the interpreter cannot create a virtualenv" {
  PYTHON=/bin/false run bash "${SCRIPT}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::/bin/false could not create a virtualenv in ${VENV_DIR}"* ]]
  [ ! -s "${GITHUB_ENV}" ]
  [ ! -s "${GITHUB_PATH}" ]
}

@test "fails when VENV_DIR is not set" {
  run env -u VENV_DIR bash "${SCRIPT}"
  [ "$status" -ne 0 ]
  [ ! -s "${GITHUB_PATH}" ]
}

@test "fails when PYTHON is not set" {
  run env -u PYTHON bash "${SCRIPT}"
  [ "$status" -ne 0 ]
  [ ! -s "${GITHUB_PATH}" ]
}
