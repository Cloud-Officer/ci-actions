#!/usr/bin/env bash

# Generic function to check for commit message triggers
# Usage: has_trigger "keyword"
function has_trigger()
{
  echo "${COMMIT_MESSAGE}" | grep -iF "#$1" &> /dev/null
}

# Generic function to execute command if trigger is present
# Usage: execute_if_trigger "keyword" command args...
function execute_if_trigger()
{
  local trigger="$1"
  shift
  if has_trigger "${trigger}"; then
    "$@"
  fi
}

# Generic function to execute command if trigger is NOT present
# Usage: execute_unless_trigger "keyword" command args...
function execute_unless_trigger()
{
  local trigger="$1"
  shift
  if ! has_trigger "${trigger}"; then
    "$@"
  fi
}

# Convenience aliases for backward compatibility
function on_beta() { has_trigger "beta-deploy"; }
function on_rc() { has_trigger "rc-deploy"; }
function on_prod() { has_trigger "prod-deploy"; }
function on_macos() { has_trigger "macos"; }
function on_tvos() { has_trigger "tvos"; }
function deploy_options() { has_trigger "deploy-options"; }
function skip_all() { has_trigger "skip-all"; }
function skip_licenses() { has_trigger "skip-licenses"; }
function skip_linters() { has_trigger "skip-linters"; }
function skip_tests() { has_trigger "skip-tests"; }
function update_packages() { has_trigger "update-packages"; }

# Convenience wrapper functions for backward compatibility
function execute_if_on_beta() { execute_if_trigger "beta-deploy" "$@"; }
function execute_if_on_rc() { execute_if_trigger "rc-deploy" "$@"; }
function execute_if_on_prod() { execute_if_trigger "prod-deploy" "$@"; }
function execute_if_on_macos() { execute_if_trigger "macos" "$@"; }
function execute_if_on_tvos() { execute_if_trigger "tvos" "$@"; }
function execute_if_skip_tests() { execute_if_trigger "skip-tests" "$@"; }
function execute_if_tests() { execute_unless_trigger "skip-tests" "$@"; }

# set environment variables

# Capture timestamp once to avoid race condition across second boundaries
TIMESTAMP="$(date +%Y%m%d%H%M%S)"
SHORT_COMMIT="$(git rev-parse --short HEAD)"
SAFE_BRANCH="${GITHUB_REF/refs\/heads\//}"
SAFE_BRANCH="${SAFE_BRANCH/\//_}"
MODIFIED_GITHUB_RUN_NUMBER=$((GITHUB_RUN_NUMBER + 15000))
export MODIFIED_GITHUB_RUN_NUMBER

if echo "${GITHUB_REF}" | grep tags &> /dev/null; then
  TAG="${GITHUB_REF/refs\/tags\//}"
  BUILD_NAME="${TAG}-${SHORT_COMMIT}-${TIMESTAMP}-${MODIFIED_GITHUB_RUN_NUMBER}"
  export BUILD_NAME
  BUILD_VERSION="${TAG}-${MODIFIED_GITHUB_RUN_NUMBER}-${TIMESTAMP}"
  export BUILD_VERSION
  git fetch --depth=1 origin +refs/tags/*:refs/tags/*
  COMMIT_MESSAGE="$(git tag -l --format='%(contents:subject)' "${TAG}" | head -n 1)"
  export COMMIT_MESSAGE
elif [ -n "${GITHUB_HEAD_REF}" ]; then
  BUILD_NAME="${GITHUB_HEAD_REF}-${SHORT_COMMIT}-${TIMESTAMP}-${MODIFIED_GITHUB_RUN_NUMBER}"
  export BUILD_NAME
  BUILD_VERSION="${GITHUB_HEAD_REF}-${MODIFIED_GITHUB_RUN_NUMBER}-${TIMESTAMP}"
  export BUILD_VERSION
  COMMIT_MESSAGE="$(git log --format=%B -n 1 "${SHORT_COMMIT}" | head -n 1)"
  export COMMIT_MESSAGE
else
  BUILD_NAME="${SAFE_BRANCH}-${SHORT_COMMIT}-${TIMESTAMP}-${MODIFIED_GITHUB_RUN_NUMBER}"
  export BUILD_NAME
  BUILD_VERSION="${SAFE_BRANCH}-${MODIFIED_GITHUB_RUN_NUMBER}-${TIMESTAMP}"
  export BUILD_VERSION
  COMMIT_MESSAGE="$(git log --format=%B -n 1 "${GITHUB_SHA}" | head -n 1)"
  export COMMIT_MESSAGE
fi

# Helper function to set boolean flag from trigger
# Usage: set_flag_from_trigger VAR_NAME "trigger-keyword"
function set_flag_from_trigger()
{
  local var_name="$1"
  local trigger="$2"
  if has_trigger "${trigger}"; then
    eval "export ${var_name}=1"
  else
    eval "export ${var_name}=0"
  fi
}

# Set deployment and skip flags from commit message triggers
set_flag_from_trigger DEPLOY_ON_BETA "beta-deploy"
set_flag_from_trigger DEPLOY_ON_RC "rc-deploy"
set_flag_from_trigger DEPLOY_MACOS "macos"
set_flag_from_trigger DEPLOY_TVOS "tvos"
set_flag_from_trigger SKIP_LICENSES "skip-licenses"
set_flag_from_trigger SKIP_LINTERS "skip-linters"
set_flag_from_trigger SKIP_TESTS "skip-tests"
set_flag_from_trigger UPDATE_PACKAGES "update-packages"

# DEPLOY_ON_PROD requires both trigger and tag
DEPLOY_ON_PROD=0
if on_prod && [ "${TAG}" != "" ]; then
  DEPLOY_ON_PROD=1
fi
export DEPLOY_ON_PROD

# DEPLOY_OPTIONS extracts value from trigger
DEPLOY_OPTIONS=""
if deploy_options; then
  DEPLOY_OPTIONS="$(echo "${COMMIT_MESSAGE}" | sed -n 's/.*#deploy-options=\([^ ]*\).*/\1/p')"
fi
export DEPLOY_OPTIONS

# Handle #skip-all trigger (override individual skip flags)
if skip_all; then
  export SKIP_LICENSES=1
  export SKIP_LINTERS=1
  export SKIP_TESTS=1
fi

# Helper function to add linter if config file/directory exists
# Usage: add_linter_if_file "LINTER_NAME" "config_file"
#        add_linter_if_dir "LINTER_NAME" "config_dir"
function add_linter_if_file()
{
  [ -f "$2" ] && LINTERS="${LINTERS} $1"
}

function add_linter_if_dir()
{
  [ -d "$2" ] && LINTERS="${LINTERS} $1"
}

# Auto-detect linters based on config file presence
LINTERS=""
add_linter_if_dir  "ACTIONLINT"    ".github/workflows"
add_linter_if_file "BANDIT"        ".bandit"
add_linter_if_file "CFNLINT"       ".cfnlintrc"
add_linter_if_file "ESLINT"        ".eslintrc.json"
add_linter_if_file "FLAKE8"        ".flake8"
add_linter_if_file "GOLANGCI"      ".golangci.yml"
add_linter_if_file "HADOLINT"      ".hadolint.yaml"
add_linter_if_file "KTLINT"        ".editorconfig"
add_linter_if_file "MARKDOWNLINT"  ".markdownlint.yml"
add_linter_if_file "PHPCS"         ".php-cs-fixer.dist.php"
add_linter_if_file "PHPSTAN"       "phpstan.neon"
add_linter_if_file "PMD"           ".pmd.xml"
add_linter_if_file "PROTOLINT"     ".protolint.yaml"
add_linter_if_file "RUBOCOP"       ".rubocop.yml"
add_linter_if_file "SEMGREP"       ".semgrepignore"
add_linter_if_file "SHELLCHECK"    ".shellcheckrc"
add_linter_if_file "SWIFTLINT"     ".swiftlint.yml"
# TRIVY - enabled when IaC files or package manager files are present
if [ -f ".cfnlintrc" ] || [ -f ".hadolint.yaml" ] || \
   compgen -G "*.tf" > /dev/null 2>&1 || \
   [ -f "package-lock.json" ] || [ -f "yarn.lock" ] || [ -f "pnpm-lock.yaml" ] || \
   [ -f "go.sum" ] || [ -f "requirements.txt" ] || [ -f "Pipfile.lock" ] || \
   [ -f "poetry.lock" ] || [ -f "Gemfile.lock" ] || [ -f "composer.lock" ] || \
   [ -f "pom.xml" ] || [ -f "build.gradle" ] || [ -f "build.gradle.kts" ] || \
   [ -f "Cargo.lock" ] || [ -f "Package.resolved" ]; then
  LINTERS="${LINTERS} TRIVY"
fi
add_linter_if_file "YAMLLINT"      ".yamllint.yml"

for github in BUILD_NAME BUILD_VERSION COMMIT_MESSAGE MODIFIED_GITHUB_RUN_NUMBER DEPLOY_ON_BETA DEPLOY_ON_RC DEPLOY_ON_PROD DEPLOY_MACOS DEPLOY_TVOS DEPLOY_OPTIONS SKIP_LICENSES SKIP_LINTERS SKIP_TESTS UPDATE_PACKAGES LINTERS; do
  echo "${github}=${!github}" >> "${GITHUB_ENV}"
  echo "${github}=${!github}" >> "${GITHUB_OUTPUT}"
done
