# GitHub Action: SOUP

This action runs [soup](https://github.com/Cloud-Officer/soup) to check open source licenses and can generate/check the
SOUP list against dependencies.

## Inputs

```yml
inputs:
  ssh-key:
    description: 'ssh key'
    required: true
  github-token:
    description: 'github token'
    required: false
    default: ''
  parameters:
    description: 'soup parameters'
    required: false
    default: '--no_prompt'
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
  php_unit_tests:
    name: PHP Unit Tests
    runs-on: ubuntu-latest
    needs:
      - variables
    if: "${{always() && needs.variables.outputs.SKIP_LICENSES != '1'}}"
    steps:
      - name: Licenses
        if: "${{(github.event_name == 'pull_request' || github.event_name == 'pull_request_target') && needs.variables.outputs.SKIP_LICENSES != '1'}}"
        uses: cloud-officer/ci-actions/soup@master
        with:
          ssh-key: "${{secrets.SSH_KEY}}"
          github-token: "${{secrets.GITHUB_TOKEN}}"
          parameters: "--no_prompt"
```
