# GitHub Action: Slack

This action sends action status to Slack.

## Requirements

This action runs on the GitHub Actions **Node 24** runtime
(`runs.using: 'node24'`). GitHub-hosted runners include it; **self-hosted
runners must have Node 24 installed**, otherwise the action fails to start.
Track GitHub's runtime deprecation schedule before bumping.

## Inputs

```yml
inputs:
  github-token:
    description: 'github token'
    required: false
    default: ${{ github.token }}
  webhook-url:
    description: 'Slack incoming webhook URL'
    required: true
  jobs:
    description: 'Jobs'
    required: true
```

### `jobs` shape

`jobs` is a JSON-encoded **object keyed by job name** — pass `${{toJSON(needs)}}`.
Each value is an object; the action reads `result` (one of `success`,
`failure`, `cancelled`, `skipped`) and, for the `variables` job, an `outputs`
map of `'0'`/`'1'` deploy/skip flags:

```json
{
  "variables": { "result": "success", "outputs": { "DEPLOY_ON_BETA": "1" } },
  "build": { "result": "success" },
  "test": { "result": "failure" }
}
```

The action fails fast with an actionable message if `jobs` is not an object
(array, string, null) or if any entry is not an object.

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
        uses: cloud-officer/ci-actions/variables@v2
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
        uses: cloud-officer/ci-actions/linters/actionlint@v2
        with:
          linters: "${{needs.variables.outputs.LINTERS}}"
          ssh-key: "${{secrets.SSH_KEY}}"
          github-token: "${{secrets.GITHUB_TOKEN}}"
  slack:
    name: Publish Statuses
    runs-on: ubuntu-latest
    needs:
      - variables
      - actionlint
    if: always()
    steps:
      - name: Publish Statuses
        uses: cloud-officer/ci-actions/slack@v2
        with:
          webhook-url: "${{secrets.SLACK_WEBHOOK_URL}}"
          jobs: "${{toJSON(needs)}}"
```
