#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../_lib/python_venv_cache_key.sh"
  WORK="$(mktemp -d)"
  export GITHUB_OUTPUT="${WORK}/github_output"
  export HOME="${WORK}/home"
  export RUNNER_OS=Linux ImageOS=ubuntu24 ImageVersion=20261110.1 RUNNER_ARCH=X64
  export PYTHON_VERSION=3.13.9 DEPENDENCY_HASH=0123abcd
  touch "${GITHUB_OUTPUT}"
}

teardown() {
  rm -rf "${WORK}"
}

key() {
  : > "${GITHUB_OUTPUT}"
  bash "${SCRIPT}"
  sed -n 's/^key=//p' "${GITHUB_OUTPUT}"
}

@test "writes the virtualenv directory under HOME and a key naming the image, Python version and dependency hash" {
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "${GITHUB_OUTPUT}")" = "dir=${HOME}/.cache/ci-actions/python-venv" ]
  [ "$(sed -n 2p "${GITHUB_OUTPUT}")" = 'key=python-venv-Linux-ubuntu24-20261110.1-X64-3.13.9-0123abcd' ]
}

@test "keys a different Python patch version differently" {
  first="$(key)"
  PYTHON_VERSION=3.13.10
  [ "${first}" != "$(key)" ]
}

@test "keys a different dependency hash differently" {
  first="$(key)"
  DEPENDENCY_HASH=ffff0000
  [ "${first}" != "$(key)" ]
}

@test "keys a different runner image differently" {
  first="$(key)"
  ImageVersion=20261117.1
  [ "${first}" != "$(key)" ]
}

@test "keys a different architecture differently" {
  first="$(key)"
  RUNNER_ARCH=ARM64
  [ "${first}" != "$(key)" ]
}

@test "accepts a PyPy version" {
  PYTHON_VERSION=pypy3.10-7.3.17
  [ "$(key)" = 'python-venv-Linux-ubuntu24-20261110.1-X64-pypy3.10-7.3.17-0123abcd' ]
}

@test "keys a repository without dependency files as none" {
  DEPENDENCY_HASH=''
  [ "$(key)" = 'python-venv-Linux-ubuntu24-20261110.1-X64-3.13.9-none' ]
}

@test "fails without a Python version" {
  PYTHON_VERSION='' run bash "${SCRIPT}"
  [ "$status" -ne 0 ]
  [ ! -s "${GITHUB_OUTPUT}" ]
}

@test "fails on a Python version that could break the key" {
  PYTHON_VERSION='3.13 x' run bash "${SCRIPT}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::unexpected Python version '3.13 x'"* ]]
  [ ! -s "${GITHUB_OUTPUT}" ]
}

@test "fails on a dependency hash that is not hex" {
  DEPENDENCY_HASH='abc
evil=1' run bash "${SCRIPT}"
  [ "$status" -eq 1 ]
  [ ! -s "${GITHUB_OUTPUT}" ]
}
