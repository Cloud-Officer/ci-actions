# Architecture Design

## Table of Contents

- [Architecture diagram](#architecture-diagram)
- [Software units](#software-units)
- [Software of Unknown Provenance](#software-of-unknown-provenance)
- [Critical algorithms](#critical-algorithms)
- [Risk controls](#risk-controls)

## Architecture diagram

```text
+------------------+     +------------------+     +------------------+
|    variables     |---->|     linters      |---->|      slack       |
|  (prepare vars)  |     | (code analysis)  |     |  (notification)  |
+------------------+     +------------------+     +------------------+
         |                        |
         v                        v
+------------------+     +------------------+
|      setup       |     |       soup       |
| (env setup)      |     | (license check)  |
+------------------+     +------------------+
         |
         v
+------------------+     +------------------+     +------------------+
|       aws        |     |   codedeploy     |     |      docker      |
| (AWS commands)   |     | (AWS deployment) |     | (Docker publish) |
+------------------+     +------------------+     +------------------+
```

### Component Overview

This repository provides a collection of reusable GitHub Actions for continuous
integration workflows. The actions are organized as composite actions (YAML-based)
and JavaScript actions, designed to be referenced from other repositories'
workflows.

### Component Interactions

1. **variables** prepares build variables and detects enabled linters based on
   configuration files present in the target repository
2. **linters** run in parallel after variables, each checking if it should
   execute based on the LINTERS output
3. **setup** configures the build environment with required language runtimes
   and services
4. **aws**, **codedeploy**, and **docker** handle deployment tasks
5. **soup** validates open source licenses
6. **slack** sends build status notifications at workflow completion

## Software units

### aws

**Purpose:** Execute AWS CLI or shell commands with configured credentials.

**Location:** `aws/action.yml`

**Key Components:**

- Checkout repository with LFS and submodules
- Configure AWS credentials via `aws-actions/configure-aws-credentials`
- Execute arbitrary shell commands with AWS access

**Inputs:**

- `github-token`: GitHub token for checkout
- `ssh-key`: SSH key for private repository access
- `aws-access-key-id`, `aws-secret-access-key`, `aws-region`: AWS credentials
- `shell-commands`: Commands to execute

### cis

**Purpose:** CIS (Center for Internet Security) benchmark compliance resource.

**Location:** `cis/`

**Key Components:**

- `PolicyBanner.rtf`: Login policy banner for CIS benchmark compliance

### codedeploy

**Purpose:** AWS CodeDeploy operations including checkout, S3 copy, and deployment.

**Location:** `codedeploy/`

**Sub-actions:**

- `codedeploy/checkout/action.yml`: Repository checkout with LFS support
- `codedeploy/s3copy/action.yml`: Sync files to/from S3
- `codedeploy/deploy/action.yml`: Create and monitor CodeDeploy deployments

**Key Components:**

- AWS credential configuration
- S3 sync operations
- Deployment creation with status polling (5-second intervals, 119 iterations max)

### docker

**Purpose:** Build and publish Docker images to DockerHub.

**Location:** `docker/action.yml`

**Key Components:**

- Multi-platform builds (linux/amd64, linux/arm64)
- Docker Buildx setup with BuildKit
- Metadata extraction for tags and labels
- Build provenance attestation

**Inputs:**

- `username`, `password`: DockerHub credentials
- `github-token`: GitHub token

### linters

**Purpose:** Collection of code quality and security linters.

**Location:** `linters/`

**Available Linters:**

| Linter | Language/Purpose | Detection File |
| :--- | :--- | :--- |
| actionlint | GitHub Actions workflows | `.github/workflows/` |
| bandit | Python security | `.bandit` |
| cfnlint | AWS CloudFormation | `.cfnlintrc` |
| checkov | IaC security scanning | `.checkov.yaml` |
| eslint | JavaScript/TypeScript | `.eslintrc.json` |
| flake8 | Python style | `.flake8` |
| golangci | Go | `.golangci.yml` |
| hadolint | Dockerfile | `.hadolint.yaml` |
| ktlint | Kotlin | `.editorconfig` |
| markdownlint | Markdown | `.markdownlint.yml` |
| phpcs | PHP coding standards | `.php-cs-fixer.dist.php` |
| phpstan | PHP static analysis | `phpstan.neon` |
| pmd | Java/multi-language | `.pmd.xml` |
| protolint | Protocol Buffers | `.protolint.yaml` |
| rubocop | Ruby | `.rubocop.yml` |
| semgrep | Security scanning | `.semgrepignore` |
| shellcheck | Shell scripts | `.shellcheckrc` |
| swiftlint | Swift | `.swiftlint.yml` |
| trivy | Container & IaC vulnerability scanning | `.trivyignore` |
| yamllint | YAML | `.yamllint.yml` |

**Pattern:** Each linter action checks if it should run based on the `LINTERS`
input variable, which is populated by the variables action.

### setup

**Purpose:** Unified setup action for multiple language runtimes and services.

**Location:** `setup/action.yml`

**Supported Languages:**

- Go (with version file detection: `.go-version`)
- Java (with version file detection: `.java-version`)
- Node.js (with version file detection: `.nvmrc`, `.node-version`)
- PHP (with version file detection: `.php-version`)
- Python (with version file detection: `.python-version`)
- Ruby (with version file detection: `.ruby-version`)
- Android SDK
- Xcode (macOS only)

**Supported Services:**

- Elasticsearch
- MongoDB
- MySQL/MariaDB
- RabbitMQ
- Redis

**Features:**

- Automatic language version detection from version files
- Caching for Go, Gradle, Maven, Composer, PIP, Carthage, CocoaPods, SPM, Tuist
- AWS credential configuration
- SSH agent setup
- APT package installation

### slack

**Purpose:** Send build status notifications to Slack.

**Location:** `slack/`

**Key Components:**

- `action.yml`: Action definition (Node.js 24 runtime)
- `index.js`: Notification logic using Slack webhook

**Features:**

- Displays build metadata (repository, branch, commit, actor)
- Shows deployment flags (DEPLOY_ON_BETA, DEPLOY_ON_RC, etc.)
- Color-coded job status (success, failure, cancelled, skipped)

### soup

**Purpose:** Software of Unknown Provenance (SOUP) license validation.

**Location:** `soup/action.yml`

**Key Components:**

- Downloads and runs the Cloud-Officer/soup Ruby tool
- Validates open source licenses against project dependencies
- Generates/checks SOUP list

### variables

**Purpose:** Prepare environment variables for workflow jobs.

**Location:** `variables/`

**Key Components:**

- `action.yml`: Action definition
- `variables.sh`: Shell script for variable computation

**Outputs:**

- `BUILD_NAME`, `BUILD_VERSION`: Computed build identifiers
- `COMMIT_MESSAGE`: First line of commit message
- `MODIFIED_GITHUB_RUN_NUMBER`: Run number + 15000 offset
- `DEPLOY_ON_BETA`, `DEPLOY_ON_RC`, `DEPLOY_ON_PROD`: Deployment flags
- `DEPLOY_MACOS`, `DEPLOY_TVOS`: Platform flags
- `DEPLOY_OPTIONS`: Custom deployment options
- `SKIP_LICENSES`, `SKIP_LINTERS`, `SKIP_TESTS`: Skip flags
- `UPDATE_PACKAGES`: Package update flag
- `LINTERS`: Space-separated list of enabled linters

**Commit Message Triggers:**

- `#beta-deploy`: Enable beta deployment
- `#rc-deploy`: Enable RC deployment
- `#prod-deploy`: Enable production deployment (tags only)
- `#macos`, `#tvos`: Enable platform builds
- `#skip-all`: Skip licenses, linters, and tests
- `#skip-licenses`, `#skip-linters`, `#skip-tests`: Individual skip flags
- `#update-packages`: Update packages
- `#deploy-options=<value>`: Custom deployment options

## Software of Unknown Provenance

See [soup.md](soup.md) for the complete SOUP list.

### External Action Dependencies

The actions depend on the following third-party GitHub Actions (see individual action.yml
files for current versions):

| Action | Purpose |
| :--- | :--- |
| actions/checkout | Repository checkout |
| actions/setup-go | Go runtime setup |
| actions/setup-java | Java runtime setup |
| actions/setup-node | Node.js runtime setup |
| actions/setup-python | Python runtime setup |
| actions/cache | Dependency caching |
| actions/attest-build-provenance | Build attestation |
| aws-actions/configure-aws-credentials | AWS credential configuration |
| docker/login-action | Docker registry login |
| docker/setup-buildx-action | Docker Buildx setup |
| docker/metadata-action | Docker metadata extraction |
| docker/build-push-action | Docker build and push |
| ruby/setup-ruby | Ruby runtime setup |
| shivammathur/setup-php | PHP runtime setup |
| webfactory/ssh-agent | SSH agent setup |
| amyu/setup-android | Android SDK setup |
| maxim-lobanov/setup-xcode | Xcode setup |
| miyataka/elasticsearch-github-actions | Elasticsearch setup |
| supercharge/mongodb-github-action | MongoDB setup |
| shogo82148/actions-setup-mysql | MySQL setup |
| namoshek/rabbitmq-github-action | RabbitMQ setup |
| shogo82148/actions-setup-redis | Redis setup |
| reviewdog/action-eslint | ESLint with reviewdog |
| reviewdog/action-setup | Reviewdog CLI setup |
| reviewdog/action-golangci-lint | Go linting with reviewdog |
| reviewdog/action-yamllint | YAML linting with reviewdog |
| reviewdog/action-shellcheck | Shell script linting with reviewdog |
| reviewdog/action-hadolint | Dockerfile linting with reviewdog |
| reviewdog/action-rubocop | Ruby linting with reviewdog |
| reviewdog/action-actionlint | GitHub Actions linting with reviewdog |
| yoheimuta/action-protolint | Protocol Buffers linting |
| ScaCap/action-ktlint | Kotlin linting |
| norio-nomura/action-swiftlint | Swift linting |
| tj-actions/bandit | Python security linter |
| checkov (pip) | IaC security scanner |
| trivy (curl) | Container & IaC vulnerability scanner |
| cfn-lint (pip) | AWS CloudFormation linter |

## Critical algorithms

### Build Variable Computation

**Purpose:** Compute build identifiers and detect workflow configuration from
commit messages and repository state.

**Location:** `variables/variables.sh` in environment variable computation block

**Algorithm:**

1. Parse `GITHUB_REF` to determine if building a tag, PR, or branch
2. Compute `BUILD_NAME` with format:
   `{ref}-{short_commit}-{timestamp}-{modified_run_number}` and `BUILD_VERSION`
   with format: `{ref}-{modified_run_number}-{timestamp}`
3. Extract commit message (tag annotation or git log)
4. Parse commit message for trigger keywords (`#beta-deploy`, `#skip-linters`, etc.)
5. Detect enabled linters by checking for configuration files in the repository

**Complexity:** O(n) where n is the number of linter detection rules

### CodeDeploy Status Polling

**Purpose:** Monitor AWS CodeDeploy deployment until completion or timeout.

**Location:** `codedeploy/deploy/action.yml` in "Deploy to CodeDeploy" step

**Algorithm:**

1. Create deployment via AWS CLI
2. Poll deployment status every 5 seconds
3. Exit on terminal states: Succeeded, Failed, Stopped, Ready
4. Timeout after 119 iterations (~10 minutes)

**Complexity:** O(1) bounded by iteration limit

### Slack Message Construction

**Purpose:** Build Slack Block Kit message with job statuses.

**Location:** `slack/index.js`

**Algorithm:**

1. Parse jobs JSON input
2. Extract deployment flags from variables output
3. Iterate jobs to determine overall status and color
4. Construct Block Kit message with attachments

**Complexity:** O(j) where j is the number of jobs

## Risk controls

### Security Measures

#### Credential Handling

- AWS credentials passed via action inputs, not hardcoded
- SSH keys for private repository access
- GitHub tokens with minimal required permissions
- DockerHub credentials for registry authentication

#### Input Validation

- Linter detection uses file existence checks, not user input parsing
- Deployment flags extracted from controlled commit messages
- JSON parsing for Slack webhook payload

#### Repository Checkout Hardening

- `persist-credentials: false` on all checkout steps to prevent credential leakage
  (except setup action where credentials are required for Java GPG/Maven operations)

#### GPG Signature Verification

- phpcs: Downloads php-cs-fixer and verifies GPG signature before execution
- pmd: Downloads PMD release and verifies GPG signature before execution

#### Code Analysis

- Semgrep security scanning with `--error` flag
- Bandit Python security linting
- ESLint for JavaScript patterns
- Multiple language-specific linters for code quality

### Error Handling

| Component | Error Handling |
| :--- | :--- |
| CodeDeploy | Status polling with timeout, explicit failure states |
| Slack | Promise rejection handler with core.setFailed |
| Linters | Early exit if not enabled, reviewdog for PR comments |
| Setup | Conditional step execution based on inputs |

### Logging and Monitoring

- GitHub Actions native logging for all steps
- Slack notifications for build completion
- CodeDeploy deployment ID output for tracking
- Reviewdog integration for PR review comments

### Failure Modes

| Failure Mode | Impact | Mitigation |
| :--- | :--- | :--- |
| AWS credential expiration | Deployment fails | Use short-lived credentials, OIDC |
| Slack webhook unavailable | No notification | Non-blocking, error logged |
| Linter timeout | Job fails | 30-minute timeout per job |
| CodeDeploy stuck | Monitoring exits | 10-minute polling timeout |
| Docker build failure | No image published | Build logs available |
| Private repo access denied | Checkout fails | SSH key validation |

### Permissions

The build workflow uses minimal permissions:

```yaml
permissions:
  contents: read
  pull-requests: read
```
