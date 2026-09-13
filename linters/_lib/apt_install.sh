#!/usr/bin/env bash

# Installs the space-separated APT_PACKAGES list with apt-get.
#
# Usage (from a composite action step):
#   env:
#     APT_PACKAGES: ${{ inputs.apt-packages }}
#   run: bash "${GITHUB_ACTION_PATH}/../_lib/apt_install.sh"

set -euo pipefail

: "${APT_PACKAGES?APT_PACKAGES must be set}"

sudo apt-get --yes update
# shellcheck disable=SC2086 # APT_PACKAGES is word-split on purpose: one input carries several packages.
sudo apt-get --yes --no-install-recommends install ${APT_PACKAGES}
