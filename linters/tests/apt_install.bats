#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../_lib/apt_install.sh"
  BIN="$(mktemp -d)"
  LOG="${BIN}/sudo.log"
  cat > "${BIN}/sudo" <<EOF
#!/usr/bin/env bash
printf '%s|' "\$@" >> "${LOG}"
printf '\n' >> "${LOG}"
if [ -n "\${SUDO_FAIL_ON:-}" ] && [ "\$5" = "\${SUDO_FAIL_ON}" ]; then exit 100; fi
EOF
  chmod +x "${BIN}/sudo"
  export PATH="${BIN}:${PATH}"
}

teardown() {
  rm -rf "${BIN}"
}

@test "updates the package index then installs each package as its own argument" {
  APT_PACKAGES='libpq-dev imagemagick' run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "${LOG}")" = 'apt-get|--yes|-o|Acquire::Retries=5|update|' ]
  [ "$(sed -n 2p "${LOG}")" = 'apt-get|--yes|-o|Acquire::Retries=5|--no-install-recommends|install|libpq-dev|imagemagick|' ]
}

@test "installs a single package" {
  APT_PACKAGES='graphviz' run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ "$(sed -n 2p "${LOG}")" = 'apt-get|--yes|-o|Acquire::Retries=5|--no-install-recommends|install|graphviz|' ]
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
