# ci-actions [![Build](https://github.com/Cloud-Officer/ci-actions/actions/workflows/build.yml/badge.svg)](https://github.com/Cloud-Officer/ci-actions/actions/workflows/build.yml)

## Table of Contents

* [Introduction](#introduction)
* [Installation](#installation)
* [Usage](#usage)
* [Contributing](#contributing)
* [Debugging](#debugging)

## Introduction

A collection of Github Actions for CI.

## Installation

Nothing to install.

## Usage

* [aws](aws/README.md): GenericAWS CLI or shell commands
* [codedeploy](codedeploy/README.md): Github Actions for AWS CodeDeploy
* [docker](docker/README.md): Github Actions for DockerHub
* [linters](linters/README.md): Github Actions for various linters
* [setup](setup/README.md): Github Action to setup tools all at once
* [slack](slack/README.md): Github Action to report build status to slack
* [soup](soup/README.md): Github Action for open source licenses check and can generate/check the SOUP list against
  dependencies
* [variables](variables/README.md): Github Action to prepare environment variables for subsequent steps

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
