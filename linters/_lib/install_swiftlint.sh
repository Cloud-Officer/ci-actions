#!/usr/bin/env bash

# Install SwiftLint straight from the upstream realm/SwiftLint GitHub release.
#
# Usage (from a composite action step):
#   run: bash "${GITHUB_ACTION_PATH}/../_lib/install_swiftlint.sh" /opt/swiftlint
#
# Replaces norio-nomura/action-swiftlint@3.2.1 (issue #258 / DEP-001), whose
# last release predates 2021 and pinned a `norionomura/swiftlint:swift-5`
# Docker base — an unmaintained supply-chain dependency running a frozen
# toolchain. Upstream publishes `swiftlint_linux_{amd64,arm64}.zip` on every
# release; the `swiftlint-static` binary inside is fully statically linked, so
# it runs on a stock ubuntu runner with no Swift toolchain installed.
#
# Set SWIFTLINT_VERSION to a release tag (e.g. 0.65.0) to pin, or leave it at
# `latest` to track upstream the way the other linters do. SWIFTLINT_API_URL /
# SWIFTLINT_DOWNLOAD_URL exist so the test suite can point the resolver and the
# downloader at fixtures instead of the network. The body runs only when this
# file is executed directly, so the suite can source it to unit-test the
# helpers below.

SWIFTLINT_API_URL="${SWIFTLINT_API_URL:-https://api.github.com/repos/realm/SwiftLint/releases/latest}"
SWIFTLINT_DOWNLOAD_URL="${SWIFTLINT_DOWNLOAD_URL:-https://github.com/realm/SwiftLint/releases/download}"

# ===========================================================================
# Helpers (individually testable)
# ===========================================================================

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

# swiftlint_resolve_version [REQUESTED] -> a concrete release tag. Anything but
# an empty value or `latest` is taken as an explicit pin (a leading `v` is
# dropped: upstream tags are bare, e.g. 0.65.0).
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

  # Parsed with sed rather than jq so the resolver has no dependency beyond
  # curl (jq is present on the runners but not necessarily anywhere else).
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

# swiftlint_install VERSION DEST -> downloads the release zip for this runner's
# architecture and leaves an executable `swiftlint` in DEST.
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

  # Prefer the statically linked binary: the dynamic one needs the Swift
  # runtime, which a stock ubuntu runner does not have.
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

# ===========================================================================
# Body
# ===========================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail

  swiftlint_dest="${1:-/opt/swiftlint}"
  swiftlint_version="$(swiftlint_resolve_version "${SWIFTLINT_VERSION:-latest}")"
  swiftlint_install "${swiftlint_version}" "${swiftlint_dest}"
  echo "SwiftLint ${swiftlint_version} installed at ${swiftlint_dest}/swiftlint"
fi
