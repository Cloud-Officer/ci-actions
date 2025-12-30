# GitHub Action: S3Copy

This action uploads an archive to an AWS S3 bucket.

## Inputs

```yml
inputs:
  github-token:
    description: 'github token'
    required: false
    default: ${{ github.token }}
  aws-access-key-id:
    description: 'aws access key id'
    required: true
  aws-secret-access-key:
    description: 'aws secret access key'
    required: true
  aws-region:
    description: 'aws region'
    required: true
  source:
    description: 'aws s3 sync source'
    required: true
  target:
    description: 'aws s3 sync target'
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
      uses: cloud-officer/ci-actions/variables@master
      with:
        ssh-key: "${{secrets.SSH_KEY}}"
  code_deploy:
    name: Code Deploy
    runs-on: ubuntu-latest
    needs:
      - variables
    if: "${{always() && (needs.variables.outputs.DEPLOY_ON_BETA == '1' || needs.variables.outputs.DEPLOY_ON_RC == '1' || needs.variables.outputs.DEPLOY_ON_PROD == '1') && needs.php_unit_tests.result != 'failure' && needs.python_unit_tests.result != 'failure'}}"
    steps:
      - name: Checkout
        uses: cloud-officer/ci-actions/codedeploy/checkout@master
        if: "${{needs.variables.outputs.DEPLOY_ON_BETA == '1' || needs.variables.outputs.DEPLOY_ON_RC == '1' || needs.variables.outputs.DEPLOY_ON_PROD == '1'}}"
        with:
          ssh-key: "${{secrets.SSH_KEY}}"
      - name: Update Packages
        shell: bash
        if: "${{needs.variables.outputs.UPDATE_PACKAGES == '1'}}"
        run: touch update-packages
      - name: Setup
        uses: cloud-officer/ci-actions/setup@master
        if: "${{needs.variables.outputs.DEPLOY_ON_BETA == '1' || needs.variables.outputs.DEPLOY_ON_RC == '1' || needs.variables.outputs.DEPLOY_ON_PROD == '1'}}"
        with:
          php-version: "${{env.PHP-VERSION}}"
          php-extensions: "${{env.PHP-EXTENSIONS}}"
          php-ini-values: "${{env.PHP-INI-VALUES}}"
          php-coverage: "${{env.PHP-COVERAGE}}"
          php-tools: "${{env.PHP-TOOLS}}"
          ssh-key: "${{secrets.SSH_KEY}}"
          aws-access-key-id: "${{secrets.AWS_ACCESS_KEY_ID}}"
          aws-secret-access-key: "${{secrets.AWS_SECRET_ACCESS_KEY}}"
          aws-region: "${{secrets.AWS_DEFAULT_REGION}}"
      - name: Composer
        shell: bash
        if: "${{needs.variables.outputs.DEPLOY_ON_BETA == '1' || needs.variables.outputs.DEPLOY_ON_RC == '1' || needs.variables.outputs.DEPLOY_ON_PROD == '1'}}"
        run: |
          export COMPOSER_MEMORY_LIMIT=-1
          export APP_ENV=test
          cp -f .ci/.env.test.local .env.test.local
          composer install --optimize-autoloader --no-interaction --prefer-dist
      - name: Zip
        shell: bash
        if: "${{needs.variables.outputs.DEPLOY_ON_BETA == '1' || needs.variables.outputs.DEPLOY_ON_RC == '1' || needs.variables.outputs.DEPLOY_ON_PROD == '1'}}"
        run: |
          echo "${{needs.variables.outputs.BUILD_NAME}}" > ./public/version.txt
          rm -rf var/cache/* var/log/*
          zip --quiet --recurse-paths "${{needs.variables.outputs.BUILD_NAME}}.zip" ./* ./.env --exclude ./docs
          mkdir deployment
          mv "${{needs.variables.outputs.BUILD_NAME}}.zip" "deployment/${{needs.variables.outputs.BUILD_NAME}}.zip"
      - name: S3Copy
        uses: cloud-officer/ci-actions/codedeploy/s3copy@master
        if: "${{needs.variables.outputs.DEPLOY_ON_BETA == '1' || needs.variables.outputs.DEPLOY_ON_RC == '1' || needs.variables.outputs.DEPLOY_ON_PROD == '1'}}"
        with:
          aws-access-key-id: "${{secrets.AWS_ACCESS_KEY_ID}}"
          aws-secret-access-key: "${{secrets.AWS_SECRET_ACCESS_KEY}}"
          aws-region: "${{secrets.AWS_DEFAULT_REGION}}"
          source: deployment
          target: s3://${{secrets.CODEDEPLOY_BUCKET}}/${GITHUB_REPOSITORY}
  beta_deploy:
    name: Beta Deploy
    runs-on: ubuntu-latest
    needs:
      - variables
      - code_deploy
    if: "${{always() && needs.code_deploy.result == 'success' && needs.variables.outputs.DEPLOY_ON_BETA == '1'}}"
    steps:
      - name: Beta Deploy
        uses: cloud-officer/ci-actions/codedeploy/deploy@master
        with:
          aws-access-key-id: "${{secrets.AWS_ACCESS_KEY_ID}}"
          aws-secret-access-key: "${{secrets.AWS_SECRET_ACCESS_KEY}}"
          aws-region: "${{secrets.AWS_DEFAULT_REGION}}"
          application-name: api
          deployment-group-name: beta
          s3-bucket: "${{secrets.CODEDEPLOY_BUCKET}}"
          s3-key: "${GITHUB_REPOSITORY}/${{needs.variables.outputs.BUILD_NAME}}.zip"
  rc_deploy:
    name: Rc Deploy
    runs-on: ubuntu-latest
    needs:
      - variables
      - code_deploy
    if: "${{always() && needs.code_deploy.result == 'success' && needs.variables.outputs.DEPLOY_ON_RC == '1'}}"
    steps:
      - name: Rc Deploy
        uses: cloud-officer/ci-actions/codedeploy/deploy@master
        with:
          aws-access-key-id: "${{secrets.AWS_ACCESS_KEY_ID}}"
          aws-secret-access-key: "${{secrets.AWS_SECRET_ACCESS_KEY}}"
          aws-region: "${{secrets.AWS_DEFAULT_REGION}}"
          application-name: api
          deployment-group-name: rc
          s3-bucket: "${{secrets.CODEDEPLOY_BUCKET}}"
          s3-key: "${GITHUB_REPOSITORY}/${{needs.variables.outputs.BUILD_NAME}}.zip"
  prod_deploy:
    name: Prod Deploy
    runs-on: ubuntu-latest
    needs:
      - variables
      - code_deploy
    if: "${{always() && needs.code_deploy.result == 'success' && needs.variables.outputs.DEPLOY_ON_PROD == '1'}}"
    steps:
      - name: Prod Deploy
        uses: cloud-officer/ci-actions/codedeploy/deploy@master
        with:
          aws-access-key-id: "${{secrets.AWS_ACCESS_KEY_ID}}"
          aws-secret-access-key: "${{secrets.AWS_SECRET_ACCESS_KEY}}"
          aws-region: "${{secrets.AWS_DEFAULT_REGION}}"
          application-name: api
          deployment-group-name: prod
          s3-bucket: "${{secrets.CODEDEPLOY_BUCKET}}"
          s3-key: "${GITHUB_REPOSITORY}/${{needs.variables.outputs.BUILD_NAME}}.zip"
```
