# GitHub Action: Deploy

This action executes AWS CLI or shell commands.

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
  aws-access-key-id:
    description: 'aws access key id'
    required: true
  aws-secret-access-key:
    description: 'aws secret access key'
    required: true
  aws-region:
    description: 'aws region'
    required: true
  shell-commands:
    description: 'shell commands'
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
  aws:
    name: AWS
    runs-on: ubuntu-latest
    needs:
      - variables
    if: "(needs.variables.outputs.DEPLOY_ON_BETA == '1' || needs.variables.outputs.DEPLOY_ON_RC == '1' || needs.variables.outputs.DEPLOY_ON_PROD == '1')"
    steps:
      - name: AWS Commands
        uses: cloud-officer/ci-actions/aws@master
        env:
          ECR_REPOSITORY: test
        with:
          ssh-key: "${{secrets.SSH_KEY}}"
          aws-access-key-id: "${{secrets.AWS_ACCESS_KEY_ID}}"
          aws-secret-access-key: "${{secrets.AWS_SECRET_ACCESS_KEY}}"
          aws-region: "${{secrets.AWS_DEFAULT_REGION}}"
          shell-commands: 'echo "${ECR_REPOSITORY}"'
```
