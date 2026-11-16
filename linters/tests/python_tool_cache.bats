#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../_lib/python_tool_cache.sh"
  WORK="$(mktemp -d)"
  TOOLS="${WORK}/hostedtoolcache"
  mkdir -p "${TOOLS}/Python/3.12.10"
  touch "${TOOLS}/Python/3.12.10/x64.complete"
  export GITHUB_OUTPUT="${WORK}/github_output"
  touch "${GITHUB_OUTPUT}"
  cd "${WORK}" || return 1
}

teardown() {
  rm -rf "${WORK}"
}

run_script() {
  run env -u PYTHON_VERSION -u PYTHON_VERSION_FILE -u PYTHON_ARCHITECTURE \
    RUNNER_OS=Linux RUNNER_ARCH=X64 RUNNER_TOOL_CACHE="${TOOLS}" ImageOS=ubuntu24 ImageVersion=20261110.1 \
    "$@" bash "${SCRIPT}"
}

@test "missing exact version from python-version: writes key and tool cache path" {
  run_script PYTHON_VERSION=3.13.13
  [ "$status" -eq 0 ]
  [ "$(cat "${GITHUB_OUTPUT}")" = "key=python-ubuntu24-20261110.1-x64-3.13.13
path<<PYTHON_TOOL_CACHE_EOF
${TOOLS}/Python/3.13.13
PYTHON_TOOL_CACHE_EOF" ]
}

@test "reads the version from python-version-file when python-version is none" {
  printf '# pinned\n3.11.9\n' > .python-version
  run_script PYTHON_VERSION=none PYTHON_VERSION_FILE=.python-version
  [ "$status" -eq 0 ]
  grep -qx 'key=python-ubuntu24-20261110.1-x64-3.11.9' "${GITHUB_OUTPUT}"
  grep -qx "${TOOLS}/Python/3.11.9" "${GITHUB_OUTPUT}"
}

@test "python-version wins over python-version-file" {
  echo 3.11.9 > .python-version
  run_script PYTHON_VERSION=3.10.17 PYTHON_VERSION_FILE=.python-version
  [ "$status" -eq 0 ]
  grep -qx 'key=python-ubuntu24-20261110.1-x64-3.10.17' "${GITHUB_OUTPUT}"
}

@test "reads the python entry of a .tool-versions file" {
  printf 'nodejs 24.1.0\npython 3.13.13\n' > .tool-versions
  run_script PYTHON_VERSION_FILE=.tool-versions
  [ "$status" -eq 0 ]
  grep -qx 'key=python-ubuntu24-20261110.1-x64-3.13.13' "${GITHUB_OUTPUT}"
}

@test "writes nothing when the version is already in the tool cache" {
  run_script PYTHON_VERSION=3.12.10
  [ "$status" -eq 0 ]
  [ ! -s "${GITHUB_OUTPUT}" ]
  [[ "$output" == *'Python 3.12.10 (x64) is already in the tool cache'* ]]
}

@test "caches only the missing versions of a multi-version input" {
  run_script PYTHON_VERSION='3.12.10
3.13.13
3.9.23'
  [ "$status" -eq 0 ]
  grep -qx 'key=python-ubuntu24-20261110.1-x64-3.13.13-3.9.23' "${GITHUB_OUTPUT}"
  grep -qx "${TOOLS}/Python/3.13.13" "${GITHUB_OUTPUT}"
  grep -qx "${TOOLS}/Python/3.9.23" "${GITHUB_OUTPUT}"
  ! grep -q '3.12.10' "${GITHUB_OUTPUT}"
}

@test "uses python-architecture over the runner architecture" {
  run_script PYTHON_VERSION=3.12.10 PYTHON_ARCHITECTURE=arm64
  [ "$status" -eq 0 ]
  grep -qx 'key=python-ubuntu24-20261110.1-arm64-3.12.10' "${GITHUB_OUTPUT}"
}

@test "lowercases the runner architecture" {
  run_script PYTHON_VERSION=3.13.13 RUNNER_ARCH=ARM64
  [ "$status" -eq 0 ]
  grep -qx 'key=python-ubuntu24-20261110.1-arm64-3.13.13' "${GITHUB_OUTPUT}"
}

@test "writes nothing for version ranges, PyPy and free-threaded builds" {
  run_script PYTHON_VERSION='3.13
3.x
>=3.11
pypy3.10
3.13.13t'
  [ "$status" -eq 0 ]
  [ ! -s "${GITHUB_OUTPUT}" ]
}

@test "writes nothing when the version file does not exist" {
  run_script PYTHON_VERSION_FILE=.python-version
  [ "$status" -eq 0 ]
  [ ! -s "${GITHUB_OUTPUT}" ]
}

@test "writes nothing on a non-Linux runner" {
  run_script PYTHON_VERSION=3.13.13 RUNNER_OS=macOS
  [ "$status" -eq 0 ]
  [ ! -s "${GITHUB_OUTPUT}" ]
}

@test "falls back to unknown image fields" {
  run_script PYTHON_VERSION=3.13.13 ImageOS= ImageVersion=
  [ "$status" -eq 0 ]
  grep -qx 'key=python-unknown-unknown-x64-3.13.13' "${GITHUB_OUTPUT}"
}

@test "fails when RUNNER_TOOL_CACHE is not set" {
  run env -u RUNNER_TOOL_CACHE RUNNER_OS=Linux PYTHON_VERSION=3.13.13 bash "${SCRIPT}"
  [ "$status" -ne 0 ]
  [ ! -s "${GITHUB_OUTPUT}" ]
}
