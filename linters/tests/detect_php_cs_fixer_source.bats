#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../_lib/detect_php_cs_fixer_source.sh"
  WORK="$(mktemp -d)"
  export GITHUB_OUTPUT="${WORK}/github_output"
  export COMPOSER_COMMAND="auto"
  cd "${WORK}" || exit 1
  touch "${GITHUB_OUTPUT}"
}

teardown() {
  cd / || true
  rm -rf "${WORK}"
}

use_composer() {
  bash "${SCRIPT}" > /dev/null
  grep '^use-composer=' "${GITHUB_OUTPUT}" | tail -1 | cut -d= -f2
}

lock_with() {
  printf '{\n    "packages-dev": [\n        {\n            "name": "%s",\n            "version": "v3.95.25"\n        }\n    ]\n}\n' "$1" > composer.lock
}

@test "auto without composer.lock uses the phar" {
  [ "$(use_composer)" = "false" ]
}

@test "auto with php-cs-fixer locked uses Composer" {
  lock_with friendsofphp/php-cs-fixer
  [ "$(use_composer)" = "true" ]
}

@test "auto with the php-cs-fixer shim locked uses Composer" {
  lock_with php-cs-fixer/shim
  [ "$(use_composer)" = "true" ]
}

@test "auto with only unrelated packages locked uses the phar" {
  lock_with phpstan/phpstan
  [ "$(use_composer)" = "false" ]
}

@test "auto ignores a package that only mentions php-cs-fixer in its name" {
  lock_with friendsofphp/php-cs-fixer-extras
  [ "$(use_composer)" = "false" ]
}

@test "none forces the phar even when php-cs-fixer is locked" {
  lock_with friendsofphp/php-cs-fixer
  export COMPOSER_COMMAND="none"
  [ "$(use_composer)" = "false" ]
}

@test "an explicit command uses Composer without composer.lock" {
  export COMPOSER_COMMAND="composer install --no-scripts"
  [ "$(use_composer)" = "true" ]
}

@test "prints the choice to the log" {
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ "$output" = "php-cs-fixer from Composer: false" ]
}
