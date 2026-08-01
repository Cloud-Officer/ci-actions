# GitHub Action: Run swiftLint

This action runs [swiftLint](https://github.com/realm/SwiftLint).

SwiftLint is installed straight from the upstream
[realm/SwiftLint](https://github.com/realm/SwiftLint) release (the statically
linked `swiftlint-static` binary from `swiftlint_linux_{amd64,arm64}.zip`, so no
Swift toolchain is required on the runner) and its output is reported through
[reviewdog](https://github.com/reviewdog/reviewdog) like the other linters.

It previously used
[norio-nomura/action-swiftlint](https://github.com/norio-nomura/action-swiftlint),
whose last release (3.2.1, 2020) pinned an unmaintained Swift 5 Docker image and
could never be advanced by the weekly external-actions bump.

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
  swiftlint-version:
    description: 'swiftlint release tag to install, or "latest"'
    required: false
    default: 'latest'
```

By default the latest upstream release is installed. Set `swiftlint-version` to
a release tag (for example `0.65.0`) to pin a consumer repository to a specific
SwiftLint version.

`lint --strict` is used, so any violation is an error; reviewdog is run with
`-fail-level=any`, which fails the job on any reported violation.

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
  swiftlint:
    name: Swift Linter
    runs-on: ubuntu-latest
    needs:
      - variables
    steps:
      - name: Swiftlint
        id: swiftlint
        uses: cloud-officer/ci-actions/linters/swiftlint@v2
        with:
          linters: "${{needs.variables.outputs.LINTERS}}"
          ssh-key: "${{secrets.SSH_KEY}}"
          github-token: "${{secrets.GITHUB_TOKEN}}"
```
