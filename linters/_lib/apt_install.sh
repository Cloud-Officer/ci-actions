#!/usr/bin/env bash

# Installs the space-separated APT_PACKAGES list with apt-get, unless every package is already installed.
#
# With APT_CACHE_DIR set, downloaded .deb files are kept there and later reinstalled from it without `apt-get update`.
#
# Usage (from a composite action step):
#   env:
#     APT_PACKAGES: ${{ inputs.apt-packages }}
#     APT_CACHE_DIR: ${{ steps.apt-cache-key.outputs.dir }}   # optional
#   run: bash "${GITHUB_ACTION_PATH}/../_lib/apt_install.sh"

set -euo pipefail

: "${APT_PACKAGES?APT_PACKAGES must be set}"

cache_dir="${APT_CACHE_DIR:-}"
archives="${APT_ARCHIVES_DIR:-/var/cache/apt/archives}"

all_installed() {
  local status
  # shellcheck disable=SC2016,SC2086 # the format is dpkg-query's, not a shell expansion; APT_PACKAGES is word-split on purpose.
  status="$(dpkg-query --show --showformat='${db:Status-Status}\n' ${APT_PACKAGES} 2> /dev/null)" || return 1
  ! grep --quiet --invert-match '^installed$' <<< "${status}"
}

if [ -n "${cache_dir}" ]; then
  mkdir -p "${cache_dir}"
fi

if all_installed; then
  echo "Already installed: ${APT_PACKAGES}"
  exit 0
fi

if [ -n "${cache_dir}" ] && compgen -G "${cache_dir}/*.deb" > /dev/null; then
  if sudo apt-get --yes --no-install-recommends install "${cache_dir}"/*.deb && all_installed; then
    echo "Installed from the apt cache: ${APT_PACKAGES}"
    exit 0
  fi

  echo "::warning::Installing from the apt cache failed - falling back to apt-get update and install"
fi

sudo apt-get --yes update

if [ -z "${cache_dir}" ]; then
  # shellcheck disable=SC2086 # APT_PACKAGES is word-split on purpose: one input carries several packages.
  sudo apt-get --yes --no-install-recommends install ${APT_PACKAGES}
  exit 0
fi

sudo apt-get clean
# shellcheck disable=SC2086 # APT_PACKAGES is word-split on purpose: one input carries several packages.
sudo apt-get --yes --no-install-recommends -o APT::Keep-Downloaded-Packages=true install ${APT_PACKAGES}

rm -f "${cache_dir}"/*.deb

if compgen -G "${archives}/*.deb" > /dev/null; then
  cp "${archives}"/*.deb "${cache_dir}/"
fi
