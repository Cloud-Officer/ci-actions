#!/usr/bin/env bash

# Installs PHP from the Ubuntu archive plus PHP_PACKAGES from a signed S3 apt repo, read with the job's AWS credentials.
#
# Usage (from a composite action step):
#   env:
#     PHP_VERSION: ${{ inputs.php-version }}            # empty or none reads PHP_VERSION_FILE (default .php-version)
#     PHP_VERSION_FILE: ${{ inputs.php-version-file }}
#     PHP_PACKAGES: ${{ inputs.php-packages }}
#     PHP_COVERAGE: ${{ inputs.php-coverage }}
#     PHP_INI_VALUES: ${{ inputs.php-ini-values }}
#     PHP_TOOLS: ${{ inputs.php-tools }}
#     PHP_APT_REPOSITORY: ${{ inputs.php-apt-repository }}
#     PHP_APT_KEY: ${{ inputs.php-apt-key }}
#   run: bash "${GITHUB_ACTION_PATH}/../_lib/php_apt_install.sh"

set -euo pipefail

S3AUTH_CONF="/etc/apt/s3auth.conf"
SOURCE_LIST="/etc/apt/sources.list.d/ci-actions-php.list"

function fail()
{
  echo "::error::$*" >&2
  exit 1
}

function trim()
{
  local value="${1}"

  value="${value#"${value%%[![:space:]]*}"}"
  echo "${value%"${value##*[![:space:]]}"}"
}

function php_minor_version()
{
  local version="${PHP_VERSION:-}"

  if [[ -z "${version}" || "${version}" == "none" ]]; then
    local file="${PHP_VERSION_FILE:-.php-version}"
    [[ -f "${file}" ]] || fail "php-packages needs a PHP version: set php-version or add ${file}"
    version="$(tr -d '[:space:]' < "${file}")"
  fi

  [[ "${version}" =~ ^([0-9]+\.[0-9]+)(\.[0-9]+)?$ ]] || fail "unsupported PHP version '${version}': expected major.minor or major.minor.patch"
  echo "${BASH_REMATCH[1]}"
}

function package_list()
{
  local line
  local package
  local -a words

  while IFS= read -r line; do
    read -r -a words <<< "${line%%#*}"

    for package in ${words[@]+"${words[@]}"}; do
      [[ "${package}" =~ ^[a-z0-9][a-z0-9.+-]+$ ]] || fail "invalid apt package name '${package}' in php-packages"
      echo "${package}"
    done
  done <<< "${PHP_PACKAGES:-}"
}

function coverage_package()
{
  case "${PHP_COVERAGE:-}" in
    pcov | xdebug) echo "php${1}-${PHP_COVERAGE}" ;;
    '' | none) ;;
    *) fail "unsupported php-coverage '${PHP_COVERAGE}' with php-packages: use pcov, xdebug or none" ;;
  esac
}

function disabled_coverage_modules()
{
  case "${PHP_COVERAGE:-}" in
    pcov) echo xdebug ;;
    xdebug) echo pcov ;;
    *) echo xdebug pcov ;;
  esac
}

function ini_lines()
{
  local pair
  local -a pairs

  IFS=',' read -r -a pairs <<< "${PHP_INI_VALUES:-}"

  for pair in ${pairs[@]+"${pairs[@]}"}; do
    pair="$(trim "${pair}")"
    [[ -z "${pair}" ]] && continue
    [[ "${pair}" == *=* ]] || fail "invalid php-ini-values entry '${pair}': expected key=value"
    echo "${pair}"
  done
}

function wants_composer()
{
  local tool
  local wanted=1
  local -a tools

  IFS=',' read -r -a tools <<< "${PHP_TOOLS:-}"

  for tool in ${tools[@]+"${tools[@]}"}; do
    tool="$(trim "${tool}")"

    case "${tool}" in
      '' | none) ;;
      composer) wanted=0 ;;
      *) fail "php-tools '${tool}' is not supported with php-packages: only composer is installed" ;;
    esac
  done

  return "${wanted}"
}

function bucket_region()
{
  local region

  region="$(curl --silent --head "https://${1}.s3.amazonaws.com/" | tr -d '\r' | awk 'tolower($1) == "x-amz-bucket-region:" { print $2 }')" || true
  echo "${region:-${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}}"
}

function cleanup()
{
  sudo rm -f "${S3AUTH_CONF}" "${SOURCE_LIST}"
}

function add_repository()
{
  local codename="${1}"
  local repository="${PHP_APT_REPOSITORY:?PHP_APT_REPOSITORY must be set}"
  local key="${PHP_APT_KEY:?PHP_APT_KEY must be set}"
  local keyring
  local bucket
  local tmp

  # apt-transport-s3 2.2 rejects s3://<bucket>.s3.amazonaws.com URIs.
  [[ "${repository}" =~ ^s3://([a-z0-9-]+)(/.*)?$ ]] || fail "php-apt-repository must be s3://<bucket>[/path] with a bucket name without dots, got '${repository}'"
  bucket="${BASH_REMATCH[1]}"

  if [[ -z "${AWS_ACCESS_KEY_ID:-}" || -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
    fail "php-packages reads ${repository} with AWS credentials: set aws-role-to-assume (GitHub OIDC, job permission id-token: write) or aws-access-key-id and aws-secret-access-key"
  fi

  command -v aws > /dev/null || fail "the aws CLI is required to fetch ${key}"
  tmp="$(mktemp -d)"
  aws s3 cp --only-show-errors "${key}" "${tmp}/key.asc" || fail "cannot read ${key}: check that the AWS role can read ${repository}"
  keyring="/usr/share/keyrings/$(basename "${key}")"
  sudo install -m 644 "${tmp}/key.asc" "${keyring}"
  rm -rf "${tmp}"

  sudo apt-get --yes --no-install-recommends install apt-transport-s3

  trap cleanup EXIT
  # Hosted runners have no instance metadata for apt-transport-s3 to fall back on, so keys and region go in s3auth.conf.
  printf "AccessKeyId = '%s'\nSecretAccessKey = '%s'\nToken = '%s'\nRegion = '%s'\n" \
    "${AWS_ACCESS_KEY_ID}" "${AWS_SECRET_ACCESS_KEY}" "${AWS_SESSION_TOKEN:-}" "$(bucket_region "${bucket}")" \
    | sudo install -m 600 /dev/stdin "${S3AUTH_CONF}"
  echo "deb [signed-by=${keyring}] ${repository} ${codename} main" | sudo tee "${SOURCE_LIST}" > /dev/null

  sudo apt-get --yes --error-on=any update || fail "cannot read the apt repository ${repository} (suite ${codename}): check the AWS role and that the repository publishes ${codename}"
}

function install_composer()
{
  local tmp
  local expected

  tmp="$(mktemp -d)"
  expected="$(curl --fail --silent --show-error --location https://composer.github.io/installer.sig)"
  curl --fail --silent --show-error --location https://getcomposer.org/installer --output "${tmp}/composer-setup.php"
  [[ "$(sha384sum "${tmp}/composer-setup.php" | cut -d ' ' -f 1)" == "${expected}" ]] || fail "the Composer installer checksum does not match composer.github.io/installer.sig"
  sudo php "${tmp}/composer-setup.php" --quiet --install-dir=/usr/local/bin --filename=composer
  rm -rf "${tmp}"
}

function main()
{
  local version
  local codename
  local module
  local ini
  local cli_version
  local list
  local composer=false
  local -a packages

  [[ "$(uname -s)" == "Linux" ]] || fail "php-packages needs an Ubuntu runner"
  # shellcheck disable=SC1090 # os-release is a runtime file
  codename="$(. "${OS_RELEASE_FILE:-/etc/os-release}" && echo "${VERSION_CODENAME:-}")"
  [[ -n "${codename}" ]] || fail "cannot read the Ubuntu codename from ${OS_RELEASE_FILE:-/etc/os-release}"

  version="$(php_minor_version)"
  list="$(package_list)"
  [[ -n "${list}" ]] || fail "php-packages lists no package"
  list="php${version}-cli ${list} $(coverage_package "${version}")"
  read -r -a packages <<< "${list//$'\n'/ }"
  ini="$(ini_lines)"

  if wants_composer; then
    composer=true
  fi

  sudo apt-get --yes update
  add_repository "${codename}"
  sudo apt-get --yes --no-install-recommends install "${packages[@]}"

  cli_version="$(dpkg-query --show --showformat='${Version}' "php${version}-cli")"
  [[ "${cli_version}" != *sury* ]] || fail "php${version}-cli ${cli_version} is not from the Ubuntu archive"

  sudo update-alternatives --set php "/usr/bin/php${version}"

  if [[ -n "$(coverage_package "${version}")" ]]; then
    sudo phpenmod -v "${version}" -s cli "${PHP_COVERAGE}"
  fi

  for module in $(disabled_coverage_modules); do
    if [[ -e "/etc/php/${version}/mods-available/${module}.ini" ]]; then
      sudo phpdismod -v "${version}" -s cli "${module}"
    fi
  done

  if [[ -n "${ini}" ]]; then
    echo "${ini}" | sudo tee "/etc/php/${version}/cli/conf.d/99-ci-actions.ini" > /dev/null
  fi

  if [[ "${composer}" == "true" ]]; then
    install_composer
  fi

  php -v
  php -m
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
