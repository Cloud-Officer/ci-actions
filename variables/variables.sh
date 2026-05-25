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

# Named helpers wrapping has_trigger / execute_*_trigger, kept so the script
# and its test suite can call them by intent rather than by raw keyword.
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
function execute_if_on_beta() { execute_if_trigger "beta-deploy" "$@"; }
function execute_if_on_rc() { execute_if_trigger "rc-deploy" "$@"; }
function execute_if_on_prod() { execute_if_trigger "prod-deploy" "$@"; }
function execute_if_on_macos() { execute_if_trigger "macos" "$@"; }
function execute_if_on_tvos() { execute_if_trigger "tvos" "$@"; }
function execute_if_skip_tests() { execute_if_trigger "skip-tests" "$@"; }
function execute_if_tests() { execute_unless_trigger "skip-tests" "$@"; }

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

# Helper function to add linter if config file/directory exists
# Usage: add_linter_if_file "LINTER_NAME" "config_file"
#        add_linter_if_dir "LINTER_NAME" "config_dir"
# Note: explicit `if`/`return 0` rather than `[ -f x ] && ...` so a missing
# config file is a no-op, not a non-zero return that aborts under `set -e`.
function add_linter_if_file()
{
  if [ -f "$2" ]; then
    LINTERS="${LINTERS} $1"
  fi
  return 0
}

function add_linter_if_dir()
{
  if [ -d "$2" ]; then
    LINTERS="${LINTERS} $1"
  fi
  return 0
}

# Resolve build identifiers and skip/deploy flags from the environment and the
# commit message, then export them to GITHUB_ENV / GITHUB_OUTPUT. Wrapped in a
# function so the test suite can source this file for its helpers without
# triggering git calls or writing to the runner files.
function main()
{
  # Fail fast: abort on any command error, unset variable, or failed pipe so a
  # shallow clone / network blip / missing tag surfaces instead of silently
  # producing empty build vars and skipped deploys. Scoped to main so sourcing
  # this file for the test suite does not change the caller's shell options.
  set -euo pipefail

  # set environment variables

  # Capture timestamp once to avoid race condition across second boundaries
  TIMESTAMP="$(date +%Y%m%d%H%M%S)"
  SHORT_COMMIT="$(git rev-parse --short HEAD)"
  SAFE_BRANCH="${GITHUB_REF:-/refs/heads/}"
  SAFE_BRANCH="${SAFE_BRANCH/refs\/heads\//}"
  SAFE_BRANCH="${SAFE_BRANCH/\//_}"
  MODIFIED_GITHUB_RUN_NUMBER=$(( ${GITHUB_RUN_NUMBER:-0} + 15000 ))
  export MODIFIED_GITHUB_RUN_NUMBER
  # Resolve the source ref and the raw commit message; only these differ
  # between a tag build, a PR-head build, and a branch build. BUILD_NAME /
  # BUILD_VERSION are then derived identically for all three.
  TAG=""
  # Anchored prefix match: a substring `grep tags` also matched branch refs that
  # merely contain "tags" (e.g. refs/heads/feature/tags-cleanup), routing them
  # through the tag path -> empty COMMIT_MESSAGE, slash-mangled BUILD_NAME, and a
  # spurious tag fetch.
  if [[ "${GITHUB_REF:-}" == refs/tags/* ]]; then
    TAG="${GITHUB_REF/refs\/tags\//}"
    SOURCE_REF="${TAG}"
    # Fetch over an authenticated HTTPS URL rather than `origin`. The checkout
    # step runs with persist-credentials:false, which strips the deploy key's
    # core.sshCommand while leaving origin pointed at git@github.com, so a plain
    # `git fetch origin` here fails with "Permission denied (publickey)" on tag
    # builds. GITHUB_TOKEN is exported by the action step for this purpose.
    git fetch --depth=1 "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" +refs/tags/*:refs/tags/*
    COMMIT_MESSAGE="$(git tag -l --format='%(contents:subject)' "${TAG}")"
  elif [ -n "${GITHUB_HEAD_REF:-}" ]; then
    SOURCE_REF="${GITHUB_HEAD_REF}"
    COMMIT_MESSAGE="$(git log --format=%B -n 1 "${SHORT_COMMIT}")"
  else
    SOURCE_REF="${SAFE_BRANCH}"
    COMMIT_MESSAGE="$(git log --format=%B -n 1 "${GITHUB_SHA:-HEAD}")"
  fi

  # Take only the first line: `git ... | head` would mask a git failure under
  # pipefail (and head closing the pipe trips pipefail too).
  COMMIT_MESSAGE="${COMMIT_MESSAGE%%$'\n'*}"

  BUILD_NAME="${SOURCE_REF}-${SHORT_COMMIT}-${TIMESTAMP}-${MODIFIED_GITHUB_RUN_NUMBER}"
  BUILD_VERSION="${SOURCE_REF}-${MODIFIED_GITHUB_RUN_NUMBER}-${TIMESTAMP}"
  export BUILD_NAME BUILD_VERSION COMMIT_MESSAGE

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
  add_linter_if_file "MARKDOWNLINT"  ".markdownlint-cli2.yaml"
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
  if find . -maxdepth 3 \( \
     -name "Dockerfile*" -o -name "*.tf" -o \
     -name ".cfnlintrc" -o -name ".hadolint.yaml" -o \
     -name "package.json" -o -name "package-lock.json" -o \
     -name "yarn.lock" -o -name "pnpm-lock.yaml" -o \
     -name "go.sum" -o -name "requirements.txt" -o \
     -name "Pipfile.lock" -o -name "poetry.lock" -o \
     -name "Gemfile.lock" -o -name "composer.lock" -o \
     -name "pom.xml" -o -name "build.gradle" -o -name "build.gradle.kts" -o \
     -name "Cargo.lock" -o -name "Package.resolved" \
     \) -print -quit 2>/dev/null | grep -q .; then
    LINTERS="${LINTERS} TRIVY"
  fi
  add_linter_if_file "YAMLLINT"      ".yamllint.yml"

  for github in BUILD_NAME BUILD_VERSION COMMIT_MESSAGE MODIFIED_GITHUB_RUN_NUMBER DEPLOY_ON_BETA DEPLOY_ON_RC DEPLOY_ON_PROD DEPLOY_MACOS DEPLOY_TVOS DEPLOY_OPTIONS SKIP_LICENSES SKIP_LINTERS SKIP_TESTS UPDATE_PACKAGES LINTERS; do
    echo "${github}=${!github}" >> "${GITHUB_ENV}"
    echo "${github}=${!github}" >> "${GITHUB_OUTPUT}"
  done
}

# Only run main when executed directly (via the action's shebang invocation),
# not when sourced by the bats test suite.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
