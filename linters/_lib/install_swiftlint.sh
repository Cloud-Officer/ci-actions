#!/usr/bin/env bash

# Installs SwiftLint from the upstream realm/SwiftLint GitHub release.
#
# Usage (from a composite action step):
#   run: bash "${GITHUB_ACTION_PATH}/../_lib/install_swiftlint.sh" /opt/swiftlint
#
# SWIFTLINT_VERSION pins a release (e.g. 0.65.0); empty or `latest` tracks upstream.

SWIFTLINT_API_URL="${SWIFTLINT_API_URL:-https://api.github.com/repos/realm/SwiftLint/releases/latest}"
SWIFTLINT_DOWNLOAD_URL="${SWIFTLINT_DOWNLOAD_URL:-https://github.com/realm/SwiftLint/releases/download}"

# swiftlint_asset ARCH -> the release asset name for that runner architecture.
function swiftlint_asset()
{
  case "${1:-}" in
    x86_64 | amd64)  printf 'swiftlint_linux_amd64.zip\n' ;;
    aarch64 | arm64) printf 'swiftlint_linux_arm64.zip\n' ;;
    *)
      echo "::error::unsupported runner architecture '${1:-}' - swiftlint publishes linux amd64/arm64 binaries only" >&2
      return 1
      ;;
  esac
}

# swiftlint_resolve_version [REQUESTED] -> a release tag without a leading `v`.
function swiftlint_resolve_version()
{
  local requested="${1:-latest}" body version

  if [ -n "${requested}" ] && [ "${requested}" != "latest" ]; then
    printf '%s\n' "${requested#v}"
    return 0
  fi

  if [ -n "${GITHUB_TOKEN:-}" ]; then
    body="$(curl --fail --silent --show-error --location \
      --header "Authorization: Bearer ${GITHUB_TOKEN}" "${SWIFTLINT_API_URL}")" || body=''
  else
    body="$(curl --fail --silent --show-error --location "${SWIFTLINT_API_URL}")" || body=''
  fi

  version="$(printf '%s' "${body}" \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"

  if [ -z "${version}" ]; then
    echo "::error::could not resolve the latest swiftlint release from ${SWIFTLINT_API_URL}" >&2
    return 1
  fi

  printf '%s\n' "${version#v}"
}

# swiftlint_download_url VERSION ASSET -> the release download URL.
function swiftlint_download_url()
{
  printf '%s/%s/%s\n' "${SWIFTLINT_DOWNLOAD_URL}" "${1}" "${2}"
}

# swiftlint_install VERSION DEST -> leaves an executable `swiftlint` in DEST.
function swiftlint_install()
{
  local version="${1}" dest="${2}" asset url tmp binary

  asset="$(swiftlint_asset "$(uname -m)")" || return 1
  url="$(swiftlint_download_url "${version}" "${asset}")"
  tmp="$(mktemp -d)"

  echo "Installing SwiftLint ${version} from ${url}"

  if ! curl --fail --silent --show-error --location --output "${tmp}/swiftlint.zip" "${url}"; then
    echo "::error::failed to download ${url}" >&2
    rm -rf "${tmp}"
    return 1
  fi

  if ! unzip -q -o -d "${tmp}" "${tmp}/swiftlint.zip"; then
    echo "::error::failed to unpack ${asset}" >&2
    rm -rf "${tmp}"
    return 1
  fi

  # The dynamic binary needs a Swift runtime that stock ubuntu runners lack.
  binary="${tmp}/swiftlint-static"
  [ -f "${binary}" ] || binary="${tmp}/swiftlint"

  if [ ! -f "${binary}" ]; then
    echo "::error::${asset} contains no swiftlint binary" >&2
    rm -rf "${tmp}"
    return 1
  fi

  mkdir -p "${dest}"
  mv "${binary}" "${dest}/swiftlint"
  chmod +x "${dest}/swiftlint"
  rm -rf "${tmp}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail

  swiftlint_dest="${1:-/opt/swiftlint}"
  swiftlint_version="$(swiftlint_resolve_version "${SWIFTLINT_VERSION:-latest}")"
  swiftlint_install "${swiftlint_version}" "${swiftlint_dest}"
  echo "SwiftLint ${swiftlint_version} installed at ${swiftlint_dest}/swiftlint"
fi
