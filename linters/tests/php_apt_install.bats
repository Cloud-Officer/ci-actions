#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../_lib/php_apt_install.sh"
  BIN="$(mktemp -d)"
  LOG="${BIN}/sudo.log"
  export OS_RELEASE_FILE="${BIN}/os-release"
  echo 'VERSION_CODENAME=resolute' > "${OS_RELEASE_FILE}"

  stub sudo "printf '%s|' \"\$@\" >> '${LOG}'; printf '\n' >> '${LOG}'
if [[ \"\$1\" == tee || \" \$* \" == *\" /dev/stdin \"* ]]; then cat >> '${LOG}'; fi
if [ -n \"\${SUDO_FAIL_ON:-}\" ] && [[ \" \$* \" == *\" \${SUDO_FAIL_ON} \"* ]]; then exit 100; fi"
  stub uname 'echo Linux'
  stub curl "printf 'HTTP/1.1 403 Forbidden\r\nx-amz-bucket-region: us-east-2\r\n'"
  stub aws "[ -z \"\${AWS_FAIL:-}\" ] || exit 1; echo key > \"\$5\""
  stub dpkg-query "echo \"\${CLI_VERSION:-8.5.4-0ubuntu1.5}\""
  stub php 'echo php "$@"'
  export PATH="${BIN}:${PATH}"
  export PHP_VERSION=8.5.12 PHP_PACKAGES='php8.5-intl php8.5-grpc' PHP_COVERAGE=pcov PHP_INI_VALUES='memory_limit=4G' PHP_TOOLS=''
  export PHP_APT_REPOSITORY='s3://ugm-builds/apt' PHP_APT_KEY='s3://ugm-builds/apt/ugroupmedia-apt.asc'
  export AWS_ACCESS_KEY_ID=AKIA AWS_SECRET_ACCESS_KEY=secret/+= AWS_SESSION_TOKEN=token
}

teardown() {
  rm -rf "${BIN}"
}

stub() {
  printf '#!/usr/bin/env bash\n%s\n' "$2" > "${BIN}/$1"
  chmod +x "${BIN}/$1"
}

in_script() {
  run bash -c "source '${SCRIPT}'; $1"
}

@test "reduces the PHP version to major.minor" {
  in_script 'php_minor_version'
  [ "$status" -eq 0 ]
  [ "$output" = '8.5' ]
}

@test "reads the version file when php-version is none or empty" {
  echo '8.5' > "${BIN}/.php-version"
  PHP_VERSION=none PHP_VERSION_FILE="${BIN}/.php-version" in_script 'php_minor_version'
  [ "$output" = '8.5' ]
  PHP_VERSION='' PHP_VERSION_FILE="${BIN}/.php-version" in_script 'php_minor_version'
  [ "$output" = '8.5' ]
}

@test "fails without a PHP version" {
  PHP_VERSION='' PHP_VERSION_FILE="${BIN}/missing" in_script 'php_minor_version'
  [ "$status" -eq 1 ]
  [[ "$output" == *'::error::php-packages needs a PHP version'* ]]
}

@test "rejects a PHP version that is not numeric" {
  PHP_VERSION=latest in_script 'php_minor_version'
  [ "$status" -eq 1 ]
  [[ "$output" == *"unsupported PHP version 'latest'"* ]]
}

@test "lists packages across lines and drops comments" {
  PHP_PACKAGES=$'# extensions\nphp8.5-amqp php8.5-apcu # inline\n\nphp8.5-zip' in_script 'package_list'
  [ "$status" -eq 0 ]
  [ "$output" = $'php8.5-amqp\nphp8.5-apcu\nphp8.5-zip' ]
}

@test "rejects a package that looks like an apt option" {
  PHP_PACKAGES='php8.5-zip -o=APT::Get::AllowUnauthenticated=true' in_script 'package_list'
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid apt package name '-o=APT"* ]]
}

@test "maps the coverage driver to its package" {
  PHP_COVERAGE=pcov in_script 'coverage_package 8.5'
  [ "$output" = 'php8.5-pcov' ]
  PHP_COVERAGE=xdebug in_script 'coverage_package 8.5'
  [ "$output" = 'php8.5-xdebug' ]
  PHP_COVERAGE=none in_script 'coverage_package 8.5'
  [ "$output" = '' ]
  PHP_COVERAGE=pcov in_script 'disabled_coverage_modules'
  [ "$output" = 'xdebug' ]
}

@test "rejects an unknown coverage driver" {
  PHP_COVERAGE=phpdbg in_script 'coverage_package 8.5'
  [ "$status" -eq 1 ]
}

@test "splits ini values on commas" {
  PHP_INI_VALUES='memory_limit=4G, error_reporting=E_ALL & ~E_DEPRECATED ,' in_script 'ini_lines'
  [ "$status" -eq 0 ]
  [ "$output" = $'memory_limit=4G\nerror_reporting=E_ALL & ~E_DEPRECATED' ]
}

@test "rejects an ini value without a key" {
  PHP_INI_VALUES='memory_limit' in_script 'ini_lines'
  [ "$status" -eq 1 ]
}

@test "installs composer only when php-tools asks for it" {
  PHP_TOOLS='composer' in_script 'wants_composer'
  [ "$status" -eq 0 ]
  PHP_TOOLS='' in_script 'wants_composer'
  [ "$status" -eq 1 ]
  PHP_TOOLS='composer, phpunit' in_script 'wants_composer'
  [ "$status" -eq 1 ]
  [[ "$output" == *"php-tools 'phpunit' is not supported"* ]]
}

@test "adds the S3 repository then installs PHP from the Ubuntu archive" {
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  grep -qx 'apt-get|--yes|--no-install-recommends|install|apt-transport-s3|' "${LOG}"
  grep -qx "install|-m|644|.*|/usr/share/keyrings/ugroupmedia-apt.asc|" "${LOG}"
  grep -qx "AccessKeyId = 'AKIA'" "${LOG}"
  grep -qx "SecretAccessKey = 'secret/+='" "${LOG}"
  grep -qx "Token = 'token'" "${LOG}"
  grep -qx "Region = 'us-east-2'" "${LOG}"
  grep -qx 'deb \[signed-by=/usr/share/keyrings/ugroupmedia-apt.asc\] s3://ugm-builds/apt resolute main' "${LOG}"
  grep -qx 'apt-get|--yes|--error-on=any|update|' "${LOG}"
  grep -qx 'apt-get|--yes|--no-install-recommends|install|php8.5-cli|php8.5-intl|php8.5-grpc|php8.5-pcov|' "${LOG}"
  grep -qx 'memory_limit=4G' "${LOG}"
  grep -qx 'rm|-f|/etc/apt/s3auth.conf|/etc/apt/sources.list.d/ci-actions-php.list|' "${LOG}"
  [[ "$output" == *'php -v'* ]]
  [[ "$output" == *'php -m'* ]]
}

@test "fails before touching apt without AWS credentials" {
  AWS_ACCESS_KEY_ID='' run bash "${SCRIPT}"
  [ "$status" -eq 1 ]
  [[ "$output" == *'::error::php-packages reads s3://ugm-builds/apt with AWS credentials'* ]]
  run grep -q 'apt-transport-s3' "${LOG}"
  [ "$status" -ne 0 ]
}

@test "fails clearly when the key cannot be read" {
  AWS_FAIL=1 run bash "${SCRIPT}"
  [ "$status" -eq 1 ]
  [[ "$output" == *'::error::cannot read s3://ugm-builds/apt/ugroupmedia-apt.asc'* ]]
}

@test "fails clearly when the repository cannot be read" {
  SUDO_FAIL_ON='--error-on=any' run bash "${SCRIPT}"
  [ "$status" -eq 1 ]
  [[ "$output" == *'::error::cannot read the apt repository s3://ugm-builds/apt (suite resolute)'* ]]
  run grep -q 'php8.5-cli' "${LOG}"
  [ "$status" -ne 0 ]
  grep -qx 'rm|-f|/etc/apt/s3auth.conf|/etc/apt/sources.list.d/ci-actions-php.list|' "${LOG}"
}

@test "rejects a bucket name with dots" {
  PHP_APT_REPOSITORY='s3://ugm-builds.s3.amazonaws.com/apt' run bash "${SCRIPT}"
  [ "$status" -eq 1 ]
  [[ "$output" == *'bucket name without dots'* ]]
}

@test "fails when php comes from a third-party build" {
  CLI_VERSION='8.5.12-1+ubuntu26.04.1+deb.sury.org+1' run bash "${SCRIPT}"
  [ "$status" -eq 1 ]
  [[ "$output" == *'is not from the Ubuntu archive'* ]]
}

@test "fails on a runner that is not Linux" {
  stub uname 'echo Darwin'
  run bash "${SCRIPT}"
  [ "$status" -eq 1 ]
  [ ! -e "${LOG}" ]
}

@test "runs the Composer installer as the runner user and only copies the binary as root" {
  stub curl 'for arg in "$@"; do prev="${out:-}"; out="${arg}"; [ "${prev}" = --output ] && { echo installer > "${arg}"; exit 0; }; done; echo installer | sha384sum | cut -d " " -f 1'
  stub php 'for arg in "$@"; do case "${arg}" in --install-dir=*) dir="${arg#--install-dir=}" ;; esac; done; echo "${USER:-runner}" > "${BIN}/php-user"; touch "${dir}/composer"'
  in_script 'install_composer'
  [ "$status" -eq 0 ]
  ! grep -q '^php|' "${LOG}"
  grep -q '^install|-m|0755|.*/composer|/usr/local/bin/composer|$' "${LOG}"
}
