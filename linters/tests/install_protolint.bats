#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../_lib/install_protolint.sh"
  FIX="$(mktemp -d)"
  BIN="$(mktemp -d)"
  DEST="${FIX}/dest"

  export PROTOLINT_API_URL="https://example.invalid/releases/latest"
  export PROTOLINT_DOWNLOAD_URL="https://example.invalid/download"
  export PATH="${BIN}:${PATH}"
  unset GITHUB_TOKEN

  make_release_json 'v0.57.0'
  make_release_tarball protolint protoc-gen-protolint
  make_checksums
  make_fake_curl
  # shellcheck source=/dev/null
  source "${SCRIPT}"
}

teardown() {
  rm -rf "${FIX}" "${BIN}"
}

make_release_json() {
  printf '{\n  "url": "https://example.invalid/x",\n  "tag_name": "%s",\n  "name": "%s"\n}\n' "$1" "$1" \
    > "${FIX}/release.json"
}

make_release_tarball() {
  local build="${FIX}/build" member
  rm -rf "${build}" "${FIX}/release.tar.gz"
  mkdir -p "${build}"
  for member in "$@"; do
    printf '#!/usr/bin/env bash\necho %s\n' "${member}" > "${build}/${member}"
  done
  printf 'MIT\n' > "${build}/LICENSE"
  tar -czf "${FIX}/release.tar.gz" -C "${build}" .
}

make_checksums() {
  local sum
  sum="$(sha256sum "${FIX}/release.tar.gz" | cut -d' ' -f1)"
  printf '%s  protolint_0.57.0_linux_amd64.tar.gz\n%s  protolint_0.57.0_linux_arm64.tar.gz\n' "${sum}" "${sum}" \
    > "${FIX}/checksums.txt"
}

make_fake_curl() {
  cat > "${BIN}/curl" <<EOF
#!/usr/bin/env bash
if [ -n "\${CURL_FAIL:-}" ]; then exit 22; fi
out=''
prev=''
url=''
for arg in "\$@"; do
  if [ "\${prev}" = '--output' ]; then out="\${arg}"; fi
  prev="\${arg}"
  url="\${arg}"
done
printf '%s\n' "\$*" >> "${FIX}/curl.log"
if [ -z "\${out}" ]; then
  cat "${FIX}/release.json"
elif [ "\${url##*/}" = 'checksums.txt' ]; then
  if [ -n "\${CURL_FAIL_CHECKSUMS:-}" ]; then exit 22; fi
  cp "${FIX}/checksums.txt" "\${out}"
else
  cp "${FIX}/release.tar.gz" "\${out}"
fi
EOF
  chmod +x "${BIN}/curl"
}

@test "protolint_asset maps x86_64 and amd64 to the linux amd64 archive" {
  run protolint_asset x86_64 0.57.0
  [ "$status" -eq 0 ]
  [ "$output" = 'protolint_0.57.0_linux_amd64.tar.gz' ]
  run protolint_asset amd64 0.57.0
  [ "$output" = 'protolint_0.57.0_linux_amd64.tar.gz' ]
}

@test "protolint_asset maps aarch64 and arm64 to the linux arm64 archive" {
  run protolint_asset aarch64 0.57.0
  [ "$status" -eq 0 ]
  [ "$output" = 'protolint_0.57.0_linux_arm64.tar.gz' ]
  run protolint_asset arm64 0.57.0
  [ "$output" = 'protolint_0.57.0_linux_arm64.tar.gz' ]
}

@test "protolint_asset fails on an unsupported or missing architecture" {
  run protolint_asset riscv64 0.57.0
  [ "$status" -eq 1 ]
  [[ "$output" == *'unsupported runner architecture'* ]]
  run protolint_asset
  [ "$status" -eq 1 ]
}

@test "protolint_resolve_version honours an explicit pin and strips a leading v" {
  run protolint_resolve_version 0.56.1
  [ "$output" = '0.56.1' ]
  run protolint_resolve_version v0.56.1
  [ "$status" -eq 0 ]
  [ "$output" = '0.56.1' ]
}

@test "protolint_resolve_version resolves latest from the release API without the v prefix" {
  run protolint_resolve_version latest
  [ "$status" -eq 0 ]
  [ "$output" = '0.57.0' ]
}

@test "protolint_resolve_version defaults to latest when nothing is requested" {
  run protolint_resolve_version
  [ "$output" = '0.57.0' ]
  run protolint_resolve_version ''
  [ "$status" -eq 0 ]
  [ "$output" = '0.57.0' ]
}

@test "protolint_resolve_version sends the token only when GITHUB_TOKEN is set" {
  run protolint_resolve_version latest
  run grep -q 'Authorization' "${FIX}/curl.log"
  [ "$status" -ne 0 ]
  export GITHUB_TOKEN=secret-token
  run protolint_resolve_version latest
  [ "$status" -eq 0 ]
  grep -q 'Authorization: Bearer secret-token' "${FIX}/curl.log"
}

@test "protolint_resolve_version fails when the API call fails or returns no tag" {
  CURL_FAIL=1 run protolint_resolve_version latest
  [ "$status" -eq 1 ]
  [[ "$output" == *'could not resolve the latest protolint release'* ]]
  printf '{"message":"Not Found"}\n' > "${FIX}/release.json"
  run protolint_resolve_version latest
  [ "$status" -eq 1 ]
}

@test "protolint_download_url adds the v prefix upstream tags carry" {
  run protolint_download_url 0.57.0 checksums.txt
  [ "$output" = 'https://example.invalid/download/v0.57.0/checksums.txt' ]
}

@test "protolint_verify accepts an archive matching checksums.txt" {
  run protolint_verify "${FIX}/release.tar.gz" protolint_0.57.0_linux_amd64.tar.gz "${FIX}/checksums.txt"
  [ "$status" -eq 0 ]
}

@test "protolint_verify rejects an archive whose checksum does not match" {
  printf 'tampered\n' >> "${FIX}/release.tar.gz"
  run protolint_verify "${FIX}/release.tar.gz" protolint_0.57.0_linux_amd64.tar.gz "${FIX}/checksums.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *'checksum mismatch for protolint_0.57.0_linux_amd64.tar.gz'* ]]
}

@test "protolint_verify rejects an asset checksums.txt does not list" {
  run protolint_verify "${FIX}/release.tar.gz" protolint_0.57.0_linux_armv7.tar.gz "${FIX}/checksums.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *'lists no checksum for protolint_0.57.0_linux_armv7.tar.gz'* ]]
}

@test "protolint_install installs the protolint binary from the verified archive" {
  run protolint_install 0.57.0 "${DEST}"
  [ "$status" -eq 0 ]
  [ -x "${DEST}/protolint" ]
  grep -qx 'echo protolint' "${DEST}/protolint"
  [ ! -e "${DEST}/protoc-gen-protolint" ]
  grep -q 'https://example.invalid/download/v0.57.0/protolint_0.57.0_linux_' "${FIX}/curl.log"
  grep -q 'https://example.invalid/download/v0.57.0/checksums.txt' "${FIX}/curl.log"
}

@test "protolint_install fails when the archive or checksums download fails" {
  CURL_FAIL=1 run protolint_install 0.57.0 "${DEST}"
  [ "$status" -eq 1 ]
  [[ "$output" == *'failed to download protolint 0.57.0'* ]]
  CURL_FAIL_CHECKSUMS=1 run protolint_install 0.57.0 "${DEST}"
  [ "$status" -eq 1 ]
  [ ! -e "${DEST}/protolint" ]
}

@test "protolint_install refuses a tampered archive" {
  printf 'tampered\n' >> "${FIX}/release.tar.gz"
  run protolint_install 0.57.0 "${DEST}"
  [ "$status" -eq 1 ]
  [[ "$output" == *'checksum mismatch'* ]]
  [ ! -e "${DEST}/protolint" ]
}

@test "protolint_install fails when the verified archive is not a tarball" {
  printf 'not a tarball\n' > "${FIX}/release.tar.gz"
  make_checksums
  run protolint_install 0.57.0 "${DEST}"
  [ "$status" -eq 1 ]
  [[ "$output" == *'failed to unpack'* ]]
  [ ! -e "${DEST}/protolint" ]
}

@test "protolint_install fails when the archive carries no protolint binary" {
  make_release_tarball protoc-gen-protolint
  make_checksums
  run protolint_install 0.57.0 "${DEST}"
  [ "$status" -eq 1 ]
  [[ "$output" == *'contains no protolint binary'* ]]
  [ ! -e "${DEST}/protolint" ]
}

@test "protolint_install fails on an unsupported architecture" {
  uname() { echo 'riscv64'; }
  export -f uname
  run protolint_install 0.57.0 "${DEST}"
  [ "$status" -eq 1 ]
  [[ "$output" == *'unsupported runner architecture'* ]]
}

@test "running the script installs a pinned protolint into the destination" {
  run env PROTOLINT_VERSION=0.57.0 bash "${SCRIPT}" "${DEST}"
  [ "$status" -eq 0 ]
  [ -x "${DEST}/protolint" ]
  [[ "$output" == *"protolint 0.57.0 installed at ${DEST}/protolint"* ]]
}

@test "running the script resolves latest when no version is pinned" {
  run env -u PROTOLINT_VERSION bash "${SCRIPT}" "${DEST}"
  [ "$status" -eq 0 ]
  [[ "$output" == *'protolint 0.57.0 installed'* ]]
}

@test "running the script fails when the release cannot be resolved" {
  run env CURL_FAIL=1 bash "${SCRIPT}" "${DEST}"
  [ "$status" -ne 0 ]
  [ ! -e "${DEST}/protolint" ]
}
