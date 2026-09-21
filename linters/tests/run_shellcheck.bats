#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../_lib/run_shellcheck.sh"
  WORK="$(mktemp -d)"
  BIN="$(mktemp -d)"
  export PATH="${BIN}:${PATH}"
  # shellcheck source=/dev/null
  source "${SCRIPT}"
  cd "${WORK}" || return 1
}

teardown() {
  rm -rf "${WORK}" "${BIN}"
}

found_files() {
  shellcheck_files | tr '\0' '\n' | sort
}

@test "finds .sh files and files with a shell shebang" {
  mkdir -p bin scripts
  printf 'echo hi\n' > scripts/build.sh
  printf '#!/usr/bin/env bash\necho hi\n' > bin/deploy
  printf '#!/bin/sh\necho hi\n' > bin/run
  printf '#!/usr/bin/env python3\nprint(1)\n' > bin/tool
  printf 'plain text\n' > README
  [ "$(found_files)" = "$(printf './bin/deploy\n./bin/run\n./scripts/build.sh')" ]
}

@test "skips vendored trees, git internals and bats files" {
  mkdir -p .git/hooks vendor node_modules/x Pods Libraries .vendor tests
  for dir in .git/hooks vendor node_modules/x Pods Libraries .vendor; do
    printf '#!/bin/sh\n' > "${dir}/script.sh"
  done
  printf '#!/usr/bin/env bats\n' > tests/suite.bats
  printf 'echo kept\n' > kept.sh
  [ "$(found_files)" = './kept.sh' ]
}

@test "keeps paths containing spaces intact" {
  mkdir -p 'my dir'
  printf 'echo hi\n' > 'my dir/a b.sh'
  [ "$(found_files)" = './my dir/a b.sh' ]
}

@test "running the script exits cleanly when there is nothing to check" {
  printf 'plain text\n' > README
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$output" == *'No shell scripts found to check.'* ]]
}

@test "running the script fails when reviewdog reports findings" {
  printf 'echo hi\n' > a.sh
  printf '#!/usr/bin/env bash\ncase "$1" in --version) echo fake;; -f) [ "$2" = json ] && echo "[]";; esac\nexit 0\n' > "${BIN}/shellcheck"
  printf '#!/usr/bin/env bash\ncat >/dev/null\nexit "${REVIEWDOG_STATUS:-0}"\n' > "${BIN}/reviewdog"
  chmod +x "${BIN}/shellcheck" "${BIN}/reviewdog"
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  REVIEWDOG_STATUS=1 run bash "${SCRIPT}"
  [ "$status" -ne 0 ]
}
