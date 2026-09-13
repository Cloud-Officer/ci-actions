# GitHub Action: DockerHub

This action builds Docker images and, by default, publishes them for linux/amd64 and linux/arm64 to DockerHub. With
`push: 'false'` it only builds the image, which needs no registry credentials and is suited to pull request checks.

## Inputs

```yml
inputs:
  github-token:
    description: 'github token'
    required: false
    default: ${{ github.token }}
  username:
    description: 'Username used to log against the Docker registry (required when push is true)'
    required: false
    default: ''
  password:
    description: 'Password or personal access token used to log against the Docker registry (required when push is true)'
    required: false
    default: ''
  push:
    description: 'Publish the image to DockerHub (true) or only build it (false)'
    required: false
    default: 'true'
  platforms:
    description: 'Comma separated list of target platforms'
    required: false
    default: 'linux/amd64,linux/arm64'
  context:
    description: 'Build context'
    required: false
    default: '.'
  file:
    description: 'Path to the Dockerfile'
    required: false
    default: './Dockerfile'
```

Builds use the GitHub Actions BuildKit cache, scoped per `platforms` value so parallel single-platform builds do not
overwrite each other's cache.

## Example usage

### Publish on tags

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
      contents: read
      attestations: write
      id-token: write
    steps:
      - name: Publish Docker image
        uses: cloud-officer/ci-actions/docker@v3
        with:
          username: ${{ secrets.DOCKER_USERNAME }}
          password: ${{ secrets.DOCKER_PASSWORD }}
```

### Build only on pull requests

```yml
name: Build
on:
  pull_request:
jobs:
  docker_build_amd64:
    name: Docker Build (amd64)
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - name: Build Docker image
        uses: cloud-officer/ci-actions/docker@v3
        with:
          push: 'false'
          platforms: linux/amd64
  docker_build_arm64:
    name: Docker Build (arm64)
    runs-on: ubuntu-24.04-arm
    permissions:
      contents: read
    steps:
      - name: Build Docker image
        uses: cloud-officer/ci-actions/docker@v3
        with:
          push: 'false'
          platforms: linux/arm64
```
