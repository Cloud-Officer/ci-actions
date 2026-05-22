#!/usr/bin/env bats

# Tests for bump-actions/bump-actions.sh. A fake `gh` on PATH resolves a
# fixed version/tag map (no network), and BUMP_SCAN_ROOT points the scanner at a
# throwaway fixture tree — mirroring how deploy.bats fakes `aws`. The script is
# also sourced so its helpers can be unit-tested directly (its body is guarded
# by `[[ "${BASH_SOURCE[0]}" == "${0}" ]]`).

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../bump-actions.sh"
  FIX="$(mktemp -d)"
  BIN="$(mktemp -d)"
  export BUMP_SCAN_ROOT="${FIX}"
  export PATH="${BIN}:${PATH}"
  make_fake_gh
  make_fixtures
  # shellcheck source=/dev/null
  source "${SCRIPT}"
}

teardown() {
  rm -rf "${FIX}" "${BIN}"
}

# Fake gh: latest versions per repo, single-ref tag existence, and notes.
make_fake_gh() {
  cat > "${BIN}/gh" <<'EOF'
#!/usr/bin/env bash
args="$*"
case "$args" in
  *"repos/actions/checkout/releases/latest"*)         echo "v7.0.0" ;;
  *"repos/docker/build-push-action/releases/latest"*) echo "v7.2.0" ;;
  *"repos/webfactory/ssh-agent/releases/latest"*)     echo "v0.10.0" ;;
  *"repos/some-org/already-current/releases/latest"*) echo "v2.3.4" ;;
  *"repos/only-in-generated/action/releases/latest"*) echo "v9.0.0" ;;
  *"repos/branchy/action/releases/latest"*)           echo "v3.0.0" ;;
  *"repos/ahead/action/releases/latest"*)             echo "v7.0.0" ;;
  *"repos/tagonly/action/releases/latest"*)           echo "" ;;
  *"repos/tagonly/action/tags"*)                      printf 'v3.1.0\nv3.0.0\nv2.0.0\n' ;;
  *"repos/actions/checkout/git/ref/tags/v7"*)         echo "refs/tags/v7" ;;
  *"repos/docker/build-push-action/git/ref/tags/v7"*) echo "refs/tags/v7" ;;
  *"git/ref/tags/"*)                                  exit 1 ;;
  "release view"*)                                    echo "fake release notes" ;;
  *)                                                  echo "" ;;
esac
EOF
  chmod +x "${BIN}/gh"
}

make_fixtures() {
  mkdir -p "${FIX}/setup" "${FIX}/comment" "${FIX}/.github/workflows"

  # Composite action: floating major, exact pin, already-current, self-ref,
  # SHA pin, local refs (with and without @), a branch pin, an ahead-of-latest
  # pin, and a tag-only repo.
  cat > "${FIX}/setup/action.yml" <<'EOF'
runs:
  using: composite
  steps:
  - uses: actions/checkout@v6
  - uses: webfactory/ssh-agent@v0.9.1
  - uses: some-org/already-current@v2
  - uses: cloud-officer/internal-action@v2
  - uses: pinned/by-sha@0123456789abcdef0123456789abcdef01234567
  - uses: ./linters/local-composite
  - uses: ./local/action@v1
  - uses: branchy/action@main
  - uses: ahead/action@v8.0.0
  - uses: tagonly/action@v2
EOF

  # A ref with a trailing comment, to prove the rewrite preserves it.
  cat > "${FIX}/comment/action.yml" <<'EOF'
runs:
  steps:
  - uses: actions/checkout@v6   # keep this comment
EOF

  # Hand-maintained workflow (no generator marker): should be scanned.
  cat > "${FIX}/.github/workflows/smoke.yml" <<'EOF'
name: Smoke
jobs:
  s:
    steps:
    - uses: docker/build-push-action@v6
EOF

  # github-build-generated workflow: must be skipped entirely.
  cat > "${FIX}/.github/workflows/build.yml" <<'EOF'
# github-build --organization Cloud-Officer
name: Build
jobs:
  b:
    steps:
    - uses: only-in-generated/action@v1
EOF
}

# ===========================================================================
# Helper unit tests (sourced)
# ===========================================================================

@test "is_sha matches only 40-char hex" {
  is_sha 0123456789abcdef0123456789abcdef01234567
  ! is_sha v6
  ! is_sha 0123456789abcdef0123456789abcdef0123456g
}

@test "is_floating_major / is_exact_semver classification" {
  is_floating_major v6
  is_floating_major 1
  ! is_floating_major v0.9.1
  ! is_floating_major main
  is_exact_semver v0.9.1
  is_exact_semver 0.35.0
  ! is_exact_semver v6
  ! is_exact_semver main
}

@test "major_of strips the v and takes the leading number" {
  [ "$(major_of v6)" = 6 ]
  [ "$(major_of v7.2.0)" = 7 ]
  [ "$(major_of 0.35.0)" = 0 ]
}

@test "version_gt is newer-aware and v-prefix insensitive" {
  version_gt v0.10.0 v0.9.1
  version_gt v0.36.0 0.35.0
  ! version_gt v0.35.0 0.35.0
  ! version_gt v7.0.0 v8.0.0
}

@test "esc_re escapes regex metacharacters" {
  [ "$(esc_re 'a.b/c')" = 'a\.b\/c' ]
}

# ===========================================================================
# Dry-run resolution
# ===========================================================================

@test "dry run lists floating-major and exact bumps" {
  run "${SCRIPT}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"actions/checkout"*"v6 -> v7"* ]]
  [[ "${output}" == *"webfactory/ssh-agent"*"v0.9.1 -> v0.10.0"* ]]
  [[ "${output}" == *"docker/build-push-action"*"v6 -> v7"* ]]
}

@test "floating major stays floating (not pinned to exact)" {
  run "${SCRIPT}"
  [[ "${output}" == *"v6 -> v7"* ]]
  [[ "${output}" != *"v6 -> v7.0.0"* ]]
}

@test "action already on the latest major is not bumped" {
  run "${SCRIPT}"
  [[ "${output}" != *"some-org/already-current"* ]]
}

@test "self-references (cloud-officer/*) are skipped" {
  run "${SCRIPT}"
  [[ "${output}" != *"cloud-officer/internal-action"* ]]
}

@test "SHA-pinned references are skipped" {
  run "${SCRIPT}"
  [[ "${output}" != *"pinned/by-sha"* ]]
}

@test "local ./ references are skipped" {
  run "${SCRIPT}"
  [[ "${output}" != *"local/action"* ]]
}

@test "branch pins (e.g. @main) are skipped, not converted to a tag" {
  run "${SCRIPT}"
  # No bump line for it (a "::warning:: ... not a version tag" on stderr is expected).
  ! grep -qE '^BUMP[[:space:]]+branchy/action' <<< "${output}"
  [[ "${output}" == *"branchy/action@main is not a version tag"* ]]
}

@test "exact pins ahead of the latest release are not downgraded" {
  run "${SCRIPT}"
  [[ "${output}" != *"ahead/action"* ]]
}

@test "tag-only repos resolve via the tags fallback" {
  run "${SCRIPT}"
  # releases/latest empty -> highest semver tag v3.1.0; no floating v3 tag -> exact
  [[ "${output}" == *"tagonly/action"*"v2 -> v3.1.0"* ]]
}

@test "github-build-generated files are not scanned" {
  run "${SCRIPT}"
  [[ "${output}" != *"only-in-generated/action"* ]]
}

# ===========================================================================
# Apply
# ===========================================================================

@test "--apply rewrites refs in scanned files but not generated ones" {
  run "${SCRIPT}" --apply
  [ "${status}" -eq 0 ]
  grep -q 'actions/checkout@v7'          "${FIX}/setup/action.yml"
  grep -q 'webfactory/ssh-agent@v0.10.0' "${FIX}/setup/action.yml"
  grep -q 'docker/build-push-action@v7'  "${FIX}/.github/workflows/smoke.yml"
  # current-major, skipped, and branch refs are untouched
  grep -q 'some-org/already-current@v2'    "${FIX}/setup/action.yml"
  grep -q 'cloud-officer/internal-action@v2' "${FIX}/setup/action.yml"
  grep -q 'branchy/action@main'            "${FIX}/setup/action.yml"
  grep -q 'ahead/action@v8.0.0'            "${FIX}/setup/action.yml"
  # generated file is left exactly as-is
  grep -q 'only-in-generated/action@v1'    "${FIX}/.github/workflows/build.yml"
}

@test "--apply preserves a trailing comment on the rewritten line" {
  run "${SCRIPT}" --apply
  [ "${status}" -eq 0 ]
  grep -q 'actions/checkout@v7   # keep this comment' "${FIX}/comment/action.yml"
}

# ===========================================================================
# PR body and empty result
# ===========================================================================

@test "--pr-body-file writes a table and release notes" {
  body="$(mktemp)"
  run "${SCRIPT}" --apply --pr-body-file "${body}"
  [ "${status}" -eq 0 ]
  grep -q '| Action | From | To |' "${body}"
  grep -q '| actions/checkout | v6 | v7 |' "${body}"
  grep -q 'fake release notes' "${body}"
  rm -f "${body}"
}

@test "no bumps available exits 0 with a clear message" {
  empty="$(mktemp -d)"
  mkdir -p "${empty}/setup"
  printf 'runs:\n  steps:\n  - uses: some-org/already-current@v2\n' > "${empty}/setup/action.yml"
  BUMP_SCAN_ROOT="${empty}" run "${SCRIPT}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"No external action bumps available."* ]]
  rm -rf "${empty}"
}
