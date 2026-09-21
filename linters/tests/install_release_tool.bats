#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../_lib/install_release_tool.sh"
  FIX="$(mktemp -d)"
  BIN="$(mktemp -d)"
  DEST="${FIX}/dest"

  export RELEASE_API_URL="https://example.invalid/repos"
  export RELEASE_DOWNLOAD_URL="https://example.invalid"
  export PATH="${BIN}:${PATH}"
  unset GITHUB_TOKEN GITHUB_PATH

  make_release_json 'v0.21.2'
  make_release_tarball reviewdog
  make_checksums 'reviewdog_0.21.2_Linux_x86_64.tar.gz' 'reviewdog_0.21.2_Linux_arm64.tar.gz'
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
  local build="${FIX}/build/nested" member
  rm -rf "${FIX}/build" "${FIX}/release"
  mkdir -p "${build}"
  for member in "$@"; do
    printf '#!/usr/bin/env bash\necho %s\n' "${member}" > "${build}/${member}"
  done
  printf 'MIT\n' > "${build}/LICENSE"
  tar -czf "${FIX}/release" -C "${FIX}/build" .
}

make_checksums() {
  local sum asset
  sum="$(sha256sum "${FIX}/release" | cut -d' ' -f1)"
  : > "${FIX}/checksums"
  for asset in "$@"; do
    printf '%s  %s\n' "${sum}" "${asset}" >> "${FIX}/checksums"
  done
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
elif [[ "\${url##*/}" == *checksums* ]]; then
  if [ -n "\${CURL_FAIL_CHECKSUMS:-}" ]; then exit 22; fi
  cp "${FIX}/checksums" "\${out}"
else
  cp "${FIX}/release" "\${out}"
fi
EOF
  chmod +x "${BIN}/curl"
}

@test "tool_repo maps each supported tool to its upstream repository" {
  run tool_repo reviewdog
  [ "$output" = 'reviewdog/reviewdog' ]
  run tool_repo hadolint
  [ "$output" = 'hadolint/hadolint' ]
  run tool_repo actionlint
  [ "$output" = 'rhysd/actionlint' ]
  run tool_repo shellcheck
  [ "$output" = 'koalaman/shellcheck' ]
}

@test "tool_repo rejects an unsupported tool" {
  run tool_repo yamllint
  [ "$status" -eq 1 ]
  [[ "$output" == *"unsupported tool 'yamllint'"* ]]
}

@test "tool_asset names the upstream amd64 asset of every tool" {
  run tool_asset reviewdog 0.21.2 x86_64
  [ "$output" = 'reviewdog_0.21.2_Linux_x86_64.tar.gz' ]
  run tool_asset hadolint 2.15.1 amd64
  [ "$output" = 'hadolint-linux-x86_64' ]
  run tool_asset actionlint 1.7.12 x86_64
  [ "$output" = 'actionlint_1.7.12_linux_amd64.tar.gz' ]
  run tool_asset shellcheck 0.11.0 x86_64
  [ "$output" = 'shellcheck-v0.11.0.linux.x86_64.tar.gz' ]
}

@test "tool_asset names the upstream arm64 asset of every tool" {
  run tool_asset reviewdog 0.21.2 aarch64
  [ "$output" = 'reviewdog_0.21.2_Linux_arm64.tar.gz' ]
  run tool_asset hadolint 2.15.1 arm64
  [ "$output" = 'hadolint-linux-arm64' ]
  run tool_asset actionlint 1.7.12 aarch64
  [ "$output" = 'actionlint_1.7.12_linux_arm64.tar.gz' ]
  run tool_asset shellcheck 0.11.0 arm64
  [ "$output" = 'shellcheck-v0.11.0.linux.aarch64.tar.gz' ]
}

@test "tool_asset fails on an unsupported architecture or tool" {
  run tool_asset reviewdog 0.21.2 riscv64
  [ "$status" -eq 1 ]
  [[ "$output" == *'unsupported runner architecture'* ]]
  run tool_asset yamllint 1.0.0 x86_64
  [ "$status" -eq 1 ]
}

@test "tool_checksums names each tool's checksums file and none for shellcheck" {
  run tool_checksums reviewdog 0.21.2
  [ "$output" = 'checksums.txt' ]
  run tool_checksums hadolint 2.15.1
  [ "$output" = 'checksums.sha256' ]
  run tool_checksums actionlint 1.7.12
  [ "$output" = 'actionlint_1.7.12_checksums.txt' ]
  run tool_checksums shellcheck 0.11.0
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "tool_resolve_version resolves latest without the v prefix and retries curl" {
  run tool_resolve_version reviewdog
  [ "$status" -eq 0 ]
  [ "$output" = '0.21.2' ]
  grep -q 'https://example.invalid/repos/reviewdog/reviewdog/releases/latest' "${FIX}/curl.log"
  grep -q -- '--retry 5 --retry-all-errors' "${FIX}/curl.log"
}

@test "tool_resolve_version sends the token only when GITHUB_TOKEN is set" {
  run tool_resolve_version reviewdog
  run grep -q 'Authorization' "${FIX}/curl.log"
  [ "$status" -ne 0 ]
  export GITHUB_TOKEN=secret-token
  run tool_resolve_version reviewdog
  [ "$status" -eq 0 ]
  grep -q 'Authorization: Bearer secret-token' "${FIX}/curl.log"
}

@test "tool_resolve_version fails when the API call fails or returns no tag" {
  CURL_FAIL=1 run tool_resolve_version reviewdog
  [ "$status" -eq 1 ]
  [[ "$output" == *'could not resolve the latest reviewdog release'* ]]
  printf '{"message":"Not Found"}\n' > "${FIX}/release.json"
  run tool_resolve_version reviewdog
  [ "$status" -eq 1 ]
}

@test "tool_download_url adds the v prefix upstream tags carry" {
  run tool_download_url actionlint 1.7.12 actionlint_1.7.12_checksums.txt
  [ "$output" = 'https://example.invalid/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_checksums.txt' ]
}

@test "tool_verify accepts both plain and starred checksum entries" {
  run tool_verify "${FIX}/release" reviewdog_0.21.2_Linux_x86_64.tar.gz "${FIX}/checksums"
  [ "$status" -eq 0 ]
  printf '%s *hadolint-linux-x86_64\n' "$(sha256sum "${FIX}/release" | cut -d' ' -f1)" > "${FIX}/checksums"
  run tool_verify "${FIX}/release" hadolint-linux-x86_64 "${FIX}/checksums"
  [ "$status" -eq 0 ]
}

@test "tool_verify rejects a mismatched or unlisted asset" {
  printf 'tampered\n' >> "${FIX}/release"
  run tool_verify "${FIX}/release" reviewdog_0.21.2_Linux_x86_64.tar.gz "${FIX}/checksums"
  [ "$status" -eq 1 ]
  [[ "$output" == *'checksum mismatch'* ]]
  run tool_verify "${FIX}/release" reviewdog_0.21.2_Linux_armv6.tar.gz "${FIX}/checksums"
  [ "$status" -eq 1 ]
  [[ "$output" == *'lists no checksum for reviewdog_0.21.2_Linux_armv6.tar.gz'* ]]
}

@test "tool_install installs a nested binary from a verified tarball" {
  run tool_install reviewdog 0.21.2 "${DEST}"
  [ "$status" -eq 0 ]
  [ -x "${DEST}/reviewdog" ]
  grep -qx 'echo reviewdog' "${DEST}/reviewdog"
  grep -q 'releases/download/v0.21.2/checksums.txt' "${FIX}/curl.log"
}

@test "tool_install installs a bare binary asset" {
  printf '#!/usr/bin/env bash\necho hadolint\n' > "${FIX}/release"
  make_checksums hadolint-linux-x86_64 hadolint-linux-arm64
  run tool_install hadolint 2.15.1 "${DEST}"
  [ "$status" -eq 0 ]
  [ -x "${DEST}/hadolint" ]
  grep -qx 'echo hadolint' "${DEST}/hadolint"
}

@test "tool_install skips verification for a tool that publishes no checksums" {
  make_release_tarball shellcheck
  run tool_install shellcheck 0.11.0 "${DEST}"
  [ "$status" -eq 0 ]
  [ -x "${DEST}/shellcheck" ]
  run grep -q 'checksums' "${FIX}/curl.log"
  [ "$status" -ne 0 ]
}

@test "tool_install fails when the asset or checksums download fails" {
  CURL_FAIL=1 run tool_install reviewdog 0.21.2 "${DEST}"
  [ "$status" -eq 1 ]
  [[ "$output" == *'failed to download reviewdog 0.21.2'* ]]
  CURL_FAIL_CHECKSUMS=1 run tool_install reviewdog 0.21.2 "${DEST}"
  [ "$status" -eq 1 ]
  [[ "$output" == *'could not verify'* ]]
  [ ! -e "${DEST}/reviewdog" ]
}

@test "tool_install refuses a tampered asset" {
  printf 'tampered\n' >> "${FIX}/release"
  run tool_install reviewdog 0.21.2 "${DEST}"
  [ "$status" -eq 1 ]
  [[ "$output" == *'checksum mismatch'* ]]
  [ ! -e "${DEST}/reviewdog" ]
}

@test "tool_install fails when the tarball is corrupt or lacks the binary" {
  printf 'not a tarball\n' > "${FIX}/release"
  make_checksums reviewdog_0.21.2_Linux_x86_64.tar.gz reviewdog_0.21.2_Linux_arm64.tar.gz
  run tool_install reviewdog 0.21.2 "${DEST}"
  [ "$status" -eq 1 ]
  [[ "$output" == *'failed to unpack'* ]]
  make_release_tarball something-else
  make_checksums reviewdog_0.21.2_Linux_x86_64.tar.gz reviewdog_0.21.2_Linux_arm64.tar.gz
  run tool_install reviewdog 0.21.2 "${DEST}"
  [ "$status" -eq 1 ]
  [[ "$output" == *'contains no reviewdog binary'* ]]
  [ ! -e "${DEST}/reviewdog" ]
}

@test "running the script installs the tool and adds it to GITHUB_PATH" {
  run env GITHUB_PATH="${FIX}/github_path" bash "${SCRIPT}" reviewdog "${DEST}"
  [ "$status" -eq 0 ]
  [ -x "${DEST}/reviewdog" ]
  [[ "$output" == *"reviewdog 0.21.2 installed at ${DEST}/reviewdog"* ]]
  [ "$(cat "${FIX}/github_path")" = "${DEST}" ]
}

@test "running the script fails without a tool or destination" {
  run bash "${SCRIPT}"
  [ "$status" -ne 0 ]
  run bash "${SCRIPT}" reviewdog
  [ "$status" -ne 0 ]
}

@test "running the script fails when the release cannot be resolved" {
  run env CURL_FAIL=1 bash "${SCRIPT}" reviewdog "${DEST}"
  [ "$status" -ne 0 ]
  [ ! -e "${DEST}/reviewdog" ]
}
