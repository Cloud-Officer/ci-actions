# ci-actions

A collection of Github Actions for CI.

## Repository structure

* [codedeploy](codedeploy/README.md): Github Actions for AWS CodeDeploy
* [jira](jira/README.md): Github Action to integrate Dependabot with Jira
* [licenses](licenses/README.md): Github Action for open source licenses check with snyk
* [linters](linters/README.md): Github Actions for various linters
* [setup](setup/README.md): Github Action to setup tools all at once
* [slack](slack/README.md): Github Action to report build status to slack
* [variables](variables/README.md): Github Action to prepare environment variables for subsequent steps

## Debugging

Please refer to the [Github Enabling debug logging guide](https://docs.github.com/en/github-ae@latest/actions/monitoring-and-troubleshooting-workflows/enabling-debug-logging) to set secrets to enable runner and steps debug logs.

You can always enable a tmate debug session to connect to a running runner instance and try things manually if debug logs are not enough. See [Debug your GitHub Actions by using tmate](https://github.com/mxschmitt/action-tmate).

The documentation for all the runner environments is available [here](https://github.com/actions/virtual-environments/tree/main/images).
