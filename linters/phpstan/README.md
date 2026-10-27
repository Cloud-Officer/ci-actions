# GitHub Action: Run phpstan

This action runs [phpstan](https://phpstan.org/).

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
  apt-packages:
    description: 'additional apt packages to install'
    required: false
    default: 'none'
  php-version:
    description: 'php version'
    required: false
    default: '8.2'
  php-extensions:
    description: 'php extensions'
    required: false
    default: ''
  php-packages:
    description: 'Apt packages installed with PHP from the Ubuntu archive instead of shivammathur/setup-php (see setup); php-extensions is then ignored'
    required: false
    default: ''
  php-apt-repository:
    description: 'S3 apt repository read when php-packages is set'
    required: false
    default: 's3://ugm-builds/apt'
  php-apt-key:
    description: 'S3 location of the ASCII-armored public key that signs php-apt-repository'
    required: false
    default: 's3://ugm-builds/apt/ugroupmedia-apt.asc'
  aws-region:
    description: 'AWS region, used with php-packages'
    required: false
  aws-role-to-assume:
    description: 'IAM role assumed through GitHub OIDC to read php-apt-repository'
    required: false
  aws-access-key-id:
    description: 'AWS access key ID to read php-apt-repository, when no role is set'
    required: false
  aws-secret-access-key:
    description: 'AWS secret access key, required with aws-access-key-id'
    required: false
  composer-command:
    description: 'composer command'
    required: false
    default: 'composer install'
  php-stan-command:
    description: 'php stan command(s)'
    required: false
    default: './vendor/bin/phpstan analyse'
```

With `php-packages`, PHP is installed from apt as described in the
[setup README](../../setup/README.md#php-from-apt); pass the AWS inputs and grant the job `id-token: write`. When the repository does not publish the
runner's Ubuntu release, setup-php installs PHP instead.

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
  phpstan:
    name: PHP Stan Linter
    runs-on: ubuntu-latest
    needs:
      - variables
    if: "${{needs.variables.outputs.SKIP_LINTERS != '1'}}"
    steps:
      - name: PHPStan
        id: phpstan
        uses: cloud-officer/ci-actions/linters/phpstan@v3
        with:
          linters: "${{needs.variables.outputs.LINTERS}}"
          ssh-key: "${{secrets.SSH_KEY}}"
          github-token: "${{secrets.GITHUB_TOKEN}}"
          php-version: "${{env.PHP-VERSION}}"
          php-extensions: "${{env.PHP-EXTENSIONS}}"
          composer-command: composer install --optimize-autoloader --no-interaction --no-suggest --prefer-dist
          php-stan-command: "./vendor/bin/phpstan analyse"
```
