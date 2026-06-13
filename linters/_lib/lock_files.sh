#!/usr/bin/env bash

# Single source of truth for the package-manager lock/manifest files that mark a
# project Trivy should run a vulnerability scan against (QUAL-010, #238).
#
# Sourced by both consumers so the list lives in exactly one place:
#   - variables/variables.sh  detect_trivy()  -> enables the TRIVY linter
#       source ".../variables/../linters/_lib/lock_files.sh"
#   - linters/trivy/action.yml                -> adds the `vuln` scanner
#       source "${GITHUB_ACTION_PATH}/../_lib/lock_files.sh"
#
# Adding or removing an ecosystem here updates both consumers at once; without
# single-sourcing, a list that drifts silently produces a Trivy job that runs
# without the vuln scanner (or never runs at all) with no error surfaced.
# tests/lock_file_contract.py asserts both consumers keep sourcing this list and
# do not re-introduce a hardcoded copy.
#
# Note: Dockerfile* / *.tf / .cfnlintrc / .hadolint.yaml are IaC markers handled
# separately (they drive TRIVY's misconfig scanner, not vuln), and package.json
# enables TRIVY in variables.sh as a manifest without a lock file — none of those
# belong in this lock-file list.

# shellcheck disable=SC2034  # consumed by the scripts that source this file
TRIVY_LOCK_FILES=(
  package-lock.json
  yarn.lock
  pnpm-lock.yaml
  go.sum
  requirements.txt
  Pipfile.lock
  poetry.lock
  Gemfile.lock
  composer.lock
  pom.xml
  build.gradle
  build.gradle.kts
  Cargo.lock
  Package.resolved
)
