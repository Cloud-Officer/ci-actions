#!/usr/bin/env bats

# Tests for linters/_lib/install_swiftlint.sh (issue #258 / DEP-001), the
# replacement for the unmaintained norio-nomura/action-swiftlint@3.2.1.
#
# A fake `curl` on PATH serves a fixture release JSON and a fixture release zip
# (no network), mirroring how bump-actions.bats fakes `gh`. The script is also
# sourced so its helpers can be unit-tested directly (its body is guarded by
# `[[ "${BASH_SOURCE[0]}" == "${0}" ]]`).

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../_lib/install_swiftlint.sh"
  FIX="$(mktemp -d)"
  BIN="$(mktemp -d)"
  DEST="${FIX}/dest"

  export SWIFTLINT_API_URL="https://example.invalid/releases/latest"
  export SWIFTLINT_DOWNLOAD_URL="https://example.invalid/download"
  export PATH="${BIN}:${PATH}"

  make_release_json '0.65.0'
  make_release_zip swiftlint swiftlint-static
  make_fake_curl
  # shellcheck source=/dev/null
  source "${SCRIPT}"
}

teardown() {
  rm -rf "${FIX}" "${BIN}"
}

# Fixture release payload returned for the API URL.
make_release_json() {
  printf '{"url":"https://example.invalid/x","tag_name":"%s","name":"%s"}\n' "$1" "$1" \
    > "${FIX}/release.json"
}

# Fixture release archive containing the named members (each a stub binary).
make_release_zip() {
  local build="${FIX}/build" member
  rm -rf "${build}"
  rm -f "${FIX}/release.zip"
  mkdir -p "${build}"
  for member in "$@"; do
    printf '#!/usr/bin/env bash\necho %s\n' "${member}" > "${build}/${member}"
  done
  printf 'MIT\n' > "${build}/LICENSE"
  (cd "${build}" && zip -q -r "${FIX}/release.zip" .)
}

# Fake curl: `--output PATH` writes the fixture zip, everything else prints the
# fixture release JSON. CURL_FAIL=1 makes every invocation fail like --fail on
# a 404 would.
make_fake_curl() {
  cat > "${BIN}/curl" <<EOF
#!/usr/bin/env bash
if [ -n "\${CURL_FAIL:-}" ]; then exit 22; fi
out=''
prev=''
for arg in "\$@"; do
  if [ "\${prev}" = '--output' ]; then out="\${arg}"; fi
  prev="\${arg}"
done
if [ -n "\${out}" ]; then
  cp "${FIX}/release.zip" "\${out}"
else
  cat "${FIX}/release.json"
fi
EOF
  chmod +x "${BIN}/curl"
}

# ===========================================================================
# swiftlint_asset
# ===========================================================================

@test "swiftlint_asset maps x86_64 and amd64 to the linux amd64 archive" {
  run swiftlint_asset x86_64
  [ "$status" -eq 0 ]
  [ "$output" = 'swiftlint_linux_amd64.zip' ]
  run swiftlint_asset amd64
  [ "$status" -eq 0 ]
  [ "$output" = 'swiftlint_linux_amd64.zip' ]
}

@test "swiftlint_asset maps aarch64 and arm64 to the linux arm64 archive" {
  run swiftlint_asset aarch64
  [ "$status" -eq 0 ]
  [ "$output" = 'swiftlint_linux_arm64.zip' ]
  run swiftlint_asset arm64
  [ "$status" -eq 0 ]
  [ "$output" = 'swiftlint_linux_arm64.zip' ]
}

@test "swiftlint_asset fails on an unsupported architecture" {
  run swiftlint_asset riscv64
  [ "$status" -eq 1 ]
  [[ "$output" == *'unsupported runner architecture'* ]]
}

@test "swiftlint_asset fails when no architecture is given" {
  run swiftlint_asset
  [ "$status" -eq 1 ]
}

# ===========================================================================
# swiftlint_resolve_version
# ===========================================================================

@test "swiftlint_resolve_version honours an explicit pin" {
  run swiftlint_resolve_version 0.64.1
  [ "$status" -eq 0 ]
  [ "$output" = '0.64.1' ]
}

@test "swiftlint_resolve_version strips a leading v from an explicit pin" {
  run swiftlint_resolve_version v0.64.1
  [ "$status" -eq 0 ]
  [ "$output" = '0.64.1' ]
}

@test "swiftlint_resolve_version resolves latest from the release API" {
  run swiftlint_resolve_version latest
  [ "$status" -eq 0 ]
  [ "$output" = '0.65.0' ]
}

@test "swiftlint_resolve_version defaults to latest when nothing is requested" {
  run swiftlint_resolve_version
  [ "$status" -eq 0 ]
  [ "$output" = '0.65.0' ]
  run swiftlint_resolve_version ''
  [ "$status" -eq 0 ]
  [ "$output" = '0.65.0' ]
}

@test "swiftlint_resolve_version sends the token when GITHUB_TOKEN is set" {
  cat > "${BIN}/curl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "${FIX}/curl.args"
cat "${FIX}/release.json"
EOF
  chmod +x "${BIN}/curl"
  export GITHUB_TOKEN=secret-token
  run swiftlint_resolve_version latest
  [ "$status" -eq 0 ]
  grep -q 'Authorization: Bearer secret-token' "${FIX}/curl.args"
}

@test "swiftlint_resolve_version fails when the API call fails" {
  export CURL_FAIL=1
  run swiftlint_resolve_version latest
  [ "$status" -eq 1 ]
  [[ "$output" == *'could not resolve the latest swiftlint release'* ]]
}

@test "swiftlint_resolve_version fails when the API payload has no tag" {
  printf '{"message":"Not Found"}\n' > "${FIX}/release.json"
  run swiftlint_resolve_version latest
  [ "$status" -eq 1 ]
  [[ "$output" == *'could not resolve the latest swiftlint release'* ]]
}

# ===========================================================================
# swiftlint_download_url
# ===========================================================================

@test "swiftlint_download_url composes the release asset URL" {
  run swiftlint_download_url 0.65.0 swiftlint_linux_amd64.zip
  [ "$status" -eq 0 ]
  [ "$output" = 'https://example.invalid/download/0.65.0/swiftlint_linux_amd64.zip' ]
}

# ===========================================================================
# swiftlint_install
# ===========================================================================

@test "swiftlint_install prefers the statically linked binary" {
  run swiftlint_install 0.65.0 "${DEST}"
  [ "$status" -eq 0 ]
  [ -x "${DEST}/swiftlint" ]
  grep -q 'swiftlint-static' "${DEST}/swiftlint"
}

@test "swiftlint_install falls back to the dynamic binary when no static one ships" {
  make_release_zip swiftlint
  run swiftlint_install 0.65.0 "${DEST}"
  [ "$status" -eq 0 ]
  [ -x "${DEST}/swiftlint" ]
  grep -qx 'echo swiftlint' "${DEST}/swiftlint"
}

@test "swiftlint_install reports the resolved download URL" {
  run swiftlint_install 0.65.0 "${DEST}"
  [ "$status" -eq 0 ]
  [[ "$output" == *'https://example.invalid/download/0.65.0/swiftlint_linux_'*'.zip'* ]]
}

@test "swiftlint_install fails when the download fails" {
  export CURL_FAIL=1
  run swiftlint_install 0.65.0 "${DEST}"
  [ "$status" -eq 1 ]
  [[ "$output" == *'failed to download'* ]]
  [ ! -e "${DEST}/swiftlint" ]
}

@test "swiftlint_install fails when the archive is not a zip" {
  printf 'not a zip\n' > "${FIX}/release.zip"
  run swiftlint_install 0.65.0 "${DEST}"
  [ "$status" -eq 1 ]
  [[ "$output" == *'failed to unpack'* ]]
  [ ! -e "${DEST}/swiftlint" ]
}

@test "swiftlint_install fails when the archive carries no swiftlint binary" {
  make_release_zip somethingelse
  run swiftlint_install 0.65.0 "${DEST}"
  [ "$status" -eq 1 ]
  [[ "$output" == *'contains no swiftlint binary'* ]]
  [ ! -e "${DEST}/swiftlint" ]
}

@test "swiftlint_install fails on an unsupported architecture" {
  uname() { echo 'riscv64'; }
  export -f uname
  run swiftlint_install 0.65.0 "${DEST}"
  [ "$status" -eq 1 ]
  [[ "$output" == *'unsupported runner architecture'* ]]
}

# ===========================================================================
# Executed body
# ===========================================================================

@test "running the script installs swiftlint into the destination directory" {
  run env SWIFTLINT_VERSION=0.65.0 bash "${SCRIPT}" "${DEST}"
  [ "$status" -eq 0 ]
  [ -x "${DEST}/swiftlint" ]
  [[ "$output" == *"SwiftLint 0.65.0 installed at ${DEST}/swiftlint"* ]]
}

@test "running the script resolves latest when no version is pinned" {
  run env -u SWIFTLINT_VERSION bash "${SCRIPT}" "${DEST}"
  [ "$status" -eq 0 ]
  [[ "$output" == *'SwiftLint 0.65.0 installed'* ]]
}

@test "running the script fails when the release cannot be resolved" {
  run env CURL_FAIL=1 bash "${SCRIPT}" "${DEST}"
  [ "$status" -ne 0 ]
  [ ! -e "${DEST}/swiftlint" ]
}
