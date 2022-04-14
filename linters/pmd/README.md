# GitHub Action: Run pmd with reviewdog

This action runs [pmd](https://github.com/pmd/pmd) with
[reviewdog](https://github.com/reviewdog/reviewdog) on pull requests to improve
code review experience.

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
  pmd:
    name: Java Linter
    runs-on: ubuntu-latest
    needs:
      - variables
    if: "${{github.event_name == 'pull_request' || github.event_name == 'pull_request_target'}}"
    steps:
      - name: PMD
        id: pmd
        uses: cloud-officer/ci-actions/linters/pmd@master
        with:
          linters: "${{needs.variables.outputs.LINTERS}}"
          ssh-key: "${{secrets.SSH_KEY}}"
          github_token: "${{secrets.GITHUB_TOKEN}}"
```
