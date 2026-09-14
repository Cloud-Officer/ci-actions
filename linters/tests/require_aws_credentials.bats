#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../_lib/require_aws_credentials.sh"
}

check() {
  run env ROLE_TO_ASSUME="$1" ACCESS_KEY_ID="$2" SECRET_ACCESS_KEY="$3" bash "${SCRIPT}"
}

@test "accepts a role to assume without access keys (OIDC)" {
  check "arn:aws:iam::123456789012:role/deploy" "" ""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "accepts an access key pair without a role" {
  check "" "AKIAEXAMPLE" "secret"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "accepts a role together with an access key pair" {
  check "arn:aws:iam::123456789012:role/deploy" "AKIAEXAMPLE" "secret"
  [ "$status" -eq 0 ]
}

@test "fails when no credentials are supplied" {
  check "" "" ""
  [ "$status" -eq 1 ]
  [ "$output" = "::error::no AWS credentials: set aws-role-to-assume (GitHub OIDC), or aws-access-key-id and aws-secret-access-key" ]
}

@test "treats whitespace-only values as missing" {
  check "   " $'\t' $'\n'
  [ "$status" -eq 1 ]
  [[ "$output" == *"no AWS credentials"* ]]
}

@test "fails when only the access key id is supplied" {
  check "" "AKIAEXAMPLE" ""
  [ "$status" -eq 1 ]
  [ "$output" = "::error::aws-access-key-id and aws-secret-access-key must be set together" ]
}

@test "fails when only the secret access key is supplied, even with a role" {
  check "arn:aws:iam::123456789012:role/deploy" "" "secret"
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be set together"* ]]
}

@test "fails when the variables are not set at all" {
  run env -u ROLE_TO_ASSUME -u ACCESS_KEY_ID -u SECRET_ACCESS_KEY bash "${SCRIPT}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no AWS credentials"* ]]
}
