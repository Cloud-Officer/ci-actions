# GitHub Action: AWS

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
    description: 'aws access key id; leave empty when aws-role-to-assume is set'
    required: false
  aws-secret-access-key:
    description: 'aws secret access key; leave empty when aws-role-to-assume is set'
    required: false
  aws-region:
    description: 'aws region'
    required: true
  aws-role-to-assume:
    description: 'ARN of the IAM role to assume with GitHub OIDC instead of access keys; the job needs permissions: id-token: write'
    required: false
  aws-audience:
    description: 'audience of the GitHub OIDC token'
    required: false
    default: 'sts.amazonaws.com'
  aws-role-session-name:
    description: 'session name recorded in CloudTrail for the assumed role'
    required: false
    default: 'GitHubActions'
  aws-role-duration-seconds:
    description: 'lifetime of the assumed role credentials, in seconds'
    required: false
    default: '3600'
  shell-commands:
    description: 'shell commands'
    required: true
```

## Authentication

Supply one of:

- **GitHub OIDC (recommended):** set `aws-role-to-assume` to an IAM role whose trust policy allows this repository,
  and grant the job `id-token: write`. No AWS secret is stored in GitHub, and the credentials expire after
  `aws-role-duration-seconds`.
- **Access keys:** set `aws-access-key-id` and `aws-secret-access-key`.

The action fails before running anything when neither a role nor a complete key pair is supplied.

```yml
  aws:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    steps:
      - name: AWS Commands
        uses: cloud-officer/ci-actions/aws@v3
        with:
          ssh-key: "${{secrets.SSH_KEY}}"
          aws-role-to-assume: "arn:aws:iam::123456789012:role/github-deploy"
          aws-region: "${{secrets.AWS_DEFAULT_REGION}}"
          shell-commands: 'aws sts get-caller-identity'
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
  aws:
    name: AWS
    runs-on: ubuntu-latest
    needs:
      - variables
    if: "(needs.variables.outputs.DEPLOY_ON_BETA == '1' || needs.variables.outputs.DEPLOY_ON_RC == '1' || needs.variables.outputs.DEPLOY_ON_PROD == '1')"
    steps:
      - name: AWS Commands
        uses: cloud-officer/ci-actions/aws@v3
        env:
          ECR_REPOSITORY: test
        with:
          ssh-key: "${{secrets.SSH_KEY}}"
          aws-access-key-id: "${{secrets.AWS_ACCESS_KEY_ID}}"
          aws-secret-access-key: "${{secrets.AWS_SECRET_ACCESS_KEY}}"
          aws-region: "${{secrets.AWS_DEFAULT_REGION}}"
          shell-commands: 'echo "${ECR_REPOSITORY}"'
```
