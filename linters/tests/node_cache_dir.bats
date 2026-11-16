#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../_lib/node_cache_dir.sh"
  BIN="$(mktemp -d)"
  REPO="${BIN}/repo"
  mkdir -p "${REPO}"
  export GITHUB_OUTPUT="${BIN}/github_output"
  touch "${GITHUB_OUTPUT}"
  cd "${REPO}" || return 1
}

teardown() {
  rm -rf "${BIN}"
}

fake() {
  printf '#!/usr/bin/env bash\necho "$PWD|$*" >> "%s/calls"\n%s\n' "${BIN}" "$2" > "${BIN}/$1"
  chmod +x "${BIN}/$1"
}

run_script() {
  run env PATH="${BIN}:${PATH}" "$@" bash "${SCRIPT}"
}

@test "npm: writes the npm cache directory" {
  fake npm 'echo /home/runner/.npm'
  run_script NODE_CACHE=npm
  [ "$status" -eq 0 ]
  [ "$(cat "${GITHUB_OUTPUT}")" = 'dir=/home/runner/.npm' ]
  [ "$(cat "${BIN}/calls")" = "${REPO}|config get cache" ]
}

@test "pnpm: writes the pnpm store directory" {
  fake pnpm 'echo /home/runner/.local/share/pnpm/store/v10'
  run_script NODE_CACHE=pnpm
  [ "$status" -eq 0 ]
  [ "$(cat "${GITHUB_OUTPUT}")" = 'dir=/home/runner/.local/share/pnpm/store/v10' ]
  [ "$(cat "${BIN}/calls")" = "${REPO}|store path --silent" ]
}

@test "yarn 1: writes the yarn cache dir" {
  # shellcheck disable=SC2016 # expanded by the fake yarn, not here
  fake yarn 'case "$1" in --version) echo 1.22.22 ;; cache) echo /home/runner/.cache/yarn/v6 ;; esac'
  run_script NODE_CACHE=yarn
  [ "$status" -eq 0 ]
  [ "$(cat "${GITHUB_OUTPUT}")" = 'dir=/home/runner/.cache/yarn/v6' ]
  [ "$(sed -n 2p "${BIN}/calls")" = "${REPO}|cache dir" ]
}

@test "yarn 2+: writes the yarn cacheFolder" {
  # shellcheck disable=SC2016 # expanded by the fake yarn, not here
  fake yarn 'case "$1" in --version) echo 4.5.0 ;; config) echo /home/runner/.yarn/berry/cache ;; esac'
  run_script NODE_CACHE=yarn
  [ "$status" -eq 0 ]
  [ "$(cat "${GITHUB_OUTPUT}")" = 'dir=/home/runner/.yarn/berry/cache' ]
  [ "$(sed -n 2p "${BIN}/calls")" = "${REPO}|config get cacheFolder" ]
}

@test "yarn 2+: writes nothing when the project commits its .yarn/cache" {
  fake yarn 'echo 4.5.0'
  mkdir -p .yarn/cache
  run_script NODE_CACHE=yarn
  [ "$status" -eq 0 ]
  [ ! -s "${GITHUB_OUTPUT}" ]
  [[ "$output" == *'not caching it'* ]]
}

@test "resolves the cache in the directory of the first dependency file" {
  mkdir -p web
  touch web/package-lock.json package-lock.json
  fake npm 'echo /home/runner/.npm'
  run_script NODE_CACHE=npm NODE_CACHE_DEPENDENCY_PATH='
  web/package-lock.json
package-lock.json'
  [ "$status" -eq 0 ]
  [ "$(cat "${BIN}/calls")" = "${REPO}/web|config get cache" ]
}

@test "resolves the cache in the current directory when the dependency path is a glob" {
  fake npm 'echo /home/runner/.npm'
  run_script NODE_CACHE=npm NODE_CACHE_DEPENDENCY_PATH='**/package-lock.json'
  [ "$status" -eq 0 ]
  [ "$(cat "${BIN}/calls")" = "${REPO}|config get cache" ]
}

@test "fails on an unsupported package manager" {
  run_script NODE_CACHE=bun
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::node-cache 'bun' is not supported - use npm, yarn or pnpm"* ]]
  [ ! -s "${GITHUB_OUTPUT}" ]
}

@test "fails with an error when the package manager exits non-zero" {
  fake pnpm 'exit 1'
  run_script NODE_CACHE=pnpm
  [ "$status" -eq 1 ]
  [[ "$output" == *'::error::pnpm is not available'* ]]
  [ ! -s "${GITHUB_OUTPUT}" ]
}

@test "fails with an error when the package manager returns an empty directory" {
  fake npm 'echo'
  run_script NODE_CACHE=npm
  [ "$status" -eq 1 ]
  [[ "$output" == *'::error::npm returned an empty cache directory'* ]]
  [ ! -s "${GITHUB_OUTPUT}" ]
}

@test "fails when the package manager returns a relative directory" {
  fake npm 'echo relative/cache'
  run_script NODE_CACHE=npm
  [ "$status" -eq 1 ]
  [[ "$output" == *'::error::npm returned a cache directory that is not a single absolute path'* ]]
  [ ! -s "${GITHUB_OUTPUT}" ]
}

@test "fails when the package manager returns a directory with a newline" {
  fake npm 'printf "/home/runner/.npm\\nevil=1\\n"'
  run_script NODE_CACHE=npm
  [ "$status" -eq 1 ]
  [ ! -s "${GITHUB_OUTPUT}" ]
}

@test "fails when NODE_CACHE is not set" {
  run env -u NODE_CACHE bash "${SCRIPT}"
  [ "$status" -ne 0 ]
  [ ! -s "${GITHUB_OUTPUT}" ]
}
