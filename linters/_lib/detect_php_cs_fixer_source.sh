#!/usr/bin/env bash

# Writes use-composer=true|false to GITHUB_OUTPUT: whether php-cs-fixer comes from the project's Composer dependencies or the phar.
#
# Usage (from linters/phpcs/action.yml, with COMPOSER_COMMAND set to the composer-command input):
#   run: bash "${GITHUB_ACTION_PATH}/../_lib/detect_php_cs_fixer_source.sh"

set -euo pipefail

case "${COMPOSER_COMMAND}" in
  none)
    use_composer=false
    ;;
  auto)
    if [ -f composer.lock ] && grep -qE '"name":[[:space:]]*"(friendsofphp/php-cs-fixer|php-cs-fixer/shim)"' composer.lock; then
      use_composer=true
    else
      use_composer=false
    fi
    ;;
  *)
    use_composer=true
    ;;
esac

echo "use-composer=${use_composer}" >> "${GITHUB_OUTPUT}"
echo "php-cs-fixer from Composer: ${use_composer}"
