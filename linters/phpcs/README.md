# GitHub Action: Run php-cs-fixer

This action runs [php-cs-fixer](https://cs.symfony.com/).

## Inputs

```yml
inputs:
  linters:
    description: 'List of all enabled linters'
    required: true
  ssh-key:
    description: 'ssh key'
    required: true
  github-token:
    description: 'github token'
    required: false
    default: ${{ github.token }}
  php-version:
    description: 'php version'
    required: false
    default: '8.2'
  php-extensions:
    description: 'php extensions'
    required: false
    default: ''
  composer-command:
    description: 'composer command; auto runs composer install when composer.lock requires php-cs-fixer, none always uses the phar'
    required: false
    default: 'auto'
  php-cs-fixer-version:
    description: 'php-cs-fixer version'
    required: false
    default: 'latest'
  php-cs-fixer-command:
    description: 'php-cs-fixer command(s)'
    required: false
    default: './php-cs-fixer fix --dry-run --diff --verbose'
```

## Example usage

```yml
name: Build
'on':
  pull_request:
    types:
      - opened
      - edited
      - reopened
      - synchronize
  push:
  release:
    types:
      - created
jobs:
  variables:
    name: Prepare Variables
    runs-on: ubuntu-latest
    outputs:
      BUILD_NAME: "${{steps.variables.outputs.BUILD_NAME}}"
      BUILD_VERSION: "${{steps.variables.outputs.BUILD_VERSION}}"
      COMMIT_MESSAGE: "${{steps.variables.outputs.COMMIT_MESSAGE}}"
      DEPLOY_ON_BETA: "${{steps.variables.outputs.DEPLOY_ON_BETA}}"
      DEPLOY_ON_RC: "${{steps.variables.outputs.DEPLOY_ON_RC}}"
      DEPLOY_ON_PROD: "${{steps.variables.outputs.DEPLOY_ON_PROD}}"
      DEPLOY_MACOS: "${{steps.variables.outputs.DEPLOY_MACOS}}"
      DEPLOY_TVOS: "${{steps.variables.outputs.DEPLOY_TVOS}}"
      SKIP_LICENSES: "${{steps.variables.outputs.SKIP_LICENSES}}"
      SKIP_TESTS: "${{steps.variables.outputs.SKIP_TESTS}}"
      UPDATE_PACKAGES: "${{steps.variables.outputs.UPDATE_PACKAGES}}"
      LINTERS: "${{steps.variables.outputs.LINTERS}}"
    steps:
      - name: Prepare variables
        id: variables
        uses: cloud-officer/ci-actions/variables@v3
        with:
          ssh-key: "${{secrets.SSH_KEY}}"
  phpcs:
    name: PHP Linter
    runs-on: ubuntu-latest
    needs:
      - variables
    steps:
      - name: PHPCS
        id: phpcs
        uses: cloud-officer/ci-actions/linters/phpcs@v3
        with:
          linters: "${{needs.variables.outputs.LINTERS}}"
          ssh-key: "${{secrets.SSH_KEY}}"
          github-token: "${{secrets.GITHUB_TOKEN}}"
```

## Using the project's php-cs-fixer

By default (`composer-command: auto`), when `composer.lock` requires `friendsofphp/php-cs-fixer` or `php-cs-fixer/shim`, the action runs `composer install` and lints with `vendor/bin/php-cs-fixer`, so the version locked by the project is used and custom fixers from project code load. Private dependencies are fetched through `ssh-key` and `github-token`. Otherwise it downloads the signed phar selected by `php-cs-fixer-version`.

Set `composer-command` to a custom command to change how dependencies are installed, or to `none` to always use the phar.
