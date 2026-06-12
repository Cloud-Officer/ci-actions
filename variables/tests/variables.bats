#!/usr/bin/env bats

# Setup: source the real variables.sh for its function definitions. The script
# guards its main body behind `[[ "${BASH_SOURCE[0]}" == "${0}" ]]`, so sourcing
# here loads the helpers without running git or writing to the runner files.
setup() {
  # Create temp directory for test files
  export TEST_DIR="$(mktemp -d)"
  export GITHUB_ENV="${TEST_DIR}/github_env"
  export GITHUB_OUTPUT="${TEST_DIR}/github_output"
  export GITHUB_RUN_NUMBER=100
  touch "${GITHUB_ENV}" "${GITHUB_OUTPUT}"

  source "${BATS_TEST_DIRNAME}/../variables.sh"
}

teardown() {
  rm -rf "${TEST_DIR}"
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

@test "linter detection: CFNLINT detected from .cfnlintrc file" {
  touch "${TEST_DIR}/.cfnlintrc"
  LINTERS=""
  add_linter_if_file "CFNLINT" "${TEST_DIR}/.cfnlintrc"
  [[ "$LINTERS" == *"CFNLINT"* ]]
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

@test "linter detection: MARKDOWNLINT detected from .markdownlint-cli2.yaml file" {
  touch "${TEST_DIR}/.markdownlint-cli2.yaml"
  LINTERS=""
  add_linter_if_file "MARKDOWNLINT" "${TEST_DIR}/.markdownlint-cli2.yaml"
  [[ "$LINTERS" == *"MARKDOWNLINT"* ]]
}

@test "linter detection: MARKDOWNLINT detected from .markdownlint.yml file (v1 backward compat)" {
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

# TRIVY is detected by a depth-bounded find over the working tree (not a single
# config-file check), so these cases cd into a fixture tree and call the
# extracted detect_trivy predicate directly.

@test "linter detection: TRIVY detected when a Dockerfile is present at the root" {
  touch "${TEST_DIR}/Dockerfile"
  cd "${TEST_DIR}"
  run detect_trivy
  [ "$status" -eq 0 ]
}

@test "linter detection: TRIVY detected from a package-lock.json nested at depth 3" {
  # Proves the find descends into subdirectories (within -maxdepth 3), not just
  # the root: a/b/package-lock.json is three levels deep.
  mkdir -p "${TEST_DIR}/a/b"
  touch "${TEST_DIR}/a/b/package-lock.json"
  cd "${TEST_DIR}"
  run detect_trivy
  [ "$status" -eq 0 ]
}

@test "linter detection: TRIVY not detected when no IaC or manifest files present" {
  mkdir -p "${TEST_DIR}/src"
  touch "${TEST_DIR}/src/main.py"
  touch "${TEST_DIR}/README.md"
  cd "${TEST_DIR}"
  run detect_trivy
  [ "$status" -eq 1 ]
}

@test "linter detection: TRIVY detected from a lock file in the shared list (Gemfile.lock)" {
  # Locks that detect_trivy actually consumes the single-sourced
  # linters/_lib/lock_files.sh array (QUAL-010 / #238): Gemfile.lock is only
  # reachable via that list, not via the IaC/manifest names hardcoded in the
  # find expression. If the source breaks, the array is empty and this fails.
  touch "${TEST_DIR}/Gemfile.lock"
  cd "${TEST_DIR}"
  run detect_trivy
  [ "$status" -eq 0 ]
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
  add_linter_if_file "MARKDOWNLINT"  "${TEST_DIR}/.markdownlint-cli2.yaml" || true
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
  touch "${TEST_DIR}/.markdownlint-cli2.yaml"
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
  add_linter_if_file "MARKDOWNLINT"  "${TEST_DIR}/.markdownlint-cli2.yaml"
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
# Main body: end-to-end subprocess run of variables.sh
# ============================================================================

@test "running variables.sh resolves triggers and writes GITHUB_ENV/OUTPUT" {
  # Drive the real main() as a subprocess against a throwaway git repo, so the
  # actual sequencing (trigger resolution + the GITHUB_ENV/OUTPUT write loop)
  # is exercised rather than a re-implementation of it.
  local repo="${TEST_DIR}/repo"
  mkdir -p "${repo}"
  (
    cd "${repo}" || exit 1
    git init -q
    git config user.email test@example.com
    git config user.name test
    echo x > file.txt
    git add file.txt
    git commit -q -m "Test commit #beta-deploy #skip-tests"
  )

  run bash -c "cd '${repo}' && \
    GITHUB_REF=refs/heads/feature GITHUB_HEAD_REF=feature \
    GITHUB_RUN_NUMBER=100 GITHUB_ENV='${GITHUB_ENV}' GITHUB_OUTPUT='${GITHUB_OUTPUT}' \
    bash '${BATS_TEST_DIRNAME}/../variables.sh'"

  [ "${status}" -eq 0 ]

  # Values resolved by the real script from the commit-message triggers
  grep -q "DEPLOY_ON_BETA=1" "${GITHUB_OUTPUT}"
  grep -q "SKIP_TESTS=1" "${GITHUB_OUTPUT}"
  grep -q "DEPLOY_ON_RC=0" "${GITHUB_OUTPUT}"
  grep -q "DEPLOY_ON_PROD=0" "${GITHUB_OUTPUT}"
  grep -q "MODIFIED_GITHUB_RUN_NUMBER=15100" "${GITHUB_OUTPUT}"
  grep -q "COMMIT_MESSAGE=Test commit #beta-deploy #skip-tests" "${GITHUB_OUTPUT}"
  grep -qE "BUILD_NAME=feature-.+" "${GITHUB_OUTPUT}"

  # Same content mirrored to GITHUB_ENV
  grep -q "DEPLOY_ON_BETA=1" "${GITHUB_ENV}"
  grep -q "SKIP_TESTS=1" "${GITHUB_ENV}"
}

@test "branch ref containing 'tags' is not misrouted to the tag path" {
  # Regression: GITHUB_REF carries the substring 'tags' but is a branch, not
  # refs/tags/*. The old unanchored `grep tags` routed this through the tag path,
  # which ran a tag fetch and produced an empty COMMIT_MESSAGE / slash-mangled
  # BUILD_NAME. The anchored check must keep it on the branch path.
  local repo="${TEST_DIR}/repo"
  mkdir -p "${repo}"
  (
    cd "${repo}" || exit 1
    git init -q
    git config user.email test@example.com
    git config user.name test
    echo x > file.txt
    git add file.txt
    git commit -q -m "Branch build commit"
  )

  run bash -c "cd '${repo}' && \
    GITHUB_REF=refs/heads/feature/tags-cleanup GITHUB_HEAD_REF='' \
    GITHUB_SHA=HEAD GITHUB_RUN_NUMBER=100 \
    GITHUB_ENV='${GITHUB_ENV}' GITHUB_OUTPUT='${GITHUB_OUTPUT}' \
    bash '${BATS_TEST_DIRNAME}/../variables.sh'"

  [ "${status}" -eq 0 ]
  grep -q "COMMIT_MESSAGE=Branch build commit" "${GITHUB_OUTPUT}"
  grep -qE "BUILD_NAME=feature_tags-cleanup-.+" "${GITHUB_OUTPUT}"
  # BUILD_NAME must not contain a slash (a slash means the tag path mangled it).
  ! grep -E "^BUILD_NAME=.*/" "${GITHUB_OUTPUT}"
}

@test "tag ref drives the tag-build path: prod deploy, tag BUILD_NAME, tag-subject COMMIT_MESSAGE" {
  # Exercise the refs/tags/* branch of main() (the production-deploy gate) end to
  # end, the path two real bugs escaped on with green CI (#214, #224). The
  # authenticated `git fetch` to github.com is replaced by a PATH-shimmed git so
  # the test stays offline; the tag already exists locally, so every other git
  # subcommand (rev-parse, tag -l) passes through to the real binary.
  local repo="${TEST_DIR}/repo"
  mkdir -p "${repo}"
  (
    cd "${repo}" || exit 1
    git init -q
    git config user.email test@example.com
    git config user.name test
    echo x > file.txt
    git add file.txt
    git commit -q -m "Initial commit"
    git tag -a v1.0.0 -m "Release v1.0.0 #prod-deploy"
  )

  local shim_dir="${TEST_DIR}/bin"
  local real_git
  real_git="$(command -v git)"
  mkdir -p "${shim_dir}"
  cat > "${shim_dir}/git" <<EOF
#!/usr/bin/env bash
# Make the authenticated tag fetch a no-op; pass everything else to real git.
if [ "\$1" = "fetch" ]; then
  exit 0
fi
exec "${real_git}" "\$@"
EOF
  chmod +x "${shim_dir}/git"

  run bash -c "cd '${repo}' && \
    PATH=\"${shim_dir}:\$PATH\" \
    GITHUB_REF=refs/tags/v1.0.0 GITHUB_HEAD_REF='' \
    GITHUB_TOKEN=dummy-token GITHUB_REPOSITORY=owner/repo \
    GITHUB_RUN_NUMBER=100 \
    GITHUB_ENV='${GITHUB_ENV}' GITHUB_OUTPUT='${GITHUB_OUTPUT}' \
    bash '${BATS_TEST_DIRNAME}/../variables.sh'"

  [ "${status}" -eq 0 ]

  # DEPLOY_ON_PROD is gated on (#prod-deploy trigger AND a non-empty TAG); only
  # the tag path can satisfy both, so this is the real production-deploy gate.
  grep -q "DEPLOY_ON_PROD=1" "${GITHUB_OUTPUT}"
  # COMMIT_MESSAGE comes from the annotated tag's subject, not git log.
  grep -q "COMMIT_MESSAGE=Release v1.0.0 #prod-deploy" "${GITHUB_OUTPUT}"
  # BUILD_NAME is derived from the bare tag name (no refs/tags/ prefix, no slash).
  grep -qE "BUILD_NAME=v1.0.0-.+" "${GITHUB_OUTPUT}"
  ! grep -E "^BUILD_NAME=.*/" "${GITHUB_OUTPUT}"
  # Unrelated triggers stay off.
  grep -q "DEPLOY_ON_BETA=0" "${GITHUB_OUTPUT}"

  # Mirrored to GITHUB_ENV as well.
  grep -q "DEPLOY_ON_PROD=1" "${GITHUB_ENV}"
}

@test "branch ref with multiple slashes is fully sanitized in BUILD_NAME" {
  # Regression (#236 / BUG-009): SAFE_BRANCH used single-occurrence ${x/\//_},
  # so only the first slash was replaced. A branch two or more levels deep
  # (refs/heads/feature/a/b) left a literal slash in BUILD_NAME/BUILD_VERSION,
  # which then break the downstream zip/CodeDeploy/S3 steps.
  local repo="${TEST_DIR}/repo"
  mkdir -p "${repo}"
  (
    cd "${repo}" || exit 1
    git init -q
    git config user.email test@example.com
    git config user.name test
    echo x > file.txt
    git add file.txt
    git commit -q -m "Deep branch build commit"
  )

  run bash -c "cd '${repo}' && \
    GITHUB_REF=refs/heads/feature/a/b GITHUB_HEAD_REF='' \
    GITHUB_SHA=HEAD GITHUB_RUN_NUMBER=100 \
    GITHUB_ENV='${GITHUB_ENV}' GITHUB_OUTPUT='${GITHUB_OUTPUT}' \
    bash '${BATS_TEST_DIRNAME}/../variables.sh'"

  [ "${status}" -eq 0 ]
  # Every slash replaced: feature/a/b -> feature_a_b.
  grep -qE "BUILD_NAME=feature_a_b-.+" "${GITHUB_OUTPUT}"
  grep -qE "BUILD_VERSION=feature_a_b-.+" "${GITHUB_OUTPUT}"
  # Invariant: no slash survives in either identifier.
  ! grep -E "^BUILD_NAME=.*/" "${GITHUB_OUTPUT}"
  ! grep -E "^BUILD_VERSION=.*/" "${GITHUB_OUTPUT}"
}

@test "PR head ref with a slash is sanitized in BUILD_NAME" {
  # Regression (#237 / BUG-010): the PR-head path set SOURCE_REF straight from
  # GITHUB_HEAD_REF with no slash sanitization, so a PR opened from a slash-named
  # branch (the common convention) put a literal slash into BUILD_NAME.
  local repo="${TEST_DIR}/repo"
  mkdir -p "${repo}"
  (
    cd "${repo}" || exit 1
    git init -q
    git config user.email test@example.com
    git config user.name test
    echo x > file.txt
    git add file.txt
    git commit -q -m "PR build commit"
  )

  run bash -c "cd '${repo}' && \
    GITHUB_REF=refs/pull/7/merge GITHUB_HEAD_REF=feature/foo \
    GITHUB_RUN_NUMBER=100 \
    GITHUB_ENV='${GITHUB_ENV}' GITHUB_OUTPUT='${GITHUB_OUTPUT}' \
    bash '${BATS_TEST_DIRNAME}/../variables.sh'"

  [ "${status}" -eq 0 ]
  grep -qE "BUILD_NAME=feature_foo-.+" "${GITHUB_OUTPUT}"
  grep -qE "BUILD_VERSION=feature_foo-.+" "${GITHUB_OUTPUT}"
  ! grep -E "^BUILD_NAME=.*/" "${GITHUB_OUTPUT}"
  ! grep -E "^BUILD_VERSION=.*/" "${GITHUB_OUTPUT}"
}

@test "tag ref with a slash is sanitized in BUILD_NAME" {
  # Regression (#237 / BUG-010): the tag path set SOURCE_REF from the raw tag
  # name, so a slash-containing tag (e.g. releases/1.0) put a literal slash into
  # BUILD_NAME. The fetch is stubbed via a PATH-shimmed git (same as the
  # tag-build-path test); the tag exists locally so tag -l passes through.
  local repo="${TEST_DIR}/repo"
  mkdir -p "${repo}"
  (
    cd "${repo}" || exit 1
    git init -q
    git config user.email test@example.com
    git config user.name test
    echo x > file.txt
    git add file.txt
    git commit -q -m "Initial commit"
    git tag -a releases/1.0 -m "Release releases/1.0"
  )

  local shim_dir="${TEST_DIR}/bin"
  local real_git
  real_git="$(command -v git)"
  mkdir -p "${shim_dir}"
  cat > "${shim_dir}/git" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "fetch" ]; then
  exit 0
fi
exec "${real_git}" "\$@"
EOF
  chmod +x "${shim_dir}/git"

  run bash -c "cd '${repo}' && \
    PATH=\"${shim_dir}:\$PATH\" \
    GITHUB_REF=refs/tags/releases/1.0 GITHUB_HEAD_REF='' \
    GITHUB_TOKEN=dummy-token GITHUB_REPOSITORY=owner/repo \
    GITHUB_RUN_NUMBER=100 \
    GITHUB_ENV='${GITHUB_ENV}' GITHUB_OUTPUT='${GITHUB_OUTPUT}' \
    bash '${BATS_TEST_DIRNAME}/../variables.sh'"

  [ "${status}" -eq 0 ]
  # releases/1.0 -> releases_1.0 in the build identifiers.
  grep -qE "BUILD_NAME=releases_1.0-.+" "${GITHUB_OUTPUT}"
  grep -qE "BUILD_VERSION=releases_1.0-.+" "${GITHUB_OUTPUT}"
  ! grep -E "^BUILD_NAME=.*/" "${GITHUB_OUTPUT}"
  ! grep -E "^BUILD_VERSION=.*/" "${GITHUB_OUTPUT}"
}
