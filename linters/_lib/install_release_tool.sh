#!/usr/bin/env bash

# Installs the latest upstream release of a linter tool, retrying transient download failures.
#
# Usage (from a composite action step):
#   run: bash "${GITHUB_ACTION_PATH}/../_lib/install_release_tool.sh" TOOL DEST
#
# TOOL is one of reviewdog, hadolint, actionlint or shellcheck. DEST is added to GITHUB_PATH when set.

RELEASE_API_URL="${RELEASE_API_URL:-https://api.github.com/repos}"
RELEASE_DOWNLOAD_URL="${RELEASE_DOWNLOAD_URL:-https://github.com}"
CURL_OPTIONS=(--fail --silent --show-error --location --retry 5 --retry-all-errors)

# tool_repo TOOL -> the GitHub owner/repo publishing TOOL.
function tool_repo()
{
  case "${1:-}" in
    reviewdog)  printf 'reviewdog/reviewdog\n' ;;
    hadolint)   printf 'hadolint/hadolint\n' ;;
    actionlint) printf 'rhysd/actionlint\n' ;;
    shellcheck) printf 'koalaman/shellcheck\n' ;;
    *)
      echo "::error::unsupported tool '${1:-}' - expected reviewdog, hadolint, actionlint or shellcheck" >&2
      return 1
      ;;
  esac
}

# tool_asset TOOL VERSION ARCH -> the release asset name for that runner architecture.
function tool_asset()
{
  local tool="${1:-}" version="${2:-}" goarch unamearch

  case "${3:-}" in
    x86_64 | amd64)  goarch=amd64 unamearch=x86_64 ;;
    aarch64 | arm64) goarch=arm64 unamearch=aarch64 ;;
    *)
      echo "::error::unsupported runner architecture '${3:-}' - ${tool} is installed for linux amd64/arm64 only" >&2
      return 1
      ;;
  esac

  case "${tool}" in
    reviewdog)  printf 'reviewdog_%s_Linux_%s.tar.gz\n' "${version}" "${unamearch/aarch64/arm64}" ;;
    hadolint)   printf 'hadolint-linux-%s\n' "${unamearch/aarch64/arm64}" ;;
    actionlint) printf 'actionlint_%s_linux_%s.tar.gz\n' "${version}" "${goarch}" ;;
    shellcheck) printf 'shellcheck-v%s.linux.%s.tar.gz\n' "${version}" "${unamearch}" ;;
    *) tool_repo "${tool}" >/dev/null ;;
  esac
}

# tool_checksums TOOL VERSION -> the release checksums file name, empty when upstream publishes none.
function tool_checksums()
{
  case "${1:-}" in
    reviewdog)  printf 'checksums.txt\n' ;;
    hadolint)   printf 'checksums.sha256\n' ;;
    actionlint) printf 'actionlint_%s_checksums.txt\n' "${2:-}" ;;
    shellcheck) printf '\n' ;;
    *) tool_repo "${1:-}" >/dev/null ;;
  esac
}

# tool_resolve_version TOOL -> the latest release version without the leading `v`.
function tool_resolve_version()
{
  local tool="${1:-}" repo body version
  local -a auth=()

  repo="$(tool_repo "${tool}")" || return 1

  if [ -n "${GITHUB_TOKEN:-}" ]; then
    auth=(--header "Authorization: Bearer ${GITHUB_TOKEN}")
  fi

  body="$(curl "${CURL_OPTIONS[@]}" "${auth[@]}" "${RELEASE_API_URL}/${repo}/releases/latest")" || body=''
  version="$(printf '%s' "${body}" \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"

  if [ -z "${version}" ]; then
    echo "::error::could not resolve the latest ${tool} release from ${RELEASE_API_URL}/${repo}" >&2
    return 1
  fi

  printf '%s\n' "${version#v}"
}

# tool_download_url TOOL VERSION FILE -> the release download URL (every supported upstream tags with a `v`).
function tool_download_url()
{
  printf '%s/%s/releases/download/v%s/%s\n' "${RELEASE_DOWNLOAD_URL}" "$(tool_repo "${1}")" "${2}" "${3}"
}

# tool_verify FILE ASSET CHECKSUMS -> succeeds only when FILE matches the SHA-256 listed for ASSET.
function tool_verify()
{
  local file="${1}" asset="${2}" checksums="${3}" expected actual

  expected="$(awk -v asset="${asset}" '$2 == asset || $2 == "*" asset { print $1 }' "${checksums}")"
  if [ -z "${expected}" ]; then
    echo "::error::${checksums##*/} lists no checksum for ${asset}" >&2
    return 1
  fi

  actual="$(sha256sum "${file}" | cut -d' ' -f1)"
  if [ "${actual}" != "${expected}" ]; then
    echo "::error::checksum mismatch for ${asset}: expected ${expected}, got ${actual}" >&2
    return 1
  fi
}

# tool_install TOOL VERSION DEST -> leaves a verified, executable TOOL in DEST.
function tool_install()
{
  local tool="${1}" version="${2}" dest="${3}" asset checksums tmp binary

  asset="$(tool_asset "${tool}" "${version}" "$(uname -m)")" || return 1
  checksums="$(tool_checksums "${tool}" "${version}")"
  tmp="$(mktemp -d)"

  echo "Installing ${tool} ${version} from $(tool_download_url "${tool}" "${version}" "${asset}")"

  if ! curl "${CURL_OPTIONS[@]}" --output "${tmp}/${asset}" "$(tool_download_url "${tool}" "${version}" "${asset}")"; then
    echo "::error::failed to download ${tool} ${version}" >&2
    rm -rf "${tmp}"
    return 1
  fi

  if [ -n "${checksums}" ]; then
    if ! curl "${CURL_OPTIONS[@]}" --output "${tmp}/${checksums}" "$(tool_download_url "${tool}" "${version}" "${checksums}")" \
      || ! tool_verify "${tmp}/${asset}" "${asset}" "${tmp}/${checksums}"; then
      echo "::error::could not verify ${asset}" >&2
      rm -rf "${tmp}"
      return 1
    fi
  fi

  if [[ "${asset}" == *.tar.gz ]]; then
    if ! tar -xzf "${tmp}/${asset}" -C "${tmp}" 2>/dev/null; then
      echo "::error::failed to unpack ${asset}" >&2
      rm -rf "${tmp}"
      return 1
    fi
    binary="$(find "${tmp}" -type f -name "${tool}" | head -1)"
  else
    binary="${tmp}/${asset}"
  fi

  if [ -z "${binary}" ] || [ ! -f "${binary}" ]; then
    echo "::error::${asset} contains no ${tool} binary" >&2
    rm -rf "${tmp}"
    return 1
  fi

  mkdir -p "${dest}"
  mv "${binary}" "${dest}/${tool}"
  chmod +x "${dest}/${tool}"
  rm -rf "${tmp}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail

  tool="${1:?usage: install_release_tool.sh TOOL DEST}"
  dest="${2:?usage: install_release_tool.sh TOOL DEST}"
  version="$(tool_resolve_version "${tool}")"
  tool_install "${tool}" "${version}" "${dest}"

  if [ -n "${GITHUB_PATH:-}" ]; then
    echo "${dest}" >> "${GITHUB_PATH}"
  fi

  echo "${tool} ${version} installed at ${dest}/${tool}"
fi
