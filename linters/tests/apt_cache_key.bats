#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../_lib/apt_cache_key.sh"
  WORK="$(mktemp -d)"
  export GITHUB_OUTPUT="${WORK}/github_output"
  export HOME="${WORK}/home"
  export ImageOS=ubuntu24 ImageVersion=20261110.1 RUNNER_ARCH=X64
  touch "${GITHUB_OUTPUT}"
}

teardown() {
  rm -rf "${WORK}"
}

key_for() {
  : > "${GITHUB_OUTPUT}"
  APT_PACKAGES="$1" bash "${SCRIPT}"
  sed -n 's/^key=//p' "${GITHUB_OUTPUT}"
}

@test "writes the cache directory under HOME and a key naming the runner image and architecture" {
  APT_PACKAGES='graphviz jq' run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "${GITHUB_OUTPUT}")" = "dir=${HOME}/.cache/ci-actions/apt" ]
  [[ "$(sed -n 2p "${GITHUB_OUTPUT}")" =~ ^key=apt-v3-ubuntu24-20261110\.1-X64-[0-9a-f]{16}$ ]]
}

@test "keys the same package list identically whatever its order, spacing or duplicates" {
  [ "$(key_for 'graphviz jq')" = "$(key_for '  jq
graphviz   jq ')" ]
}

@test "keys a different package list differently" {
  [ "$(key_for 'graphviz jq')" != "$(key_for 'graphviz')" ]
}

@test "keys a different runner image differently" {
  first="$(key_for 'graphviz')"
  ImageVersion=20261117.1
  [ "${first}" != "$(key_for 'graphviz')" ]
}

@test "uses placeholders when the runner image variables are missing" {
  run env -u ImageOS -u ImageVersion -u RUNNER_ARCH APT_PACKAGES=graphviz bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$(sed -n 2p "${GITHUB_OUTPUT}")" == key=apt-v3-unknown-unknown-unknown-* ]]
}

@test "fails when APT_PACKAGES is not set" {
  run env -u APT_PACKAGES bash "${SCRIPT}"
  [ "$status" -ne 0 ]
  [ ! -s "${GITHUB_OUTPUT}" ]
}
