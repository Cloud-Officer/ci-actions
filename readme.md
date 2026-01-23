# ci-actions [![Build](https://github.com/Cloud-Officer/ci-actions/actions/workflows/build.yml/badge.svg)](https://github.com/Cloud-Officer/ci-actions/actions/workflows/build.yml)

## Table of Contents

* [Introduction](#introduction)
* [Installation](#installation)
* [Usage](#usage)
* [Contributing](#contributing)
* [Debugging](#debugging)

## Introduction

A collection of GitHub Actions for CI/CD workflows.

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

Nothing to install.

## Usage

* [aws](aws/README.md): Execute AWS CLI or shell commands
* [codedeploy](codedeploy/README.md): AWS CodeDeploy actions (checkout, deploy, s3copy)
* [docker](docker/README.md): Publish Docker images
* [linters](linters/README.md): Code quality linters for multiple languages
* [setup](setup/README.md): Setup tools for build environments
* [slack](slack/README.md): Send action status to Slack
* [soup](soup/README.md): Open source license compliance and SOUP list generation
* [variables](variables/README.md): Prepare variables for parallel jobs

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

When you submit code changes, your submissions are understood to be under the same [License](license) that covers the
project. Feel free to contact the maintainers if that's a concern.

## Debugging

Please refer to
the [Github Enabling debug logging guide](https://docs.github.com/en/github-ae@latest/actions/monitoring-and-troubleshooting-workflows/enabling-debug-logging)
to set secrets to enable runner and steps debug logs.

You can always enable a tmate debug session to connect to a running runner instance and try things manually if debug
logs are not enough. See [Debug your GitHub Actions by using tmate](https://github.com/mxschmitt/action-tmate).

The documentation for all the [runner environments](https://github.com/actions/virtual-environments/tree/main/images).
