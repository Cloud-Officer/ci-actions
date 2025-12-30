# GitHub Action: Variables

This action prepare variables for all other parallel jobs.

## Inputs

```yml
inputs:
  github-token:
    description: 'github token'
    required: false
    default: ${{ github.token }}
  ssh-key:
    description: 'ssh key'
    required: true
```

## Outputs

```yml
outputs:
  BUILD_NAME:
    description: 'Build name'
    value:  ${{ steps.variables.outputs.BUILD_NAME }}
  BUILD_VERSION:
    description: 'Build version'
    value: ${{ steps.variables.outputs.BUILD_VERSION }}
  COMMIT_MESSAGE:
    description: 'Commit message'
    value: ${{ steps.variables.outputs.COMMIT_MESSAGE }}
  MODIFIED_GITHUB_RUN_NUMBER:
    description: 'Modified build number'
    value: ${{ steps.variables.outputs.MODIFIED_GITHUB_RUN_NUMBER }}
  DEPLOY_ON_BETA:
    description: 'Deploy code on beta'
    value: ${{ steps.variables.outputs.DEPLOY_ON_BETA }}
  DEPLOY_ON_RC:
    description: 'Deploy code on rc'
    value: ${{ steps.variables.outputs.DEPLOY_ON_RC }}
  DEPLOY_ON_PROD:
    description: 'Deploy code on prod'
    value: ${{ steps.variables.outputs.DEPLOY_ON_PROD }}
  DEPLOY_MACOS:
    description: 'Deploy code on macOS'
    value: ${{ steps.variables.outputs.DEPLOY_MACOS }}
  DEPLOY_TVOS:
    description: 'Deploy code on tvOS'
    value: ${{ steps.variables.outputs.DEPLOY_TVOS }}
  DEPLOY_OPTIONS:
    description: 'Deploy options'
    value: ${{ steps.variables.outputs.DEPLOY_OPTIONS }}
  SKIP_LICENSES:
    description: 'Skip open source licences check'
    value: ${{ steps.variables.outputs.SKIP_LICENSES }}
  SKIP_LINTERS:
    description: 'Skip linter checks'
    value: ${{ steps.variables.outputs.SKIP_LINTERS }}
  SKIP_TESTS:
    description: 'Skip unit tests'
    value: ${{ steps.variables.outputs.SKIP_TESTS }}
  UPDATE_PACKAGES:
    description: 'Update packages on instance'
    value: ${{ steps.variables.outputs.UPDATE_PACKAGES }}
  LINTERS:
    description: 'List of all enabled linters'
    value: ${{ steps.variables.outputs.LINTERS }}
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
      DEPLOY_OPTIONS: "${{steps.variables.outputs.DEPLOY_OPTIONS}}"
      SKIP_LICENSES: "${{steps.variables.outputs.SKIP_LICENSES}}"
      SKIP_LINTERS: "${{steps.variables.outputs.SKIP_LINTERS}}"
      SKIP_TESTS: "${{steps.variables.outputs.SKIP_TESTS}}"
      UPDATE_PACKAGES: "${{steps.variables.outputs.UPDATE_PACKAGES}}"
      LINTERS: "${{steps.variables.outputs.LINTERS}}"
    steps:
      - name: Prepare variables
        id: variables
        uses: cloud-officer/ci-actions/variables@master
        with:
          ssh-key: "${{secrets.SSH_KEY}}"
  actionlint:
    name: Github Actions Linter
    runs-on: ubuntu-latest
    needs:
      - variables
    if: "${{github.event_name == 'pull_request' || github.event_name == 'pull_request_target'}}"
    steps:
      - name: Actionlint
        id: actionlint
        uses: cloud-officer/ci-actions/linters/actionlint@master
        with:
          linters: "${{needs.variables.outputs.LINTERS}}"
          ssh-key: "${{secrets.SSH_KEY}}"
          github-token: "${{secrets.GITHUB_TOKEN}}"
```
