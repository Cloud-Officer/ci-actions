#!/usr/bin/env bats

setup() {
  HELPER="${BATS_TEST_DIRNAME}/../_lib/submodule_paths.sh"
  WORK="$(mktemp -d)"
  cd "${WORK}" || exit 1
  # shellcheck source=/dev/null
  source "${HELPER}"
}

teardown() {
  cd / || true
  rm -rf "${WORK}"
}

@test "prints nothing and succeeds when there is no .gitmodules" {
  run submodule_paths
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "prints nothing and succeeds when .gitmodules declares no path" {
  printf '[submodule "empty"]\n\turl = git@github.com:example/empty.git\n' > .gitmodules
  run submodule_paths
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "lists every path in a git-written .gitmodules" {
  cat > .gitmodules <<'GITMODULES'
[submodule "vendored-lib"]
	path = vendored-lib
	url = git@github.com:example/vendored-lib.git
[submodule "scripts"]
	path = tools/scripts
	url = git@github.com:example/scripts.git
GITMODULES
  run submodule_paths
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'vendored-lib\ntools/scripts')" ]
}

@test "lists a path written without spaces around '='" {
  printf '[submodule "vendor"]\n\tpath=vendor/lib\n\turl=git@github.com:example/lib.git\n' > .gitmodules
  run submodule_paths
  [ "$status" -eq 0 ]
  [ "$output" = "vendor/lib" ]
}

@test "ignores 'path = ' appearing in a url or a submodule name" {
  cat > .gitmodules <<'GITMODULES'
[submodule "path = fake"]
	path = real-lib
	url = https://example.com/path = decoy.git
GITMODULES
  run submodule_paths
  [ "$status" -eq 0 ]
  [ "$output" = "real-lib" ]
}

@test "keeps a path that contains spaces intact when the submodule is named after it" {
  printf '[submodule "third party/docs"]\n\tpath = third party/docs\n' > .gitmodules
  run submodule_paths
  [ "$status" -eq 0 ]
  [ "$output" = "third party/docs" ]
}

@test "skips a path key that carries no value" {
  printf '[submodule "broken"]\n\tpath\n[submodule "ok"]\n\tpath = ok-lib\n' > .gitmodules
  run submodule_paths
  [ "$status" -eq 0 ]
  [ "$output" = "ok-lib" ]
}

@test "does not abort a caller running under set -eo pipefail when nothing matches" {
  printf '[submodule "empty"]\n\turl = git@github.com:example/empty.git\n' > .gitmodules
  run bash -c 'set -eo pipefail; source "$1"; submodule_paths; echo reached' _ "${HELPER}"
  [ "$status" -eq 0 ]
  [ "$output" = "reached" ]
}
