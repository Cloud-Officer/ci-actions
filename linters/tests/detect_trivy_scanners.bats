#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../_lib/detect_trivy_scanners.sh"
  WORK="$(mktemp -d)"
  export GITHUB_OUTPUT="${WORK}/github_output"
  export LINTERS=""
  cd "${WORK}" || exit 1
  touch "${GITHUB_OUTPUT}"
}

teardown() {
  cd / || true
  rm -rf "${WORK}"
}

scanners() {
  bash "${SCRIPT}" > /dev/null
  grep '^scanners=' "${GITHUB_OUTPUT}" | tail -1 | cut -d= -f2
}

add_file() {
  mkdir -p "$(dirname "$1")"
  touch "$1"
}

add_submodule() {
  mkdir -p "$1"
  printf '[submodule "%s"]\n\tpath = %s\n\turl = git@github.com:example/%s.git\n' "$1" "$1" "$1" >> .gitmodules
}

@test "an empty workspace gets only the secret scanner" {
  [ "$(scanners)" = "secret" ]
}

@test "prints the chosen scanners to the log" {
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ "$output" = "Trivy scanners: secret" ]
}

@test "Terraform four or more directories deep enables misconfig" {
  add_file infra/terraform/modules/vpc/main.tf
  [ "$(scanners)" = "secret,misconfig" ]
}

@test "a Dockerfile four or more directories deep enables misconfig" {
  add_file services/api/docker/build/Dockerfile.prod
  [ "$(scanners)" = "secret,misconfig" ]
}

@test "shallow Terraform enables misconfig" {
  add_file main.tf
  [ "$(scanners)" = "secret,misconfig" ]
}

@test "CFNLINT or HADOLINT in LINTERS enables misconfig without IaC files" {
  [ "$(LINTERS='SHELLCHECK CFNLINT' scanners)" = "secret,misconfig" ]
  [ "$(LINTERS='HADOLINT' scanners)" = "secret,misconfig" ]
}

@test "IaC files only inside a submodule do not enable misconfig" {
  add_submodule vendor-infra
  add_file vendor-infra/modules/network/deep/main.tf
  add_file vendor-infra/Dockerfile
  [ "$(scanners)" = "secret" ]
}

@test "a lock file four or more directories deep enables vuln" {
  add_file apps/web/frontend/client/package-lock.json
  [ "$(scanners)" = "secret,vuln" ]
}

@test "a lock file only inside a submodule does not enable vuln" {
  add_submodule third-party
  add_file third-party/Gemfile.lock
  [ "$(scanners)" = "secret" ]
}

@test "deep IaC and a lock file together enable every scanner" {
  add_file infra/terraform/envs/prod/main.tf
  add_file go.sum
  [ "$(scanners)" = "secret,misconfig,vuln" ]
}

@test "a submodule declared without spaces around '=' is still pruned" {
  mkdir -p vendor-infra/modules
  printf '[submodule "vendor-infra"]\n\tpath=vendor-infra\n\turl=git@github.com:example/vendor-infra.git\n' > .gitmodules
  add_file vendor-infra/modules/main.tf
  add_file vendor-infra/Gemfile.lock
  [ "$(scanners)" = "secret" ]
}
