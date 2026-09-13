#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../_lib/require_inputs.sh"
}

@test "succeeds when every input has a value" {
  run bash "${SCRIPT}" "application-name=app" "s3-bucket=bucket"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "succeeds when no inputs are passed" {
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "fails and names an input whose value is empty" {
  run bash "${SCRIPT}" "application-name=app" "shell-commands="
  [ "$status" -eq 1 ]
  [ "$output" = "::error::required input(s) empty: shell-commands" ]
}

@test "treats spaces, tabs and newlines alone as empty" {
  local value
  for value in '   ' $'\t' $'\n' $' \t\n '; do
    run bash "${SCRIPT}" "s3-key=${value}"
    [ "$status" -eq 1 ]
    [ "$output" = "::error::required input(s) empty: s3-key" ]
  done
}

@test "names every empty input in a single message" {
  run bash "${SCRIPT}" "application-name=" "deployment-group-name=group" "s3-bucket=  " "s3-key="
  [ "$status" -eq 1 ]
  [ "$output" = "::error::required input(s) empty: application-name s3-bucket s3-key" ]
}

@test "splits each pair on the first '=' only" {
  run bash "${SCRIPT}" "shell-commands=aws s3 ls --query 'a=b'" "token=="
  [ "$status" -eq 0 ]
  run bash "${SCRIPT}" "shell-commands=" "other=x=y"
  [ "$status" -eq 1 ]
  [ "$output" = "::error::required input(s) empty: shell-commands" ]
}

@test "keeps a value with surrounding whitespace as present" {
  run bash "${SCRIPT}" "aws-region=  ca-central-1  "
  [ "$status" -eq 0 ]
}
