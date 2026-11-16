#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../_lib/apt_install.sh"
  BIN="$(mktemp -d)"
  LOG="${BIN}/sudo.log"
  STATUS="${BIN}/status"
  CACHE="${BIN}/cache"
  export APT_ARCHIVES_DIR="${BIN}/archives"
  mkdir -p "${APT_ARCHIVES_DIR}"
  cat > "${BIN}/sudo" <<EOF
#!/usr/bin/env bash
printf '%s|' "\$@" >> "${LOG}"
printf '\n' >> "${LOG}"
if [ -n "\${SUDO_FAIL_ON:-}" ] && [ "\$3" = "\${SUDO_FAIL_ON}" ]; then exit 100; fi
if [ -n "\${SUDO_FAIL_MATCH:-}" ] && [[ "\$*" == *"\${SUDO_FAIL_MATCH}"* ]]; then exit 100; fi
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

@test "on a cache miss keeps the downloaded packages and copies them to the cache directory" {
  touch "${APT_ARCHIVES_DIR}/graphviz.deb" "${APT_ARCHIVES_DIR}/libgvc.deb"
  APT_PACKAGES='graphviz' APT_CACHE_DIR="${CACHE}" run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "${LOG}")" = 'apt-get|--yes|update|' ]
  [ "$(sed -n 2p "${LOG}")" = 'apt-get|clean|' ]
  [ "$(sed -n 3p "${LOG}")" = 'apt-get|--yes|--no-install-recommends|-o|APT::Keep-Downloaded-Packages=true|install|graphviz|' ]
  [ "$(cd "${CACHE}" && ls)" = "$(printf 'graphviz.deb\nlibgvc.deb')" ]
}

@test "on a cache miss with nothing downloaded leaves an empty cache directory" {
  APT_PACKAGES='graphviz' APT_CACHE_DIR="${CACHE}" run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ -d "${CACHE}" ]
  [ -z "$(ls -A "${CACHE}")" ]
}

@test "creates the cache directory even when every package is already installed" {
  echo installed > "${STATUS}"
  APT_PACKAGES='graphviz' APT_CACHE_DIR="${CACHE}" run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ -d "${CACHE}" ]
  [ ! -e "${LOG}" ]
}

@test "on a cache hit installs the cached packages without updating the package index" {
  mkdir -p "${CACHE}"
  touch "${CACHE}/graphviz.deb" "${CACHE}/libgvc.deb"
  APT_PACKAGES='graphviz' APT_CACHE_DIR="${CACHE}" run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "${LOG}" | tr -d ' ')" = 1 ]
  [ "$(sed -n 1p "${LOG}")" = "apt-get|--yes|--no-install-recommends|install|${CACHE}/graphviz.deb|${CACHE}/libgvc.deb|" ]
  [[ "$output" == *'Installed from the apt cache: graphviz'* ]]
}

@test "falls back to update and install, refreshing the cache, when the cached packages do not install" {
  mkdir -p "${CACHE}"
  touch "${CACHE}/stale.deb" "${APT_ARCHIVES_DIR}/graphviz.deb"
  APT_PACKAGES='graphviz' APT_CACHE_DIR="${CACHE}" SUDO_FAIL_MATCH=stale.deb run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$output" == *'::warning::Installing from the apt cache failed'* ]]
  [ "$(sed -n 2p "${LOG}")" = 'apt-get|--yes|update|' ]
  [ "$(sed -n 4p "${LOG}")" = 'apt-get|--yes|--no-install-recommends|-o|APT::Keep-Downloaded-Packages=true|install|graphviz|' ]
  [ "$(cd "${CACHE}" && ls)" = 'graphviz.deb' ]
}

@test "falls back to update and install when the cached packages leave a requested package missing" {
  mkdir -p "${CACHE}"
  touch "${CACHE}/libgvc.deb"
  APT_PACKAGES='graphviz' APT_CACHE_DIR="${CACHE}" SUDO_NO_MARK=1 run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ "$(sed -n 2p "${LOG}")" = 'apt-get|--yes|update|' ]
}
