#!/usr/bin/env bats

# Tests for linters/_lib/clean_workspace.sh, the shared cleanup step used by
# linters/markdownlint/action.yml and linters/yamllint/action.yml (QUAL-006,
# #262). Every test runs inside a throwaway workspace so the deletions never
# touch the real checkout. The script guards its body behind
# `[[ "${BASH_SOURCE[0]}" == "${0}" ]]`, so it can be both sourced (to unit-test
# the helpers) and executed end-to-end.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../_lib/clean_workspace.sh"
  export SCRIPT
  WORK="$(mktemp -d)"
  export WORK
  cd "${WORK}" || exit 1
}

teardown() {
  cd / || true
  rm -rf "${WORK}"
}

# A .gitmodules with three submodules: two disposable, one whose path contains
# "scripts" and therefore must survive.
make_gitmodules() {
  mkdir -p vendored-lib shared-scripts docs-submodule
  touch vendored-lib/README.md shared-scripts/keep.md docs-submodule/doc.md
  cat > .gitmodules <<'EOF'
[submodule "vendored-lib"]
	path = vendored-lib
	url = git@github.com:example/vendored-lib.git
[submodule "shared-scripts"]
	path = shared-scripts
	url = git@github.com:example/shared-scripts.git
[submodule "docs-submodule"]
	path = docs-submodule
	url = git@github.com:example/docs-submodule.git
EOF
}

# ============================================================================
# remove_submodules
# ============================================================================

@test "removes submodule checkouts listed in .gitmodules" {
  make_gitmodules
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ ! -d vendored-lib ]
  [ ! -d docs-submodule ]
}

@test "keeps the scripts submodule so the linter config symlinks stay valid" {
  make_gitmodules
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ -d shared-scripts ]
  [ -f shared-scripts/keep.md ]
}

@test "a root config symlinked into the scripts submodule still resolves" {
  make_gitmodules
  mkdir -p shared-scripts/linters
  echo "rule: on" > shared-scripts/linters/.yamllint.yml
  ln -s shared-scripts/linters/.yamllint.yml .yamllint.yml
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ -f .yamllint.yml ]
  [ "$(cat .yamllint.yml)" = "rule: on" ]
}

@test "succeeds when there is no .gitmodules at all" {
  touch README.md
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ -f README.md ]
}

@test "succeeds when .gitmodules lists only the scripts submodule" {
  mkdir -p shared-scripts
  cat > .gitmodules <<'EOF'
[submodule "shared-scripts"]
	path = shared-scripts
	url = git@github.com:example/shared-scripts.git
EOF
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ -d shared-scripts ]
}

@test "tolerates a .gitmodules entry whose directory was never checked out" {
  cat > .gitmodules <<'EOF'
[submodule "never-cloned"]
	path = never-cloned
	url = git@github.com:example/never-cloned.git
EOF
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
}

@test "skips .gitmodules lines that match 'path' but carry no path value" {
  mkdir -p vendored-lib
  touch vendored-lib/README.md
  cat > .gitmodules <<'EOF'
# path
[submodule "vendored-lib"]
	path = vendored-lib
	url = git@github.com:example/vendored-lib.git
EOF
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
  [ ! -d vendored-lib ]
}

@test "leaves files that are not submodules untouched" {
  make_gitmodules
  mkdir -p src
  touch src/app.md
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ -f src/app.md ]
}

# ============================================================================
# remove_directories
# ============================================================================

@test "removes each named directory anywhere in the tree" {
  mkdir -p vendor app/node_modules ios/Libraries
  touch vendor/x.md app/node_modules/y.md ios/Libraries/z.md
  run bash "${SCRIPT}" vendor node_modules Libraries
  [ "$status" -eq 0 ]
  [ ! -d vendor ]
  [ ! -d app/node_modules ]
  [ ! -d ios/Libraries ]
  [ -d app ]
  [ -d ios ]
}

@test "removes nested occurrences of a named directory" {
  mkdir -p a/node_modules/pkg/node_modules
  touch a/node_modules/pkg/node_modules/deep.md
  run bash "${SCRIPT}" node_modules
  [ "$status" -eq 0 ]
  [ ! -d a/node_modules ]
  [ -d a ]
}

@test "does not need '|| true': find exits clean after deleting what it matched" {
  # Regression for QUAL-006. The old `-exec rm -rf {} \;` form made find descend
  # into a directory it had already deleted and exit non-zero with "No such file
  # or directory", which is why the callers masked it with `|| true`. The
  # -prune form must exit 0 on its own and print nothing on stderr.
  mkdir -p vendor/nested/deeper
  touch vendor/nested/deeper/f.md
  run bash "${SCRIPT}" vendor
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "ignores a file that merely shares the name of a directory to remove" {
  touch vendor
  run bash "${SCRIPT}" vendor
  [ "$status" -eq 0 ]
  [ -f vendor ]
}

@test "succeeds when none of the named directories exist" {
  touch README.md
  run bash "${SCRIPT}" vendor node_modules Libraries
  [ "$status" -eq 0 ]
  [ -f README.md ]
}

@test "removes nothing extra when called with no directory names (yamllint path)" {
  mkdir -p vendor node_modules Libraries
  touch vendor/x.md node_modules/y.md Libraries/z.md
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ -d vendor ]
  [ -d node_modules ]
  [ -d Libraries ]
}

# ============================================================================
# Combined markdownlint path
# ============================================================================

@test "markdownlint invocation removes submodules and vendored trees together" {
  make_gitmodules
  mkdir -p vendor app/node_modules ios/Libraries
  touch vendor/x.md app/node_modules/y.md ios/Libraries/z.md
  run bash "${SCRIPT}" vendor node_modules Libraries
  [ "$status" -eq 0 ]
  [ ! -d vendored-lib ]
  [ ! -d docs-submodule ]
  [ ! -d vendor ]
  [ ! -d app/node_modules ]
  [ ! -d ios/Libraries ]
  [ -d shared-scripts ]
}

@test "propagates failure instead of masking it when a removal cannot succeed" {
  # The `|| true` that this change removes would have swallowed this. Make the
  # parent directory read-only so rm cannot unlink the submodule checkout.
  # root ignores the write bit, so the failure cannot be provoked there.
  if [ "$(id -u)" -eq 0 ]; then
    skip "running as root: directory permissions do not block rm"
  fi
  mkdir -p locked/vendored-lib
  cat > .gitmodules <<'EOF'
[submodule "vendored-lib"]
	path = locked/vendored-lib
	url = git@github.com:example/vendored-lib.git
EOF
  chmod a-w locked
  run bash "${SCRIPT}"
  chmod u+w locked
  [ "$status" -ne 0 ]
}

# ============================================================================
# Sourcing guard
# ============================================================================

@test "sourcing the script does not delete anything" {
  make_gitmodules
  # shellcheck source=/dev/null
  source "${SCRIPT}"
  [ -d vendored-lib ]
  [ -d shared-scripts ]
  run type -t remove_submodules
  [ "$output" = "function" ]
}
