#!/usr/bin/env bash

# Generic function to check for commit message triggers
# Usage: has_trigger "keyword"
function has_trigger()
{
  [ -n "$1" ] || return 1
  echo "${COMMIT_MESSAGE}" | grep -iF "#$1" &> /dev/null
}

# The only place trigger keywords are spelled: OUTPUT_VARIABLE=keyword.
TRIGGER_FLAGS=(
  "DEPLOY_ON_BETA=beta-deploy"
  "DEPLOY_ON_RC=rc-deploy"
  "DEPLOY_ON_PROD=prod-deploy"
  "DEPLOY_MACOS=macos"
  "DEPLOY_TVOS=tvos"
  "DEPLOY_OPTIONS=deploy-options"
  "SKIP_ALL=skip-all"
  "SKIP_LICENSES=skip-licenses"
  "SKIP_LINTERS=skip-linters"
  "SKIP_TESTS=skip-tests"
  "UPDATE_PACKAGES=update-packages"
)

# Usage: trigger_keyword VAR_NAME
function trigger_keyword()
{
  local pair
  for pair in "${TRIGGER_FLAGS[@]}"; do
    if [[ "${pair%%=*}" == "${1}" ]]; then
      printf '%s\n' "${pair#*=}"
      return 0
    fi
  done
  echo "::error::unknown trigger flag '$1'" >&2
  return 1
}

function on_beta() { has_trigger "$(trigger_keyword DEPLOY_ON_BETA)"; }
function on_rc() { has_trigger "$(trigger_keyword DEPLOY_ON_RC)"; }
function on_prod() { has_trigger "$(trigger_keyword DEPLOY_ON_PROD)"; }
function on_macos() { has_trigger "$(trigger_keyword DEPLOY_MACOS)"; }
function on_tvos() { has_trigger "$(trigger_keyword DEPLOY_TVOS)"; }
function deploy_options() { has_trigger "$(trigger_keyword DEPLOY_OPTIONS)"; }
function skip_all() { has_trigger "$(trigger_keyword SKIP_ALL)"; }
function skip_licenses() { has_trigger "$(trigger_keyword SKIP_LICENSES)"; }
function skip_linters() { has_trigger "$(trigger_keyword SKIP_LINTERS)"; }
function skip_tests() { has_trigger "$(trigger_keyword SKIP_TESTS)"; }
function update_packages() { has_trigger "$(trigger_keyword UPDATE_PACKAGES)"; }

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

# Succeeds when an IaC marker, package.json or a TRIVY_LOCK_FILES entry exists outside submodules.
function detect_trivy()
{
  local lib_dir
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../linters/_lib"
  # shellcheck source=/dev/null
  source "${lib_dir}/lock_files.sh"
  # shellcheck source=/dev/null
  source "${lib_dir}/submodule_paths.sh"

  local find_args=(
    -name "Dockerfile*" -o -name "*.tf" -o
    -name ".cfnlintrc" -o -name ".hadolint.yaml" -o
    -name "package.json"
  )
  local lock_file
  for lock_file in "${TRIVY_LOCK_FILES[@]}"; do
    find_args+=( -o -name "${lock_file}" )
  done

  local prune_args=()
  local path
  while IFS= read -r path; do
    if [ -n "${path}" ]; then
      prune_args+=("-path" "./${path}" "-prune" "-o")
    fi
  done < <(submodule_paths)

  find . "${prune_args[@]}" '(' "${find_args[@]}" ')' -print -quit 2>/dev/null | grep -q .
}

# Exports build identifiers, trigger flags and LINTERS to GITHUB_ENV and GITHUB_OUTPUT.
function main()
{
  set -euo pipefail

  # Capture timestamp once to avoid race condition across second boundaries
  TIMESTAMP="$(date +%Y%m%d%H%M%S)"
  SHORT_COMMIT="$(git rev-parse --short HEAD)"
  SAFE_BRANCH="${GITHUB_REF:-/refs/heads/}"
  SAFE_BRANCH="${SAFE_BRANCH/refs\/heads\//}"
  SAFE_BRANCH="${SAFE_BRANCH//\//_}"
  MODIFIED_GITHUB_RUN_NUMBER=$(( ${GITHUB_RUN_NUMBER:-0} + 15000 ))
  export MODIFIED_GITHUB_RUN_NUMBER
  TAG=""
  if [[ "${GITHUB_REF:-}" == refs/tags/* ]]; then
    TAG="${GITHUB_REF/refs\/tags\//}"
    SOURCE_REF="${TAG}"
    # persist-credentials:false leaves origin on SSH with no key; fetch over HTTPS with GITHUB_TOKEN.
    git fetch --depth=1 "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" +refs/tags/*:refs/tags/*
    COMMIT_MESSAGE="$(git tag -l --format='%(contents:subject)' "${TAG}")"
  elif [ -n "${GITHUB_HEAD_REF:-}" ]; then
    SOURCE_REF="${GITHUB_HEAD_REF}"
    COMMIT_MESSAGE="$(git log --format=%B -n 1 "${SHORT_COMMIT}")"
  else
    SOURCE_REF="${SAFE_BRANCH}"
    COMMIT_MESSAGE="$(git log --format=%B -n 1 "${GITHUB_SHA:-HEAD}")"
  fi

  # Parameter expansion, not | head, so pipefail cannot mask a git failure.
  COMMIT_MESSAGE="${COMMIT_MESSAGE%%$'\n'*}"

  SOURCE_REF="${SOURCE_REF//\//_}"

  BUILD_NAME="${SOURCE_REF}-${SHORT_COMMIT}-${TIMESTAMP}-${MODIFIED_GITHUB_RUN_NUMBER}"
  BUILD_VERSION="${SOURCE_REF}-${MODIFIED_GITHUB_RUN_NUMBER}-${TIMESTAMP}"
  export BUILD_NAME BUILD_VERSION COMMIT_MESSAGE

  # Set deployment and skip flags from commit message triggers
  local flag keyword
  for flag in DEPLOY_ON_BETA DEPLOY_ON_RC DEPLOY_MACOS DEPLOY_TVOS SKIP_LICENSES SKIP_LINTERS SKIP_TESTS UPDATE_PACKAGES; do
    keyword="$(trigger_keyword "${flag}")"
    set_flag_from_trigger "${flag}" "${keyword}"
  done

  # DEPLOY_ON_PROD requires both trigger and tag
  DEPLOY_ON_PROD=0
  if on_prod && [ "${TAG}" != "" ]; then
    DEPLOY_ON_PROD=1
  fi
  export DEPLOY_ON_PROD

  # DEPLOY_OPTIONS extracts value from trigger
  DEPLOY_OPTIONS=""
  if deploy_options; then
    keyword="$(trigger_keyword DEPLOY_OPTIONS)"
    DEPLOY_OPTIONS="$(echo "${COMMIT_MESSAGE}" | sed -n "s/.*#${keyword}=\([^ ]*\).*/\1/p")"
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
  add_linter_if_file "PHPCS"         ".php-cs-fixer.php"
  add_linter_if_file "PHPCS"         ".php-cs-fixer.dist.php"
  add_linter_if_file "PHPSTAN"       "phpstan.neon"
  add_linter_if_file "PHPSTAN"       "phpstan.neon.dist"
  add_linter_if_file "PHPSTAN"       "phpstan.dist.neon"
  add_linter_if_file "PMD"           ".pmd.xml"
  add_linter_if_file "PROTOLINT"     ".protolint.yaml"
  add_linter_if_file "RUBOCOP"       ".rubocop.yml"
  add_linter_if_file "SEMGREP"       ".semgrepignore"
  add_linter_if_file "SHELLCHECK"    ".shellcheckrc"
  add_linter_if_file "SWIFTLINT"     ".swiftlint.yml"
  # TRIVY - enabled when IaC files or package manager files are present
  if detect_trivy; then
    LINTERS="${LINTERS} TRIVY"
  fi
  add_linter_if_file "YAMLLINT"      ".yamllint.yml"

  for github in BUILD_NAME BUILD_VERSION COMMIT_MESSAGE MODIFIED_GITHUB_RUN_NUMBER DEPLOY_ON_BETA DEPLOY_ON_RC DEPLOY_ON_PROD DEPLOY_MACOS DEPLOY_TVOS DEPLOY_OPTIONS SKIP_LICENSES SKIP_LINTERS SKIP_TESTS UPDATE_PACKAGES LINTERS; do
    echo "${github}=${!github}" >> "${GITHUB_ENV}"
    echo "${github}=${!github}" >> "${GITHUB_OUTPUT}"
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
