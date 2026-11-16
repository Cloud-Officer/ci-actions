#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../_lib/apt_install.sh"
  BIN="$(mktemp -d)"
  LOG="${BIN}/sudo.log"
  STATUS="${BIN}/status"
  CACHE="${BIN}/cache"
  cat > "${BIN}/sudo" <<EOF
#!/usr/bin/env bash
printf '%s|' "\$@" >> "${LOG}"
printf '\n' >> "${LOG}"
if [ -n "\${SUDO_FAIL_ON:-}" ] && [ "\$3" = "\${SUDO_FAIL_ON}" ]; then exit 100; fi
if [ -n "\${SUDO_FAIL_MATCH:-}" ] && [[ "\$*" == *"\${SUDO_FAIL_MATCH}"* ]]; then exit 100; fi
if [ -n "\${SUDO_FAIL_ONCE_MATCH:-}" ] && [[ "\$*" == *"\${SUDO_FAIL_ONCE_MATCH}"* ]] && [ ! -e "${BIN}/failed-once" ]; then touch "${BIN}/failed-once"; exit 100; fi
if [[ " \$* " == *" install "* ]] && [ -z "\${SUDO_NO_MARK:-}" ]; then echo installed > "${STATUS}"; fi
EOF
  cat > "${BIN}/dpkg-query" <<EOF
#!/usr/bin/env bash
[ -f "${STATUS}" ] || exit 1
for arg in "\$@"; do
  case "\${arg}" in -*) ;; *) cat "${STATUS}" ;; esac
done
EOF
  chmod +x "${BIN}/sudo" "${BIN}/dpkg-query"
  export PATH="${BIN}:${PATH}"
}

teardown() {
  rm -rf "${BIN}"
}

@test "updates the package index then installs each package as its own argument" {
  APT_PACKAGES='libpq-dev imagemagick' run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "${LOG}")" = 'apt-get|--yes|update|' ]
  [ "$(sed -n 2p "${LOG}")" = 'apt-get|--yes|--no-install-recommends|install|libpq-dev|imagemagick|' ]
}

@test "installs a single package" {
  APT_PACKAGES='graphviz' run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ "$(sed -n 2p "${LOG}")" = 'apt-get|--yes|--no-install-recommends|install|graphviz|' ]
}

@test "does not install when the package index update fails" {
  APT_PACKAGES='graphviz' SUDO_FAIL_ON=update run bash "${SCRIPT}"
  [ "$status" -ne 0 ]
  [ "$(wc -l < "${LOG}" | tr -d ' ')" = 1 ]
}

@test "fails when the install fails" {
  APT_PACKAGES='no-such-package' SUDO_FAIL_ON=--no-install-recommends run bash "${SCRIPT}"
  [ "$status" -eq 100 ]
}

@test "fails when APT_PACKAGES is not set" {
  run env -u APT_PACKAGES bash "${SCRIPT}"
  [ "$status" -ne 0 ]
  [ ! -e "${LOG}" ]
}

@test "skips update and install when every package is already installed" {
  echo installed > "${STATUS}"
  APT_PACKAGES='graphviz jq' run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Already installed: graphviz jq'* ]]
  [ ! -e "${LOG}" ]
}

@test "installs a package dpkg only knows by its leftover config files" {
  echo config-files > "${STATUS}"
  APT_PACKAGES='graphviz' run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "${LOG}")" = 'apt-get|--yes|update|' ]
}

@test "with a cache installs through the cache directory without updating the package index" {
  APT_PACKAGES='graphviz jq' APT_CACHE_DIR="${CACHE}" run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "${LOG}")" = "apt-get|--yes|--no-install-recommends|-o|Dir::Cache::Archives=${CACHE}|-o|APT::Keep-Downloaded-Packages=true|install|graphviz|jq|" ]
  [ "$(sed -n 2p "${LOG}")" = "chown|-R|$(id -u):$(id -g)|${CACHE}|" ]
  [ "$(wc -l < "${LOG}" | tr -d ' ')" = 2 ]
  [[ "$output" == *'Installed without apt-get update: graphviz jq'* ]]
}

@test "with a cache creates the partial directory apt needs" {
  APT_PACKAGES='graphviz' APT_CACHE_DIR="${CACHE}" run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ -d "${CACHE}/partial" ]
}

@test "with a cache succeeds for a virtual package dpkg does not report by its requested name" {
  mkdir -p "${CACHE}"
  touch "${CACHE}/libvips42t64.deb"
  APT_PACKAGES='libvips' APT_CACHE_DIR="${CACHE}" SUDO_NO_MARK=1 run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$output" != *'::warning::'* ]]
  ! grep -q '|update|' "${LOG}"
}

@test "creates the cache directory even when every package is already installed" {
  echo installed > "${STATUS}"
  APT_PACKAGES='graphviz' APT_CACHE_DIR="${CACHE}" run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ -d "${CACHE}" ]
  [ ! -e "${LOG}" ]
}

@test "with a cache updates the package index and retries when the first install fails" {
  APT_PACKAGES='graphviz' APT_CACHE_DIR="${CACHE}" SUDO_FAIL_ONCE_MATCH=Dir::Cache::Archives run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$output" == *'::warning::Installing without apt-get update failed'* ]]
  [ "$(sed -n 2p "${LOG}")" = 'apt-get|--yes|update|' ]
  [ "$(sed -n 3p "${LOG}")" = "apt-get|--yes|--no-install-recommends|-o|Dir::Cache::Archives=${CACHE}|-o|APT::Keep-Downloaded-Packages=true|install|graphviz|" ]
  [ "$(sed -n 4p "${LOG}")" = "chown|-R|$(id -u):$(id -g)|${CACHE}|" ]
}

@test "with a cache fails when the install still fails after updating the package index" {
  APT_PACKAGES='no-such-package' APT_CACHE_DIR="${CACHE}" SUDO_FAIL_MATCH=Dir::Cache::Archives run bash "${SCRIPT}"
  [ "$status" -eq 100 ]
  grep -q '|update|' "${LOG}"
}
