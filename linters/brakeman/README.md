# GitHub Action: Run Brakeman Security Scanner

This action runs [Brakeman](https://brakemanscanner.org/), a static analysis security scanner
for Ruby on Rails applications, and fails the job on any warning that is not ignored.

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
  ruby-version:
    description: 'ruby version'
    required: false
    default: '4.0'
```

## Configuration

Create a `config/brakeman.yml` file in your repository to enable Brakeman and set its options:

```yml
---
:skip_checks:
  - CheckForceSSL
```

Brakeman reads `config/brakeman.yml` and `config/brakeman.ignore` itself. Use `brakeman -I` locally to
review warnings and record false positives in `config/brakeman.ignore`.

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
  brakeman:
    name: Brakeman Security Scanner
    runs-on: ubuntu-latest
    needs:
      - variables
    permissions:
      contents: read
    if: "${{(github.event_name == 'pull_request') || (github.event_name == 'pull_request_target')}}"
    steps:
      - name: Brakeman
        id: brakeman
        uses: cloud-officer/ci-actions/linters/brakeman@v3
        with:
          linters: "${{needs.variables.outputs.LINTERS}}"
          ssh-key: "${{secrets.SSH_KEY}}"
          github-token: "${{secrets.GITHUB_TOKEN}}"
```
