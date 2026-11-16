#!/usr/bin/env bash

# Installs the space-separated APT_PACKAGES list with apt-get, unless every package is already installed.
#
# With APT_CACHE_DIR set, apt uses it as its archive directory: verified .deb files found there are not downloaded again,
# and `apt-get update` runs only when installing from the image's package index fails.
#
# Usage (from a composite action step):
#   env:
#     APT_PACKAGES: ${{ inputs.apt-packages }}
#     APT_CACHE_DIR: ${{ steps.apt-cache-key.outputs.dir }}   # optional
#   run: bash "${GITHUB_ACTION_PATH}/../_lib/apt_install.sh"

set -euo pipefail

: "${APT_PACKAGES?APT_PACKAGES must be set}"

cache_dir="${APT_CACHE_DIR:-}"

all_installed() {
  local status
  # shellcheck disable=SC2016,SC2086 # the format is dpkg-query's, not a shell expansion; APT_PACKAGES is word-split on purpose.
  status="$(dpkg-query --show --showformat='${db:Status-Status}\n' ${APT_PACKAGES} 2> /dev/null)" || return 1
  ! grep --quiet --invert-match '^installed$' <<< "${status}"
}

if [ -n "${cache_dir}" ]; then
  mkdir -p "${cache_dir}/partial"
fi

if all_installed; then
  echo "Already installed: ${APT_PACKAGES}"
  exit 0
fi

if [ -z "${cache_dir}" ]; then
  sudo apt-get --yes update
  # shellcheck disable=SC2086 # APT_PACKAGES is word-split on purpose: one input carries several packages.
  sudo apt-get --yes --no-install-recommends install ${APT_PACKAGES}
  exit 0
fi

install_with_cache() {
  # shellcheck disable=SC2086 # APT_PACKAGES is word-split on purpose: one input carries several packages.
  sudo apt-get --yes --no-install-recommends -o "Dir::Cache::Archives=${cache_dir}" -o APT::Keep-Downloaded-Packages=true install ${APT_PACKAGES}
}

if install_with_cache; then
  echo "Installed without apt-get update: ${APT_PACKAGES}"
else
  echo "::warning::Installing without apt-get update failed - updating the package index and retrying"
  sudo apt-get --yes update
  install_with_cache
fi

sudo chown -R "$(id -u):$(id -g)" "${cache_dir}"
