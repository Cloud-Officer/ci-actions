# GitHub Action: Run phpstan

This action runs [phpstan](https://phpstan.org/).

## Inputs

```yml
inputs:
  linters:
    description: 'List of all enabled linters'
    required: true
  ssh-key:
    description: 'ssh key'
    required: true
  github_token:
    description: 'github token'
    required: true
  php-version:
    description: 'php version'
    required: false
    default: '8.2'
  php-extensions:
    description: 'php extensions'
    required: false
    default: ''
  php-stan-command:
    description: 'php stan command(s)'
    required: false
    default: 'vendor/bin/phpstan analyse'
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
        uses: cloud-officer/ci-actions/variables@master
        with:
          ssh-key: "${{secrets.SSH_KEY}}"
  phpstan:
    name: PHP Stan Linter
    runs-on: ubuntu-22.04
    needs:
      - variables
    if: "${{needs.variables.outputs.SKIP_LINTERS != '1'}}"
    steps:
      - name: PHPStan
        id: phpstan
        uses: cloud-officer/ci-actions/linters/phpstan@master
        with:
          linters: "${{needs.variables.outputs.LINTERS}}"
          ssh-key: "${{secrets.SSH_KEY}}"
          github_token: "${{secrets.GITHUB_TOKEN}}"
          php-version: "${{env.PHP-VERSION}}"
          php-extensions: "${{env.PHP-EXTENSIONS}}"
          php-stan-command: vendor/bin/phpstan analyse
```
