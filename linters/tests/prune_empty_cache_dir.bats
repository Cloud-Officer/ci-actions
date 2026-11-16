#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../_lib/prune_empty_cache_dir.sh"
  WORK="$(mktemp -d)"
}

teardown() {
  rm -rf "${WORK}"
}

@test "removes a cache directory that holds only empty directories" {
  mkdir -p "${WORK}/cache/v6/.tmp"
  CACHE_DIR="${WORK}/cache" run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ ! -e "${WORK}/cache" ]
  [[ "$output" == *"Removed empty cache directory ${WORK}/cache"* ]]
}

@test "keeps a cache directory that holds a file" {
  mkdir -p "${WORK}/cache/v6"
  touch "${WORK}/cache/v6/npm-left-pad-1.3.0.tgz"
  CACHE_DIR="${WORK}/cache" run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ -f "${WORK}/cache/v6/npm-left-pad-1.3.0.tgz" ]
  [ -z "$output" ]
}

@test "does nothing when the cache directory does not exist" {
  CACHE_DIR="${WORK}/missing" run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "fails when CACHE_DIR is empty" {
  CACHE_DIR='' run bash "${SCRIPT}"
  [ "$status" -ne 0 ]
}
