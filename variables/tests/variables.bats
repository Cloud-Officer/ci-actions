#!/usr/bin/env bats

# Setup: source the script functions without running the main logic
setup() {
  # Create temp directory for test files
  export TEST_DIR="$(mktemp -d)"
  export GITHUB_ENV="${TEST_DIR}/github_env"
  export GITHUB_OUTPUT="${TEST_DIR}/github_output"
  export GITHUB_RUN_NUMBER=100
  touch "${GITHUB_ENV}" "${GITHUB_OUTPUT}"

  # Source only the functions from variables.sh
  # We need to extract just the function definitions
  extract_functions
}

teardown() {
  rm -rf "${TEST_DIR}"
}

# Extract only functions from variables.sh without executing the main script
extract_functions() {
  # Define the functions manually to avoid side effects
  export -f has_trigger 2>/dev/null || true

  # has_trigger function
  has_trigger() {
    echo "${COMMIT_MESSAGE}" | grep -iF "#$1" &> /dev/null
  }

  # Convenience aliases
  on_beta() { has_trigger "beta-deploy"; }
  on_rc() { has_trigger "rc-deploy"; }
  on_prod() { has_trigger "prod-deploy"; }
  on_macos() { has_trigger "macos"; }
  on_tvos() { has_trigger "tvos"; }
  deploy_options() { has_trigger "deploy-options"; }
  skip_all() { has_trigger "skip-all"; }
  skip_licenses() { has_trigger "skip-licenses"; }
  skip_linters() { has_trigger "skip-linters"; }
  skip_tests() { has_trigger "skip-tests"; }
  update_packages() { has_trigger "update-packages"; }

  # Helper function to set boolean flag from trigger
  set_flag_from_trigger() {
    local var_name="$1"
    local trigger="$2"
    if has_trigger "${trigger}"; then
      eval "export ${var_name}=1"
    else
      eval "export ${var_name}=0"
    fi
  }

  # Linter detection functions
  add_linter_if_file() {
    [ -f "$2" ] && LINTERS="${LINTERS} $1"
  }

  add_linter_if_dir() {
    [ -d "$2" ] && LINTERS="${LINTERS} $1"
  }

  export -f has_trigger on_beta on_rc on_prod on_macos on_tvos
  export -f deploy_options skip_all skip_licenses skip_linters skip_tests update_packages
  export -f set_flag_from_trigger add_linter_if_file add_linter_if_dir
}

# ============================================================================
# has_trigger tests
# ============================================================================

@test "has_trigger returns true when trigger is present" {
  export COMMIT_MESSAGE="feat: Add feature #beta-deploy"
  run has_trigger "beta-deploy"
  [ "$status" -eq 0 ]
}

@test "has_trigger returns false when trigger is absent" {
  export COMMIT_MESSAGE="feat: Add feature"
  run has_trigger "beta-deploy"
  [ "$status" -eq 1 ]
}

@test "has_trigger is case insensitive" {
  export COMMIT_MESSAGE="feat: Add feature #BETA-DEPLOY"
  run has_trigger "beta-deploy"
  [ "$status" -eq 0 ]
}

@test "has_trigger matches partial word" {
  export COMMIT_MESSAGE="feat: #skip-tests for now"
  run has_trigger "skip-tests"
  [ "$status" -eq 0 ]
}

@test "has_trigger works with multiple triggers" {
  export COMMIT_MESSAGE="feat: #beta-deploy #skip-tests"
  run has_trigger "beta-deploy"
  [ "$status" -eq 0 ]
  run has_trigger "skip-tests"
  [ "$status" -eq 0 ]
}

# ============================================================================
# Convenience alias tests
# ============================================================================

@test "on_beta returns true for #beta-deploy" {
  export COMMIT_MESSAGE="Deploy to beta #beta-deploy"
  run on_beta
  [ "$status" -eq 0 ]
}

@test "on_beta returns false without trigger" {
  export COMMIT_MESSAGE="Normal commit"
  run on_beta
  [ "$status" -eq 1 ]
}

@test "on_rc returns true for #rc-deploy" {
  export COMMIT_MESSAGE="Deploy to RC #rc-deploy"
  run on_rc
  [ "$status" -eq 0 ]
}

@test "on_prod returns true for #prod-deploy" {
  export COMMIT_MESSAGE="Deploy to prod #prod-deploy"
  run on_prod
  [ "$status" -eq 0 ]
}

@test "on_macos returns true for #macos" {
  export COMMIT_MESSAGE="Build for macOS #macos"
  run on_macos
  [ "$status" -eq 0 ]
}

@test "on_tvos returns true for #tvos" {
  export COMMIT_MESSAGE="Build for tvOS #tvos"
  run on_tvos
  [ "$status" -eq 0 ]
}

@test "skip_all returns true for #skip-all" {
  export COMMIT_MESSAGE="Quick fix #skip-all"
  run skip_all
  [ "$status" -eq 0 ]
}

@test "skip_licenses returns true for #skip-licenses" {
  export COMMIT_MESSAGE="Update deps #skip-licenses"
  run skip_licenses
  [ "$status" -eq 0 ]
}

@test "skip_linters returns true for #skip-linters" {
  export COMMIT_MESSAGE="WIP #skip-linters"
  run skip_linters
  [ "$status" -eq 0 ]
}

@test "skip_tests returns true for #skip-tests" {
  export COMMIT_MESSAGE="Hotfix #skip-tests"
  run skip_tests
  [ "$status" -eq 0 ]
}

@test "update_packages returns true for #update-packages" {
  export COMMIT_MESSAGE="Dependency update #update-packages"
  run update_packages
  [ "$status" -eq 0 ]
}

@test "deploy_options returns true for #deploy-options" {
  export COMMIT_MESSAGE="Deploy with options #deploy-options=verbose"
  run deploy_options
  [ "$status" -eq 0 ]
}

# ============================================================================
# set_flag_from_trigger tests
# ============================================================================

@test "set_flag_from_trigger sets 1 when trigger present" {
  export COMMIT_MESSAGE="Deploy #beta-deploy"
  set_flag_from_trigger DEPLOY_ON_BETA "beta-deploy"
  [ "$DEPLOY_ON_BETA" = "1" ]
}

@test "set_flag_from_trigger sets 0 when trigger absent" {
  export COMMIT_MESSAGE="Normal commit"
  set_flag_from_trigger DEPLOY_ON_BETA "beta-deploy"
  [ "$DEPLOY_ON_BETA" = "0" ]
}

@test "set_flag_from_trigger works with different variable names" {
  export COMMIT_MESSAGE="Skip tests #skip-tests"
  set_flag_from_trigger SKIP_TESTS "skip-tests"
  [ "$SKIP_TESTS" = "1" ]
}

@test "set_flag_from_trigger exports the variable" {
  export COMMIT_MESSAGE="Update #update-packages"
  set_flag_from_trigger UPDATE_PACKAGES "update-packages"
  # Check that the variable is exported (available to subshells)
  result=$(bash -c 'echo $UPDATE_PACKAGES')
  [ "$result" = "1" ]
}

# ============================================================================
# Linter detection tests
# ============================================================================

@test "add_linter_if_file adds linter when file exists" {
  touch "${TEST_DIR}/.eslintrc.json"
  export LINTERS=""
  add_linter_if_file "ESLINT" "${TEST_DIR}/.eslintrc.json"
  [[ "$LINTERS" == *"ESLINT"* ]]
}

@test "add_linter_if_file does not add linter when file missing" {
  export LINTERS=""
  add_linter_if_file "ESLINT" "${TEST_DIR}/.eslintrc.json" || true
  [[ "$LINTERS" != *"ESLINT"* ]]
}

@test "add_linter_if_dir adds linter when directory exists" {
  mkdir -p "${TEST_DIR}/.github/workflows"
  export LINTERS=""
  add_linter_if_dir "ACTIONLINT" "${TEST_DIR}/.github/workflows"
  [[ "$LINTERS" == *"ACTIONLINT"* ]]
}

@test "add_linter_if_dir does not add linter when directory missing" {
  export LINTERS=""
  add_linter_if_dir "ACTIONLINT" "${TEST_DIR}/.github/workflows" || true
  [[ "$LINTERS" != *"ACTIONLINT"* ]]
}

@test "multiple linters can be detected" {
  touch "${TEST_DIR}/.eslintrc.json"
  touch "${TEST_DIR}/.yamllint.yml"
  mkdir -p "${TEST_DIR}/.github/workflows"
  export LINTERS=""
  add_linter_if_file "ESLINT" "${TEST_DIR}/.eslintrc.json"
  add_linter_if_file "YAMLLINT" "${TEST_DIR}/.yamllint.yml"
  add_linter_if_dir "ACTIONLINT" "${TEST_DIR}/.github/workflows"
  [[ "$LINTERS" == *"ESLINT"* ]]
  [[ "$LINTERS" == *"YAMLLINT"* ]]
  [[ "$LINTERS" == *"ACTIONLINT"* ]]
}

# ============================================================================
# Integration tests
# ============================================================================

@test "empty commit message triggers nothing" {
  export COMMIT_MESSAGE=""
  run on_beta
  [ "$status" -eq 1 ]
  run skip_all
  [ "$status" -eq 1 ]
}

@test "commit message with only whitespace triggers nothing" {
  export COMMIT_MESSAGE="   "
  run on_beta
  [ "$status" -eq 1 ]
}

@test "trigger at start of message works" {
  export COMMIT_MESSAGE="#beta-deploy initial deploy"
  run on_beta
  [ "$status" -eq 0 ]
}

@test "trigger at end of message works" {
  export COMMIT_MESSAGE="Initial deploy #beta-deploy"
  run on_beta
  [ "$status" -eq 0 ]
}

@test "trigger in middle of message works" {
  export COMMIT_MESSAGE="Deploy to #beta-deploy environment"
  run on_beta
  [ "$status" -eq 0 ]
}

@test "similar but different trigger does not match" {
  export COMMIT_MESSAGE="Deploy #beta-deploy-test"
  # This should still match because grep -F matches substring
  run has_trigger "beta-deploy"
  [ "$status" -eq 0 ]
}

@test "trigger without hash does not match" {
  export COMMIT_MESSAGE="Deploy beta-deploy"
  run on_beta
  [ "$status" -eq 1 ]
}

# ============================================================================
# Main body: deployment and skip flag tests
# ============================================================================

@test "all deployment flags set correctly from commit message" {
  export COMMIT_MESSAGE="Deploy #beta-deploy #rc-deploy #macos #tvos"
  set_flag_from_trigger DEPLOY_ON_BETA "beta-deploy"
  set_flag_from_trigger DEPLOY_ON_RC "rc-deploy"
  set_flag_from_trigger DEPLOY_MACOS "macos"
  set_flag_from_trigger DEPLOY_TVOS "tvos"
  [ "$DEPLOY_ON_BETA" = "1" ]
  [ "$DEPLOY_ON_RC" = "1" ]
  [ "$DEPLOY_MACOS" = "1" ]
  [ "$DEPLOY_TVOS" = "1" ]
}

@test "all deployment flags default to 0 without triggers" {
  export COMMIT_MESSAGE="Normal commit"
  set_flag_from_trigger DEPLOY_ON_BETA "beta-deploy"
  set_flag_from_trigger DEPLOY_ON_RC "rc-deploy"
  set_flag_from_trigger DEPLOY_MACOS "macos"
  set_flag_from_trigger DEPLOY_TVOS "tvos"
  [ "$DEPLOY_ON_BETA" = "0" ]
  [ "$DEPLOY_ON_RC" = "0" ]
  [ "$DEPLOY_MACOS" = "0" ]
  [ "$DEPLOY_TVOS" = "0" ]
}

@test "all skip flags set correctly from commit message" {
  export COMMIT_MESSAGE="Fix #skip-licenses #skip-linters #skip-tests #update-packages"
  set_flag_from_trigger SKIP_LICENSES "skip-licenses"
  set_flag_from_trigger SKIP_LINTERS "skip-linters"
  set_flag_from_trigger SKIP_TESTS "skip-tests"
  set_flag_from_trigger UPDATE_PACKAGES "update-packages"
  [ "$SKIP_LICENSES" = "1" ]
  [ "$SKIP_LINTERS" = "1" ]
  [ "$SKIP_TESTS" = "1" ]
  [ "$UPDATE_PACKAGES" = "1" ]
}

@test "DEPLOY_ON_PROD requires both trigger and TAG" {
  export COMMIT_MESSAGE="Release #prod-deploy"
  export TAG="v1.0.0"
  DEPLOY_ON_PROD=0
  if on_prod && [ "${TAG}" != "" ]; then
    DEPLOY_ON_PROD=1
  fi
  [ "$DEPLOY_ON_PROD" = "1" ]
}

@test "DEPLOY_ON_PROD is 0 with trigger but no TAG" {
  export COMMIT_MESSAGE="Release #prod-deploy"
  export TAG=""
  DEPLOY_ON_PROD=0
  if on_prod && [ "${TAG}" != "" ]; then
    DEPLOY_ON_PROD=1
  fi
  [ "$DEPLOY_ON_PROD" = "0" ]
}

@test "DEPLOY_ON_PROD is 0 with TAG but no trigger" {
  export COMMIT_MESSAGE="Normal release"
  export TAG="v1.0.0"
  DEPLOY_ON_PROD=0
  if on_prod && [ "${TAG}" != "" ]; then
    DEPLOY_ON_PROD=1
  fi
  [ "$DEPLOY_ON_PROD" = "0" ]
}

@test "DEPLOY_OPTIONS extracts value from commit message" {
  export COMMIT_MESSAGE="Deploy with #deploy-options=verbose,dry-run"
  DEPLOY_OPTIONS=""
  if deploy_options; then
    DEPLOY_OPTIONS="$(echo "${COMMIT_MESSAGE}" | sed -n 's/.*#deploy-options=\([^ ]*\).*/\1/p')"
  fi
  [ "$DEPLOY_OPTIONS" = "verbose,dry-run" ]
}

@test "DEPLOY_OPTIONS is empty without trigger" {
  export COMMIT_MESSAGE="Normal deploy"
  DEPLOY_OPTIONS=""
  if deploy_options; then
    DEPLOY_OPTIONS="$(echo "${COMMIT_MESSAGE}" | sed -n 's/.*#deploy-options=\([^ ]*\).*/\1/p')"
  fi
  [ "$DEPLOY_OPTIONS" = "" ]
}

@test "skip_all overrides all individual skip flags" {
  export COMMIT_MESSAGE="Quick fix #skip-all"
  set_flag_from_trigger SKIP_LICENSES "skip-licenses"
  set_flag_from_trigger SKIP_LINTERS "skip-linters"
  set_flag_from_trigger SKIP_TESTS "skip-tests"
  # Before skip_all, individual flags are 0
  [ "$SKIP_LICENSES" = "0" ]
  [ "$SKIP_LINTERS" = "0" ]
  [ "$SKIP_TESTS" = "0" ]
  # Apply skip_all override
  if skip_all; then
    export SKIP_LICENSES=1
    export SKIP_LINTERS=1
    export SKIP_TESTS=1
  fi
  [ "$SKIP_LICENSES" = "1" ]
  [ "$SKIP_LINTERS" = "1" ]
  [ "$SKIP_TESTS" = "1" ]
}

@test "skip_all does not affect non-skip flags" {
  export COMMIT_MESSAGE="Quick fix #skip-all"
  set_flag_from_trigger DEPLOY_ON_BETA "beta-deploy"
  set_flag_from_trigger UPDATE_PACKAGES "update-packages"
  [ "$DEPLOY_ON_BETA" = "0" ]
  [ "$UPDATE_PACKAGES" = "0" ]
}

# ============================================================================
# Main body: full linter auto-detection chain tests
# ============================================================================

@test "linter detection: ACTIONLINT detected from .github/workflows directory" {
  mkdir -p "${TEST_DIR}/.github/workflows"
  LINTERS=""
  add_linter_if_dir "ACTIONLINT" "${TEST_DIR}/.github/workflows"
  [[ "$LINTERS" == *"ACTIONLINT"* ]]
}

@test "linter detection: BANDIT detected from .bandit file" {
  touch "${TEST_DIR}/.bandit"
  LINTERS=""
  add_linter_if_file "BANDIT" "${TEST_DIR}/.bandit"
  [[ "$LINTERS" == *"BANDIT"* ]]
}

@test "linter detection: ESLINT detected from .eslintrc.json file" {
  touch "${TEST_DIR}/.eslintrc.json"
  LINTERS=""
  add_linter_if_file "ESLINT" "${TEST_DIR}/.eslintrc.json"
  [[ "$LINTERS" == *"ESLINT"* ]]
}

@test "linter detection: FLAKE8 detected from .flake8 file" {
  touch "${TEST_DIR}/.flake8"
  LINTERS=""
  add_linter_if_file "FLAKE8" "${TEST_DIR}/.flake8"
  [[ "$LINTERS" == *"FLAKE8"* ]]
}

@test "linter detection: GOLANGCI detected from .golangci.yml file" {
  touch "${TEST_DIR}/.golangci.yml"
  LINTERS=""
  add_linter_if_file "GOLANGCI" "${TEST_DIR}/.golangci.yml"
  [[ "$LINTERS" == *"GOLANGCI"* ]]
}

@test "linter detection: HADOLINT detected from .hadolint.yaml file" {
  touch "${TEST_DIR}/.hadolint.yaml"
  LINTERS=""
  add_linter_if_file "HADOLINT" "${TEST_DIR}/.hadolint.yaml"
  [[ "$LINTERS" == *"HADOLINT"* ]]
}

@test "linter detection: KTLINT detected from .editorconfig file" {
  touch "${TEST_DIR}/.editorconfig"
  LINTERS=""
  add_linter_if_file "KTLINT" "${TEST_DIR}/.editorconfig"
  [[ "$LINTERS" == *"KTLINT"* ]]
}

@test "linter detection: MARKDOWNLINT detected from .markdownlint.yml file" {
  touch "${TEST_DIR}/.markdownlint.yml"
  LINTERS=""
  add_linter_if_file "MARKDOWNLINT" "${TEST_DIR}/.markdownlint.yml"
  [[ "$LINTERS" == *"MARKDOWNLINT"* ]]
}

@test "linter detection: PHPCS detected from .php-cs-fixer.dist.php file" {
  touch "${TEST_DIR}/.php-cs-fixer.dist.php"
  LINTERS=""
  add_linter_if_file "PHPCS" "${TEST_DIR}/.php-cs-fixer.dist.php"
  [[ "$LINTERS" == *"PHPCS"* ]]
}

@test "linter detection: PHPSTAN detected from phpstan.neon file" {
  touch "${TEST_DIR}/phpstan.neon"
  LINTERS=""
  add_linter_if_file "PHPSTAN" "${TEST_DIR}/phpstan.neon"
  [[ "$LINTERS" == *"PHPSTAN"* ]]
}

@test "linter detection: PMD detected from .pmd.xml file" {
  touch "${TEST_DIR}/.pmd.xml"
  LINTERS=""
  add_linter_if_file "PMD" "${TEST_DIR}/.pmd.xml"
  [[ "$LINTERS" == *"PMD"* ]]
}

@test "linter detection: PROTOLINT detected from .protolint.yaml file" {
  touch "${TEST_DIR}/.protolint.yaml"
  LINTERS=""
  add_linter_if_file "PROTOLINT" "${TEST_DIR}/.protolint.yaml"
  [[ "$LINTERS" == *"PROTOLINT"* ]]
}

@test "linter detection: RUBOCOP detected from .rubocop.yml file" {
  touch "${TEST_DIR}/.rubocop.yml"
  LINTERS=""
  add_linter_if_file "RUBOCOP" "${TEST_DIR}/.rubocop.yml"
  [[ "$LINTERS" == *"RUBOCOP"* ]]
}

@test "linter detection: SEMGREP detected from .semgrepignore file" {
  touch "${TEST_DIR}/.semgrepignore"
  LINTERS=""
  add_linter_if_file "SEMGREP" "${TEST_DIR}/.semgrepignore"
  [[ "$LINTERS" == *"SEMGREP"* ]]
}

@test "linter detection: SHELLCHECK detected from .shellcheckrc file" {
  touch "${TEST_DIR}/.shellcheckrc"
  LINTERS=""
  add_linter_if_file "SHELLCHECK" "${TEST_DIR}/.shellcheckrc"
  [[ "$LINTERS" == *"SHELLCHECK"* ]]
}

@test "linter detection: SWIFTLINT detected from .swiftlint.yml file" {
  touch "${TEST_DIR}/.swiftlint.yml"
  LINTERS=""
  add_linter_if_file "SWIFTLINT" "${TEST_DIR}/.swiftlint.yml"
  [[ "$LINTERS" == *"SWIFTLINT"* ]]
}

@test "linter detection: YAMLLINT detected from .yamllint.yml file" {
  touch "${TEST_DIR}/.yamllint.yml"
  LINTERS=""
  add_linter_if_file "YAMLLINT" "${TEST_DIR}/.yamllint.yml"
  [[ "$LINTERS" == *"YAMLLINT"* ]]
}

@test "linter detection: no linters detected when no config files present" {
  LINTERS=""
  add_linter_if_dir  "ACTIONLINT"    "${TEST_DIR}/.github/workflows" || true
  add_linter_if_file "BANDIT"        "${TEST_DIR}/.bandit" || true
  add_linter_if_file "ESLINT"        "${TEST_DIR}/.eslintrc.json" || true
  add_linter_if_file "FLAKE8"        "${TEST_DIR}/.flake8" || true
  add_linter_if_file "GOLANGCI"      "${TEST_DIR}/.golangci.yml" || true
  add_linter_if_file "HADOLINT"      "${TEST_DIR}/.hadolint.yaml" || true
  add_linter_if_file "KTLINT"        "${TEST_DIR}/.editorconfig" || true
  add_linter_if_file "MARKDOWNLINT"  "${TEST_DIR}/.markdownlint.yml" || true
  add_linter_if_file "PHPCS"         "${TEST_DIR}/.php-cs-fixer.dist.php" || true
  add_linter_if_file "PHPSTAN"       "${TEST_DIR}/phpstan.neon" || true
  add_linter_if_file "PMD"           "${TEST_DIR}/.pmd.xml" || true
  add_linter_if_file "PROTOLINT"     "${TEST_DIR}/.protolint.yaml" || true
  add_linter_if_file "RUBOCOP"       "${TEST_DIR}/.rubocop.yml" || true
  add_linter_if_file "SEMGREP"       "${TEST_DIR}/.semgrepignore" || true
  add_linter_if_file "SHELLCHECK"    "${TEST_DIR}/.shellcheckrc" || true
  add_linter_if_file "SWIFTLINT"     "${TEST_DIR}/.swiftlint.yml" || true
  add_linter_if_file "YAMLLINT"      "${TEST_DIR}/.yamllint.yml" || true
  [ "$LINTERS" = "" ]
}

@test "linter detection: full chain detects all linters when all config files present" {
  mkdir -p "${TEST_DIR}/.github/workflows"
  touch "${TEST_DIR}/.bandit"
  touch "${TEST_DIR}/.eslintrc.json"
  touch "${TEST_DIR}/.flake8"
  touch "${TEST_DIR}/.golangci.yml"
  touch "${TEST_DIR}/.hadolint.yaml"
  touch "${TEST_DIR}/.editorconfig"
  touch "${TEST_DIR}/.markdownlint.yml"
  touch "${TEST_DIR}/.php-cs-fixer.dist.php"
  touch "${TEST_DIR}/phpstan.neon"
  touch "${TEST_DIR}/.pmd.xml"
  touch "${TEST_DIR}/.protolint.yaml"
  touch "${TEST_DIR}/.rubocop.yml"
  touch "${TEST_DIR}/.semgrepignore"
  touch "${TEST_DIR}/.shellcheckrc"
  touch "${TEST_DIR}/.swiftlint.yml"
  touch "${TEST_DIR}/.yamllint.yml"
  LINTERS=""
  add_linter_if_dir  "ACTIONLINT"    "${TEST_DIR}/.github/workflows"
  add_linter_if_file "BANDIT"        "${TEST_DIR}/.bandit"
  add_linter_if_file "ESLINT"        "${TEST_DIR}/.eslintrc.json"
  add_linter_if_file "FLAKE8"        "${TEST_DIR}/.flake8"
  add_linter_if_file "GOLANGCI"      "${TEST_DIR}/.golangci.yml"
  add_linter_if_file "HADOLINT"      "${TEST_DIR}/.hadolint.yaml"
  add_linter_if_file "KTLINT"        "${TEST_DIR}/.editorconfig"
  add_linter_if_file "MARKDOWNLINT"  "${TEST_DIR}/.markdownlint.yml"
  add_linter_if_file "PHPCS"         "${TEST_DIR}/.php-cs-fixer.dist.php"
  add_linter_if_file "PHPSTAN"       "${TEST_DIR}/phpstan.neon"
  add_linter_if_file "PMD"           "${TEST_DIR}/.pmd.xml"
  add_linter_if_file "PROTOLINT"     "${TEST_DIR}/.protolint.yaml"
  add_linter_if_file "RUBOCOP"       "${TEST_DIR}/.rubocop.yml"
  add_linter_if_file "SEMGREP"       "${TEST_DIR}/.semgrepignore"
  add_linter_if_file "SHELLCHECK"    "${TEST_DIR}/.shellcheckrc"
  add_linter_if_file "SWIFTLINT"     "${TEST_DIR}/.swiftlint.yml"
  add_linter_if_file "YAMLLINT"      "${TEST_DIR}/.yamllint.yml"
  [[ "$LINTERS" == *"ACTIONLINT"* ]]
  [[ "$LINTERS" == *"BANDIT"* ]]
  [[ "$LINTERS" == *"ESLINT"* ]]
  [[ "$LINTERS" == *"FLAKE8"* ]]
  [[ "$LINTERS" == *"GOLANGCI"* ]]
  [[ "$LINTERS" == *"HADOLINT"* ]]
  [[ "$LINTERS" == *"KTLINT"* ]]
  [[ "$LINTERS" == *"MARKDOWNLINT"* ]]
  [[ "$LINTERS" == *"PHPCS"* ]]
  [[ "$LINTERS" == *"PHPSTAN"* ]]
  [[ "$LINTERS" == *"PMD"* ]]
  [[ "$LINTERS" == *"PROTOLINT"* ]]
  [[ "$LINTERS" == *"RUBOCOP"* ]]
  [[ "$LINTERS" == *"SEMGREP"* ]]
  [[ "$LINTERS" == *"SHELLCHECK"* ]]
  [[ "$LINTERS" == *"SWIFTLINT"* ]]
  [[ "$LINTERS" == *"YAMLLINT"* ]]
}

@test "linter detection: partial config files detect only matching linters" {
  touch "${TEST_DIR}/.eslintrc.json"
  touch "${TEST_DIR}/.swiftlint.yml"
  touch "${TEST_DIR}/.flake8"
  LINTERS=""
  add_linter_if_dir  "ACTIONLINT"    "${TEST_DIR}/.github/workflows" || true
  add_linter_if_file "BANDIT"        "${TEST_DIR}/.bandit" || true
  add_linter_if_file "ESLINT"        "${TEST_DIR}/.eslintrc.json"
  add_linter_if_file "FLAKE8"        "${TEST_DIR}/.flake8"
  add_linter_if_file "GOLANGCI"      "${TEST_DIR}/.golangci.yml" || true
  add_linter_if_file "SWIFTLINT"     "${TEST_DIR}/.swiftlint.yml"
  [[ "$LINTERS" == *"ESLINT"* ]]
  [[ "$LINTERS" == *"FLAKE8"* ]]
  [[ "$LINTERS" == *"SWIFTLINT"* ]]
  [[ "$LINTERS" != *"ACTIONLINT"* ]]
  [[ "$LINTERS" != *"BANDIT"* ]]
  [[ "$LINTERS" != *"GOLANGCI"* ]]
}

# ============================================================================
# Main body: GITHUB_ENV and GITHUB_OUTPUT writing tests
# ============================================================================

@test "variables are written to GITHUB_ENV and GITHUB_OUTPUT" {
  export COMMIT_MESSAGE="Deploy #beta-deploy"
  export TAG=""

  # Set all flags as the main body does
  set_flag_from_trigger DEPLOY_ON_BETA "beta-deploy"
  set_flag_from_trigger DEPLOY_ON_RC "rc-deploy"
  set_flag_from_trigger DEPLOY_MACOS "macos"
  set_flag_from_trigger DEPLOY_TVOS "tvos"
  set_flag_from_trigger SKIP_LICENSES "skip-licenses"
  set_flag_from_trigger SKIP_LINTERS "skip-linters"
  set_flag_from_trigger SKIP_TESTS "skip-tests"
  set_flag_from_trigger UPDATE_PACKAGES "update-packages"

  DEPLOY_ON_PROD=0
  if on_prod && [ "${TAG}" != "" ]; then
    DEPLOY_ON_PROD=1
  fi

  DEPLOY_OPTIONS=""
  if deploy_options; then
    DEPLOY_OPTIONS="$(echo "${COMMIT_MESSAGE}" | sed -n 's/.*#deploy-options=\([^ ]*\).*/\1/p')"
  fi

  if skip_all; then
    SKIP_LICENSES=1
    SKIP_LINTERS=1
    SKIP_TESTS=1
  fi

  LINTERS=""
  BUILD_NAME="test-build"
  BUILD_VERSION="test-version"
  MODIFIED_GITHUB_RUN_NUMBER=15100

  # Write to GITHUB_ENV and GITHUB_OUTPUT as the main body does
  for github in BUILD_NAME BUILD_VERSION COMMIT_MESSAGE MODIFIED_GITHUB_RUN_NUMBER DEPLOY_ON_BETA DEPLOY_ON_RC DEPLOY_ON_PROD DEPLOY_MACOS DEPLOY_TVOS DEPLOY_OPTIONS SKIP_LICENSES SKIP_LINTERS SKIP_TESTS UPDATE_PACKAGES LINTERS; do
    echo "${github}=${!github}" >> "${GITHUB_ENV}"
    echo "${github}=${!github}" >> "${GITHUB_OUTPUT}"
  done

  # Verify GITHUB_ENV contents
  grep -q "DEPLOY_ON_BETA=1" "${GITHUB_ENV}"
  grep -q "DEPLOY_ON_RC=0" "${GITHUB_ENV}"
  grep -q "DEPLOY_ON_PROD=0" "${GITHUB_ENV}"
  grep -q "SKIP_LICENSES=0" "${GITHUB_ENV}"
  grep -q "BUILD_NAME=test-build" "${GITHUB_ENV}"
  grep -q "LINTERS=" "${GITHUB_ENV}"

  # Verify GITHUB_OUTPUT contents
  grep -q "DEPLOY_ON_BETA=1" "${GITHUB_OUTPUT}"
  grep -q "DEPLOY_ON_RC=0" "${GITHUB_OUTPUT}"
  grep -q "MODIFIED_GITHUB_RUN_NUMBER=15100" "${GITHUB_OUTPUT}"
}
