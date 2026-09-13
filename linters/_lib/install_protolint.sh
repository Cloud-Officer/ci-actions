#!/usr/bin/env bash

# Installs protolint from the upstream yoheimuta/protolint release after verifying it against the release checksums.txt.
#
# Usage (from linters/protolint/action.yml):
#   run: bash "${GITHUB_ACTION_PATH}/../_lib/install_protolint.sh" /opt/protolint
#
# PROTOLINT_VERSION pins a release (e.g. 0.57.0); empty or `latest` tracks upstream.

PROTOLINT_API_URL="${PROTOLINT_API_URL:-https://api.github.com/repos/yoheimuta/protolint/releases/latest}"
PROTOLINT_DOWNLOAD_URL="${PROTOLINT_DOWNLOAD_URL:-https://github.com/yoheimuta/protolint/releases/download}"

# protolint_asset ARCH VERSION -> the release archive name for that runner architecture.
function protolint_asset()
{
  case "${1:-}" in
    x86_64 | amd64)  printf 'protolint_%s_linux_amd64.tar.gz\n' "${2:-}" ;;
    aarch64 | arm64) printf 'protolint_%s_linux_arm64.tar.gz\n' "${2:-}" ;;
    *)
      echo "::error::unsupported runner architecture '${1:-}' - protolint is installed for linux amd64/arm64 only" >&2
      return 1
      ;;
  esac
}

# protolint_resolve_version [REQUESTED] -> a release version without the leading `v`.
function protolint_resolve_version()
{
  local requested="${1:-latest}" body version
  local -a auth=()

  if [ -n "${requested}" ] && [ "${requested}" != "latest" ]; then
    printf '%s\n' "${requested#v}"
    return 0
  fi

  if [ -n "${GITHUB_TOKEN:-}" ]; then
    auth=(--header "Authorization: Bearer ${GITHUB_TOKEN}")
  fi

  body="$(curl --fail --silent --show-error --location "${auth[@]}" "${PROTOLINT_API_URL}")" || body=''
  version="$(printf '%s' "${body}" \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"

  if [ -z "${version}" ]; then
    echo "::error::could not resolve the latest protolint release from ${PROTOLINT_API_URL}" >&2
    return 1
  fi

  printf '%s\n' "${version#v}"
}

# protolint_download_url VERSION FILE -> the release download URL (upstream tags carry a `v`).
function protolint_download_url()
{
  printf '%s/v%s/%s\n' "${PROTOLINT_DOWNLOAD_URL}" "${1}" "${2}"
}

# protolint_verify ARCHIVE ASSET CHECKSUMS -> succeeds only when ARCHIVE matches the SHA-256 listed for ASSET.
function protolint_verify()
{
  local archive="${1}" asset="${2}" checksums="${3}" expected actual

  expected="$(awk -v asset="${asset}" '$2 == asset { print $1 }' "${checksums}")"
  if [ -z "${expected}" ]; then
    echo "::error::checksums.txt lists no checksum for ${asset}" >&2
    return 1
  fi

  actual="$(sha256sum "${archive}" | cut -d' ' -f1)"
  if [ "${actual}" != "${expected}" ]; then
    echo "::error::checksum mismatch for ${asset}: expected ${expected}, got ${actual}" >&2
    return 1
  fi
}

# protolint_install VERSION DEST -> leaves a verified, executable `protolint` in DEST.
function protolint_install()
{
  local version="${1}" dest="${2}" asset url tmp

  asset="$(protolint_asset "$(uname -m)" "${version}")" || return 1
  url="$(protolint_download_url "${version}" "${asset}")"
  tmp="$(mktemp -d)"

  echo "Installing protolint ${version} from ${url}"

  if ! curl --fail --silent --show-error --location --output "${tmp}/${asset}" "${url}" \
    || ! curl --fail --silent --show-error --location --output "${tmp}/checksums.txt" \
      "$(protolint_download_url "${version}" checksums.txt)"; then
    echo "::error::failed to download protolint ${version}" >&2
    rm -rf "${tmp}"
    return 1
  fi

  if ! protolint_verify "${tmp}/${asset}" "${asset}" "${tmp}/checksums.txt"; then
    rm -rf "${tmp}"
    return 1
  fi

  if ! tar -xzf "${tmp}/${asset}" -C "${tmp}" 2>/dev/null; then
    echo "::error::failed to unpack ${asset}" >&2
    rm -rf "${tmp}"
    return 1
  fi

  if [ ! -f "${tmp}/protolint" ]; then
    echo "::error::${asset} contains no protolint binary" >&2
    rm -rf "${tmp}"
    return 1
  fi

  mkdir -p "${dest}"
  mv "${tmp}/protolint" "${dest}/protolint"
  chmod +x "${dest}/protolint"
  rm -rf "${tmp}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail

  protolint_dest="${1:-/opt/protolint}"
  protolint_version="$(protolint_resolve_version "${PROTOLINT_VERSION:-latest}")"
  protolint_install "${protolint_version}" "${protolint_dest}"
  echo "protolint ${protolint_version} installed at ${protolint_dest}/protolint"
fi
