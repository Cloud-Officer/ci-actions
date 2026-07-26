# ci-actions [![Build](https://github.com/Cloud-Officer/ci-actions/actions/workflows/build.yml/badge.svg)](https://github.com/Cloud-Officer/ci-actions/actions/workflows/build.yml)

## Table of Contents

* [Introduction](#introduction)
* [Installation](#installation)
* [Usage](#usage)
* [Contributing](#contributing)

## Introduction

A collection of composite GitHub Actions for CI/CD workflows. Instead of re-implementing the same setup, linting, packaging
and deployment steps in every repository, workflows reference these actions and get a consistent, maintained implementation.

It is intended for teams that build and deploy multiple repositories with GitHub Actions and want a single place to keep
their build environment setup, code quality gates and deployment steps.

### Features

* **Setup**: Unified tool setup for consistent build environments
* **Linters**: Code quality checks for multiple languages (Python, Go, PHP, Ruby, Swift, Kotlin, and more)
* **Docker**: Build and publish Docker images to DockerHub
* **AWS**: Execute AWS CLI or shell commands
* **CodeDeploy**: AWS CodeDeploy integration for deployments
* **Slack**: Build status notifications
* **SOUP**: Open source license compliance and dependency tracking
* **Variables**: Environment variable preparation for parallel jobs

## Installation

### Prerequisites

* A GitHub repository with GitHub Actions enabled
* An SSH deploy key stored as a repository secret (for example `SSH_KEY`) — the `variables` action requires it, and `setup`
  uses it to check out private dependencies

There is nothing to install: the actions are referenced directly from this repository by your workflow files.

### Reference an action

```yaml
uses: Cloud-Officer/ci-actions/setup@v2
```

The floating `v2` tag always points at the latest 2.x release. Pin to an immutable release tag (for example `2.1.4`) when you
need reproducible builds.

### Verify

Add a job that runs the `variables` action and confirm it succeeds:

```yaml
jobs:
  variables:
    name: Prepare Variables
    runs-on: ubuntu-latest
    steps:
      - name: Prepare variables
        id: variables
        uses: Cloud-Officer/ci-actions/variables@v2
        with:
          ssh-key: "${{secrets.SSH_KEY}}"
```

A successful run exposes outputs such as `BUILD_NAME`, `BUILD_VERSION` and `LINTERS` for the downstream jobs.

See individual action documentation below for detailed inputs and examples.

## Usage

### Available Actions

* [aws](aws/README.md): Execute AWS CLI or shell commands
* [codedeploy](codedeploy/README.md): AWS CodeDeploy actions (checkout, deploy, s3copy)
* [docker](docker/README.md): Build and publish Docker images
* [linters](linters/README.md): Code quality linters for multiple languages
* [setup](setup/README.md): Setup tools for build environments
* [slack](slack/README.md): Send action status to Slack
* [soup](soup/README.md): Open source license compliance and SOUP list generation
* [variables](variables/README.md): Prepare variables for parallel jobs

The `codedeploy` and `linters` entries are groups of sub-actions (`codedeploy/checkout`, `linters/rubocop`, and so on);
see their READMEs for the full list.

### CI Control Flags

Control CI behavior by adding these flags to your commit message:

| Flag                      | Description                         |
|---------------------------|-------------------------------------|
| `#beta-deploy`            | Deploy to beta environment          |
| `#rc-deploy`              | Deploy to RC environment            |
| `#prod-deploy`            | Deploy to production (requires tag) |
| `#macos`                  | Enable macOS deployment             |
| `#tvos`                   | Enable tvOS deployment              |
| `#skip-licenses`          | Skip license checks                 |
| `#skip-linters`           | Skip linter checks                  |
| `#skip-tests`             | Skip tests                          |
| `#skip-all`               | Skip licenses, linters, and tests   |
| `#update-packages`        | Update packages                     |
| `#deploy-options=<value>` | Pass deployment options             |

Example commit message:

```text
Add new feature #beta-deploy #skip-tests
```

### Debugging

Please refer to the [Github Enabling debug logging guide](https://docs.github.com/en/actions/monitoring-and-troubleshooting-workflows/enabling-debug-logging)
to set secrets to enable runner and steps debug logs.

You can always enable a tmate debug session to connect to a running runner instance and try things manually if debug logs are not enough. See [Debug your GitHub Actions by using tmate](https://github.com/mxschmitt/action-tmate).

The documentation for all the [runner environments](https://github.com/actions/runner-images/tree/main/images).

### Design Documentation

* [Architecture](docs/architecture.md): action topology, software units and risk controls
* [SOUP list](docs/soup.md): software of unknown provenance and license inventory

## Contributing

We love your input! We want to make contributing to this project as easy and transparent as possible, whether it's:

* Reporting a bug
* Discussing the current state of the code
* Submitting a fix
* Proposing new features
* Becoming a maintainer

Pull requests are the best way to propose changes to the codebase. We actively welcome your pull requests:

1. Fork the repo and create your branch from `master`.
2. If you've added code that should be tested, add tests. Ensure the test suite passes.
3. Update the documentation.
4. Make sure your code lints.
5. Issue that pull request!

When you submit code changes, your submissions are understood to be under the same [License](LICENSE) that covers the project. Feel free to contact the maintainers if that's a concern.
