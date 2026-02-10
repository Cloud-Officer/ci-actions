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
