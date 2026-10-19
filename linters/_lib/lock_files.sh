#!/usr/bin/env bash

# Lock/manifest files that enable Trivy's vuln scanner; sourced by variables.sh and detect_trivy_scanners.sh.

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
