# GitHub Action: SOUP

This action publishes Docker image linux/amd64 and linux/arm64 to DockerHub.

## Inputs

```yml
inputs:
  github-token:
    description: 'github token'
    required: false
    default: ${{ github.token }}
  username:
    description: 'Username used to log against the Docker registry'
    required: true
  password:
    description: 'Password or personal access token used to log against the Docker registry'
    required: true
```

## Example usage

```yml
name: Publish Docker image
on:
  push:
    tags:
      - "**"
jobs:
  push_to_registry:
    name: Push Docker Image to Docker Hub
    runs-on: ubuntu-latest
    permissions:
      packages: write
      contents: read
      attestations: write
      id-token: write
    steps:
      - name: Publish Docker image
        uses: cloud-officer/ci-actions/docker@master
        with:
          username: ${{ secrets.DOCKER_USERNAME }}
          password: ${{ secrets.DOCKER_PASSWORD }}
```
