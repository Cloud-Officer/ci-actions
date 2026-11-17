#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../_lib/apt_install.sh"
  BIN="$(cd "$(mktemp -d)" && pwd -P)"
  LOG="${BIN}/sudo.log"
  STATUS="${BIN}/status"
  CACHE="${BIN}/cache"
  export ROOT="${BIN}/root" DPKG_ADMINDIR="${BIN}/dpkg"
  export APT_SNAPSHOT_SCAN_ROOTS="${ROOT}"
  mkdir -p "${DPKG_ADMINDIR}/info" "${DPKG_ADMINDIR}/alternatives" "${ROOT}"
  cat > "${BIN}/sudo" <<EOF
#!/usr/bin/env bash
printf '%s|' "\$@" >> "${LOG}"
printf '\n' >> "${LOG}"
if [ -n "\${SUDO_FAIL_ON:-}" ] && [ "\$3" = "\${SUDO_FAIL_ON}" ]; then exit 100; fi
if [ -n "\${SUDO_FAIL_MATCH:-}" ] && [[ "\$*" == *"\${SUDO_FAIL_MATCH}"* ]]; then exit 100; fi
if [ -n "\${SUDO_FAIL_ONCE_MATCH:-}" ] && [[ "\$*" == *"\${SUDO_FAIL_ONCE_MATCH}"* ]] && [ ! -e "${BIN}/failed-once" ]; then touch "${BIN}/failed-once"; exit 100; fi
if [[ " \$* " == *" install "* ]] && [ -z "\${SUDO_NO_MARK:-}" ]; then echo installed > "${STATUS}"; fi
if [[ " \$* " == *" install "* ]] && [ -f "${BIN}/on-install" ]; then bash "${BIN}/on-install"; fi
case "\$1" in tar|tee|find) exec "\$@" ;; esac
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

stanza() {
  printf 'Package: %s\nStatus: install ok installed\nArchitecture: amd64\nVersion: %s\n\n' "$1" "$2"
}

simulate_ffmpeg_install() {
  stanza base-files 13 > "${DPKG_ADMINDIR}/status"
  {
    declare -f stanza
    cat <<'EOF'
mkdir -p "${ROOT}/usr/bin" "${ROOT}/usr/lib"
echo binary > "${ROOT}/usr/bin/ffmpeg"
ln -sf ffmpeg "${ROOT}/usr/bin/avconv"
echo library > "${ROOT}/usr/lib/libavcodec.so.61"
printf '%s\n' /. "${ROOT}/usr/bin" "${ROOT}/usr/bin/ffmpeg" "${ROOT}/usr/bin/avconv" "${ROOT}/usr/share/doc/excluded" > "${DPKG_ADMINDIR}/info/ffmpeg.list"
echo checksums > "${DPKG_ADMINDIR}/info/ffmpeg.md5sums"
printf '%s\n' "${ROOT}/usr/lib/libavcodec.so.61" > "${DPKG_ADMINDIR}/info/libavcodec61:amd64.list"
echo 'activate-noawait ldconfig' > "${DPKG_ADMINDIR}/info/libavcodec61:amd64.triggers"
{ stanza ffmpeg 7.0; stanza libavcodec61 7.0; } >> "${DPKG_ADMINDIR}/status"
EOF
  } > "${BIN}/on-install"
}

reset_runner() {
  rm -rf "${ROOT}" "${DPKG_ADMINDIR}/info"/* "${STATUS}" "${LOG}" "${BIN}/on-install"
  stanza base-files 13 > "${DPKG_ADMINDIR}/status"
}

install_ffmpeg_then_reset_runner() {
  simulate_ffmpeg_install
  APT_PACKAGES='ffmpeg' APT_CACHE_DIR="${CACHE}" bash "${SCRIPT}" > /dev/null
  reset_runner
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

@test "with a cache saves the files, dpkg records and status of the newly installed packages" {
  simulate_ffmpeg_install
  APT_PACKAGES='ffmpeg' APT_CACHE_DIR="${CACHE}" run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Saved the installed files of 2 packages for the next run'* ]]
  entries="$(tar -t -f "${CACHE}/installed.tar")"
  grep -qx "${ROOT#/}/usr/bin/ffmpeg" <<< "${entries}"
  grep -qx "${ROOT#/}/usr/bin/avconv" <<< "${entries}"
  grep -qx "${ROOT#/}/usr/lib/libavcodec.so.61" <<< "${entries}"
  grep -qx "${DPKG_ADMINDIR#/}/info/ffmpeg.list" <<< "${entries}"
  grep -qx "${DPKG_ADMINDIR#/}/info/ffmpeg.md5sums" <<< "${entries}"
  grep -qx "${DPKG_ADMINDIR#/}/info/libavcodec61:amd64.triggers" <<< "${entries}"
  ! grep -qx "${ROOT#/}/usr/bin/\?" <<< "${entries}"
  ! grep -q excluded <<< "${entries}"
  grep -qx 'Package: ffmpeg' "${CACHE}/installed.status"
  grep -qx 'Package: libavcodec61' "${CACHE}/installed.status"
  ! grep -qx 'Package: base-files' "${CACHE}/installed.status"
  [ ! -e "${CACHE}/installed.tar.tmp" ]
}

@test "with a saved snapshot restores the installed files and dpkg records without apt-get" {
  install_ffmpeg_then_reset_runner
  APT_PACKAGES='ffmpeg' APT_CACHE_DIR="${CACHE}" run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Restored from the installed-files snapshot: ffmpeg'* ]]
  [ "$(cat "${ROOT}/usr/bin/ffmpeg")" = binary ]
  [ "$(readlink "${ROOT}/usr/bin/avconv")" = ffmpeg ]
  [ -f "${DPKG_ADMINDIR}/info/ffmpeg.md5sums" ]
  grep -qx 'Package: base-files' "${DPKG_ADMINDIR}/status"
  grep -qx 'Package: ffmpeg' "${DPKG_ADMINDIR}/status"
  grep -qx 'ldconfig|' "${LOG}"
  ! grep -q 'apt-get' "${LOG}"
}

@test "with the snapshot tarball missing installs from the cached .deb files" {
  install_ffmpeg_then_reset_runner
  rm "${CACHE}/installed.tar"
  APT_PACKAGES='ffmpeg' APT_CACHE_DIR="${CACHE}" run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$output" != *'::warning::'* ]]
  grep -q "Dir::Cache::Archives=${CACHE}" "${LOG}"
  ! grep -qx 'ldconfig|' "${LOG}"
}

@test "with a corrupt snapshot tarball warns and installs from the cached .deb files" {
  install_ffmpeg_then_reset_runner
  echo corrupt > "${CACHE}/installed.tar"
  APT_PACKAGES='ffmpeg' APT_CACHE_DIR="${CACHE}" run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$output" == *'::warning::Restoring the installed-files snapshot failed'* ]]
  grep -q "Dir::Cache::Archives=${CACHE}" "${LOG}"
  ! grep -qx 'ldconfig|' "${LOG}"
}

@test "does not restore the snapshot over a package dpkg already knows" {
  install_ffmpeg_then_reset_runner
  printf 'Package: ffmpeg\nStatus: deinstall ok config-files\nArchitecture: amd64\nVersion: 6.0\n\n' >> "${DPKG_ADMINDIR}/status"
  APT_PACKAGES='ffmpeg' APT_CACHE_DIR="${CACHE}" run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$output" == *'::warning::Restoring the installed-files snapshot failed'* ]]
  ! grep -q '^tar|-x|' "${LOG}"
  grep -q "Dir::Cache::Archives=${CACHE}" "${LOG}"
}

@test "does not snapshot packages whose maintainer scripts add users" {
  simulate_ffmpeg_install
  echo "echo 'adduser --system ffmpeg' > \"\${DPKG_ADMINDIR}/info/ffmpeg.postinst\"" >> "${BIN}/on-install"
  APT_PACKAGES='ffmpeg' APT_CACHE_DIR="${CACHE}" run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Not snapshotting: ffmpeg:amd64 has maintainer scripts'* ]]
  [ ! -e "${CACHE}/installed.tar" ]
}

@test "does not snapshot when the install upgraded an already installed package" {
  simulate_ffmpeg_install
  echo 'stanza base-files 14 >> "${DPKG_ADMINDIR}/status"' >> "${BIN}/on-install"
  APT_PACKAGES='ffmpeg' APT_CACHE_DIR="${CACHE}" run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Not snapshotting: the install upgraded a package'* ]]
  [ ! -e "${CACHE}/installed.tar" ]
}

@test "saves the alternatives the install registered" {
  simulate_ffmpeg_install
  cat >> "${BIN}/on-install" <<'EOF'
ln -sf /usr/bin/ffmpeg "${ROOT}/usr/bin/convert"
printf '%s\n' auto "${ROOT}/usr/bin/convert" convert.1 "${ROOT}/usr/share/man/convert.1" '' /usr/bin/ffmpeg 10 > "${DPKG_ADMINDIR}/alternatives/convert"
EOF
  APT_PACKAGES='ffmpeg' APT_CACHE_DIR="${CACHE}" run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  entries="$(tar -t -f "${CACHE}/installed.tar")"
  grep -qx "${DPKG_ADMINDIR#/}/alternatives/convert" <<< "${entries}"
  grep -qx "${ROOT#/}/usr/bin/convert" <<< "${entries}"
}

@test "warns but succeeds when saving the snapshot fails" {
  simulate_ffmpeg_install
  APT_PACKAGES='ffmpeg' APT_CACHE_DIR="${CACHE}" SUDO_FAIL_MATCH='tar -c' run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$output" == *'::warning::Saving the installed-files snapshot failed'* ]]
  [ ! -e "${CACHE}/installed.tar" ]
  [ ! -e "${CACHE}/installed.status" ]
}

@test "saves the files maintainer scripts generate during the install and restores them" {
  mkdir -p "${ROOT}/etc"
  echo image > "${ROOT}/etc/untouched.conf"
  simulate_ffmpeg_install
  cat >> "${BIN}/on-install" <<'EOF'
mkdir -p "${ROOT}/var/lib/texmf/web2c/pdftex"
echo format > "${ROOT}/var/lib/texmf/web2c/pdftex/pdflatex.fmt"
EOF
  APT_PACKAGES='ffmpeg' APT_CACHE_DIR="${CACHE}" run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  entries="$(tar -t -f "${CACHE}/installed.tar")"
  grep -qx "${ROOT#/}/var/lib/texmf/web2c/pdftex/pdflatex.fmt" <<< "${entries}"
  ! grep -q untouched.conf <<< "${entries}"
  [ "$(grep -cx "${ROOT#/}/usr/bin/ffmpeg" <<< "${entries}")" -eq 1 ]
  reset_runner
  APT_PACKAGES='ffmpeg' APT_CACHE_DIR="${CACHE}" run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Restored from the installed-files snapshot: ffmpeg'* ]]
  [ "$(cat "${ROOT}/var/lib/texmf/web2c/pdftex/pdflatex.fmt")" = format ]
}

@test "does not save the dpkg database or the cache directory as generated files" {
  simulate_ffmpeg_install
  APT_PACKAGES='ffmpeg' APT_CACHE_DIR="${CACHE}" APT_SNAPSHOT_SCAN_ROOTS="${ROOT} ${DPKG_ADMINDIR} ${CACHE}" run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  entries="$(tar -t -f "${CACHE}/installed.tar")"
  ! grep -qx "${DPKG_ADMINDIR#/}/status" <<< "${entries}"
  ! grep -q "${CACHE#/}/" <<< "${entries}"
}

@test "does not save generated files that are not world-readable" {
  simulate_ffmpeg_install
  cat >> "${BIN}/on-install" <<'EOF'
mkdir -p "${ROOT}/etc/ssl/private"
echo key > "${ROOT}/etc/ssl/private/snakeoil.key"
chmod 600 "${ROOT}/etc/ssl/private/snakeoil.key"
EOF
  APT_PACKAGES='ffmpeg' APT_CACHE_DIR="${CACHE}" run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  ! grep -q snakeoil.key <<< "$(tar -t -f "${CACHE}/installed.tar")"
}
