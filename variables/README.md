# GitHub Action: Variables

This action prepares variables for all other parallel jobs.

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
    value: ${{ steps.variables.outputs.BUILD_NAME }}
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

## Commit Message Triggers

The variables action parses commit messages and tag annotations for special trigger keywords. Include these in your commit message or tag to control workflow behavior:

### Deployment Triggers

| Trigger                   | Output Variable          | Description                             |
|---------------------------|--------------------------|-----------------------------------------|
| `#beta-deploy`            | `DEPLOY_ON_BETA=1`       | Deploy to beta environment              |
| `#rc-deploy`              | `DEPLOY_ON_RC=1`         | Deploy to release candidate environment |
| `#prod-deploy`            | `DEPLOY_ON_PROD=1`       | Deploy to production (requires tag)     |
| `#macos`                  | `DEPLOY_MACOS=1`         | Enable macOS deployment                 |
| `#tvos`                   | `DEPLOY_TVOS=1`          | Enable tvOS deployment                  |
| `#deploy-options=<value>` | `DEPLOY_OPTIONS=<value>` | Pass custom deployment options          |

### Skip Triggers

| Trigger          | Output Variable         | Description                       |
|------------------|-------------------------|-----------------------------------|
| `#skip-licenses` | `SKIP_LICENSES=1`       | Skip open source license checks   |
| `#skip-linters`  | `SKIP_LINTERS=1`        | Skip linter checks                |
| `#skip-tests`    | `SKIP_TESTS=1`          | Skip unit tests                   |
| `#skip-all`      | All skip flags set to 1 | Skip licenses, linters, and tests |

### Other Triggers

| Trigger            | Output Variable     | Description                 |
|--------------------|---------------------|-----------------------------|
| `#update-packages` | `UPDATE_PACKAGES=1` | Update packages on instance |

### Example Commit Messages

```bash
# Deploy to beta
git commit -m "Add new feature #beta-deploy"

# Skip tests for documentation changes
git commit -m "Update README #skip-tests"

# Production deploy with options (on a tag)
git tag -a v1.0.0 -m "Release v1.0.0 #prod-deploy #deploy-options=--force"

# Skip all checks for urgent hotfix
git commit -m "Emergency fix #skip-all #beta-deploy"
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
