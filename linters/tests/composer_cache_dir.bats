#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../_lib/composer_cache_dir.sh"
  BIN="$(mktemp -d)"
  export GITHUB_OUTPUT="${BIN}/github_output"
  touch "${GITHUB_OUTPUT}"
}

teardown() {
  rm -rf "${BIN}"
}

fake_composer() {
  printf '#!/usr/bin/env bash\n%s\n' "$1" > "${BIN}/composer"
  chmod +x "${BIN}/composer"
}

@test "writes the Composer cache directory to GITHUB_OUTPUT" {
  fake_composer 'echo /home/runner/.cache/composer/files'
  run env PATH="${BIN}:${PATH}" bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ "$(cat "${GITHUB_OUTPUT}")" = 'dir=/home/runner/.cache/composer/files' ]
}

@test "asks composer for cache-files-dir" {
  # shellcheck disable=SC2016 # expanded by the fake composer, not here
  fake_composer 'echo "$*" > "$(dirname "$0")/args"; echo /tmp/cache'
  run env PATH="${BIN}:${PATH}" bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ "$(cat "${BIN}/args")" = 'config cache-files-dir' ]
}

@test "fails with an error when composer exits non-zero" {
  fake_composer 'exit 1'
  run env PATH="${BIN}:${PATH}" bash "${SCRIPT}"
  [ "$status" -eq 1 ]
  [[ "$output" == *'::error::composer is not available - cannot resolve the Composer cache directory'* ]]
  [ ! -s "${GITHUB_OUTPUT}" ]
}

@test "fails with an error when composer is not installed" {
  run env PATH="${BIN}" "${BASH}" "${SCRIPT}"
  [ "$status" -eq 1 ]
  [[ "$output" == *'::error::composer is not available'* ]]
  [ ! -s "${GITHUB_OUTPUT}" ]
}

@test "fails with an error when composer returns an empty directory" {
  fake_composer 'echo'
  run env PATH="${BIN}:${PATH}" bash "${SCRIPT}"
  [ "$status" -eq 1 ]
  [[ "$output" == *'::error::composer config cache-files-dir returned empty'* ]]
  [ ! -s "${GITHUB_OUTPUT}" ]
}
