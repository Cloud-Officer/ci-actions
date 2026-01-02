#!/usr/bin/env bash
#set -ex

function on_beta()
{
  echo "${COMMIT_MESSAGE}" | grep -iF '#beta-deploy' &> /dev/null
}

function on_rc()
{
  echo "${COMMIT_MESSAGE}" | grep -iF '#rc-deploy' &> /dev/null
}

function on_prod()
{
  echo "${COMMIT_MESSAGE}" | grep -iF '#prod-deploy' &> /dev/null
}

function on_macos()
{
  echo "${COMMIT_MESSAGE}" | grep -iF '#macos' &> /dev/null
}

function on_tvos()
{
  echo "${COMMIT_MESSAGE}" | grep -iF '#tvos' &> /dev/null
}

function deploy_options()
{
  echo "${COMMIT_MESSAGE}" | grep -iF '#deploy-options' &> /dev/null
}

function skip_all()
{
  echo "${COMMIT_MESSAGE}" | grep -iF '#skip-all' &> /dev/null
}

function skip_licenses()
{
  echo "${COMMIT_MESSAGE}" | grep -iF '#skip-licenses' &> /dev/null
}

function skip_linters()
{
  echo "${COMMIT_MESSAGE}" | grep -iF '#skip-linters' &> /dev/null
}

function skip_tests()
{
  echo "${COMMIT_MESSAGE}" | grep -iF '#skip-tests' &> /dev/null
}

function update_packages()
{
  echo "${COMMIT_MESSAGE}" | grep -iF '#update-packages' &> /dev/null
}

function execute_if_on_beta()
{
  if on_beta; then
    "$@"
  fi
}

function execute_if_on_rc()
{
  if on_rc; then
    "$@"
  fi
}

function execute_if_on_prod()
{
  if on_prod; then
    "$@"
  fi
}

function execute_if_on_macos()
{
  if on_macos; then
    "$@"
  fi
}

function execute_if_on_tvos()
{
  if on_tvos; then
    "$@"
  fi
}

function execute_if_skip_tests()
{
  if skip_tests; then
    "$@"
  fi
}

function execute_if_tests()
{
  if ! skip_tests; then
    "$@"
  fi
}

# set environment variables

SHORT_COMMIT="$(git rev-parse --short HEAD)"
SAFE_BRANCH="${GITHUB_REF/refs\/heads\//}"
SAFE_BRANCH="${SAFE_BRANCH/\//_}"
MODIFIED_GITHUB_RUN_NUMBER=$((GITHUB_RUN_NUMBER + 15000))
export MODIFIED_GITHUB_RUN_NUMBER

if echo "${GITHUB_REF}" | grep tags &> /dev/null; then
  TAG="${GITHUB_REF/refs\/tags\//}"
  BUILD_NAME="${TAG}-${SHORT_COMMIT}-$(date +"%Y%m%d%H%M%S")-${MODIFIED_GITHUB_RUN_NUMBER}"
  export BUILD_NAME
  BUILD_VERSION="${TAG}-${MODIFIED_GITHUB_RUN_NUMBER}-$(date +"%Y%m%d%H%M%S")"
  export BUILD_VERSION
  git fetch --depth=1 origin +refs/tags/*:refs/tags/*
  COMMIT_MESSAGE="$(git tag -l --format='%(contents:subject)' "${TAG}" | head -n 1)"
  export COMMIT_MESSAGE
elif [ -n "${GITHUB_HEAD_REF}" ]; then
  BUILD_NAME="${GITHUB_HEAD_REF}-${SHORT_COMMIT}-$(date +"%Y%m%d%H%M%S")-${MODIFIED_GITHUB_RUN_NUMBER}"
  export BUILD_NAME
  BUILD_VERSION="${GITHUB_HEAD_REF}-${MODIFIED_GITHUB_RUN_NUMBER}-$(date +"%Y%m%d%H%M%S")"
  export BUILD_VERSION
  COMMIT_MESSAGE="$(git log --format=%B -n 1 "${SHORT_COMMIT}" | head -n 1)"
  export COMMIT_MESSAGE
else
  BUILD_NAME="${SAFE_BRANCH}-${SHORT_COMMIT}-$(date +"%Y%m%d%H%M%S")-${MODIFIED_GITHUB_RUN_NUMBER}"
  export BUILD_NAME
  BUILD_VERSION="${SAFE_BRANCH}-${MODIFIED_GITHUB_RUN_NUMBER}-$(date +"%Y%m%d%H%M%S")"
  export BUILD_VERSION
  COMMIT_MESSAGE="$(git log --format=%B -n 1 "${GITHUB_SHA}" | head -n 1)"
  export COMMIT_MESSAGE
fi

DEPLOY_ON_BETA=0

if on_beta; then
  DEPLOY_ON_BETA=1
fi

export DEPLOY_ON_BETA

DEPLOY_ON_RC=0

if on_rc; then
  DEPLOY_ON_RC=1
fi

export DEPLOY_ON_RC

DEPLOY_ON_PROD=0

if on_prod && [ "${TAG}" != "" ]; then
  DEPLOY_ON_PROD=1
fi

export DEPLOY_ON_PROD

DEPLOY_MACOS=0

if on_macos; then
  DEPLOY_MACOS=1
fi

export DEPLOY_MACOS

DEPLOY_TVOS=0

if on_tvos; then
  DEPLOY_TVOS=1
fi

export DEPLOY_TVOS

DEPLOY_OPTIONS=""

if deploy_options; then
  DEPLOY_OPTIONS="$(echo "${COMMIT_MESSAGE}" | sed -n 's/.*#deploy-options=\([^ ]*\).*/\1/p')"
fi

export DEPLOY_OPTIONS

SKIP_LICENSES=0

if skip_licenses; then
  SKIP_LICENSES=1
fi

export SKIP_LICENSES

SKIP_LINTERS=0

if skip_linters; then
  SKIP_LINTERS=1
fi

export SKIP_LINTERS

SKIP_TESTS=0

if skip_tests; then
  SKIP_TESTS=1
fi

export SKIP_TESTS

if skip_all; then
  SKIP_LICENSES=1
  SKIP_LINTERS=1
  SKIP_TESTS=1
fi

UPDATE_PACKAGES=0

if update_packages; then
  UPDATE_PACKAGES=1
fi

export UPDATE_PACKAGES

LINTERS=""

if [ -d .github/workflows ]; then
  LINTERS="${LINTERS} ACTIONLINT"
fi

if [ -f .bandit ]; then
  LINTERS="${LINTERS} BANDIT"
fi

if [ -f .eslintrc.json ]; then
  LINTERS="${LINTERS} ESLINT"
fi

if [ -f .flake8 ]; then
  LINTERS="${LINTERS} FLAKE8"
fi

if [ -f .golangci.yml ]; then
  LINTERS="${LINTERS} GOLANGCI"
fi

if [ -f .hadolint.yaml ]; then
  LINTERS="${LINTERS} HADOLINT"
fi

if [ -f .editorconfig ]; then
  LINTERS="${LINTERS} KTLINT"
fi

if [ -f .markdownlint.yml ]; then
  LINTERS="${LINTERS} MARKDOWNLINT"
fi

if [  -f .php-cs-fixer.dist.php ]; then
  LINTERS="${LINTERS} PHPCS"
fi

if [  -f phpstan.neon ]; then
  LINTERS="${LINTERS} PHPSTAN"
fi

if [ -f .pmd.xml ]; then
  LINTERS="${LINTERS} PMD"
fi

if [ -f .protolint.yaml ]; then
  LINTERS="${LINTERS} PROTOLINT"
fi

if [ -f .rubocop.yml ]; then
  LINTERS="${LINTERS} RUBOCOP"
fi

if [ -f .semgrepignore ]; then
  LINTERS="${LINTERS} SEMGREP"
fi

if [ -f .shellcheckrc ]; then
  LINTERS="${LINTERS} SHELLCHECK"
fi

if [ -f .swiftlint.yml ]; then
  LINTERS="${LINTERS} SWIFTLINT"
fi

if [ -f .yamllint.yml ]; then
  LINTERS="${LINTERS} YAMLLINT"
fi

if find . -type f \( \
    -name "*.cpp" -o -name "*.c++" -o -name "*.cxx" -o -name "*.hpp" -o -name "*.hh" -o -name "*.h++" -o -name "*.hxx" -o -name "*.c" -o -name "*.cc" -o -name "*.h" \
    -o -name "*.sln" -o -name "*.csproj" -o -name "*.cs" -o -name "*.cshtml" -o -name "*.xaml" \
    -o -name "*.go" \
    -o -name "*.java" \
    -o -name "*.kt" \
    -o -name "*.js" -o -name "*.jsx" -o -name "*.mjs" -o -name "*.es" -o -name "*.es6" -o -name "*.htm" -o -name "*.html" -o -name "*.xhtm" -o -name "*.xhtml" -o -name "*.vue" -o -name "*.hbs" -o -name "*.ejs" -o -name "*.njk" -o -name "*.json" -o -name "*.yaml" -o -name "*.yml" -o -name "*.raml" -o -name "*.xml" \
    -o -name "*.py" \
    -o -name "*.rb" -o -name "*.erb" -o -name "*.gemspec" -o -name "Gemfile" \
    -o -name "*.swift" \
    -o -name "*.ts" -o -name "*.tsx" -o -name "*.mts" -o -name "*.cts" \
    \) | grep -q .; then
  LINTERS="${LINTERS} CODEQL"
fi

for github in BUILD_NAME BUILD_VERSION COMMIT_MESSAGE MODIFIED_GITHUB_RUN_NUMBER DEPLOY_ON_BETA DEPLOY_ON_RC DEPLOY_ON_PROD DEPLOY_MACOS DEPLOY_TVOS DEPLOY_OPTIONS SKIP_LICENSES SKIP_LINTERS SKIP_TESTS UPDATE_PACKAGES LINTERS; do
  echo "${github}=${!github}" >> "${GITHUB_ENV}"
  echo "${github}=${!github}" >> "${GITHUB_OUTPUT}"
done
