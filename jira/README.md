# GitHub Action: Jira

This action creates a Jira ticket on Dependabot pull request.

## Inputs

```yml
inputs:
  base-url:
    description: 'Base URL'
    required: true
  user-email:
    description: 'User email'
    required: true
  api-token:
    description: 'API token'
    required: true
  project:
    description: 'project'
    required: true
  issue-type:
    description: 'Issue type'
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
  dependabot:
    name: Dependabot
    runs-on: ubuntu-latest
    if: "${{(github.event_name == 'pull_request' || github.event_name == 'pull_request_target') && github.event.pull_request.user.login == 'dependabot[bot]'}}"
    steps:
      - name: Dependabot
        uses: cloud-officer/ci-actions/jira@master
        with:
          base-url: "${{ secrets.JIRA_BASE_URL }}"
          user-email: "${{ secrets.JIRA_USER_EMAIL }}"
          api-token: "${{ secrets.JIRA_API_TOKEN }}"
          project: "${{ secrets.JIRA_PROJECT }}"
          issue-type: "${{ secrets.JIRA_ISSUE_TYPE }}"
```
