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

Maintenance utility (out of band, weekly cron — not part of the build pipeline):

+----------------------------------------------------------------+
|                          bump-actions                          |
| (scan YAML for external action refs, bump to latest upstream)  |
+----------------------------------------------------------------+

Verification harness (runs against this repository's own actions):

+----------------------------------------------------------------+
|                    tests + .github/workflows                   |
| (action.yml contract checks, bats suites, smoke workflow)      |
+----------------------------------------------------------------+
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
7. **bump-actions** runs out of band on a weekly cron (not part of the build
   pipeline) to keep external GitHub Action references up to date
8. **tests** and the hand-maintained smoke workflow validate this repository's
   own actions; they are not consumed by downstream repositories

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

### bump-actions

**Purpose:** Keep external GitHub Action references current by scanning
hand-maintained YAML and bumping each `uses: org/repo@ref` to its latest
upstream version. Powers the weekly external-actions bump cron (issue #212).

**Location:** `bump-actions/bump-actions.sh`

**Key Components:**

- `target_files`: list candidate YAML, skipping vendor dirs and
  github-build-generated files
- `extract_refs`: emit unique external refs, excluding `./` local and
  `cloud-officer/*` refs
- `resolve_bump`: resolve the new ref for a current ref (floating major,
  exact semver, or no-op)
- `main`: dry-run report by default; `--apply` rewrites refs in place and
  `--pr-body-file` writes a bump table with upstream release notes

**Invocation:** Run out of band by `.github/workflows/external-actions-bump.yml`
(weekly cron); unit-tested via `bump-actions/tests/bump-actions.bats`. Requires
an authenticated `gh` on PATH and bash 4 or newer: `main` uses `mapfile`, so on
direct execution the script re-execs under the first bash 4+ found in
`/opt/homebrew/bin`, `/usr/local/bin` or `/usr/bin` (and fails loudly if none
exists) rather than silently scanning an empty file list under macOS bash 3.2.
The guard is skipped when the file is sourced, so the bats suite is unaffected.

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
  (polling logic extracted to `codedeploy/deploy/deploy.sh`)

**Key Components:**

- AWS credential configuration
- S3 sync operations
- Deployment creation with status polling (5-second intervals; monitoring
  window configurable via the `monitor-timeout-minutes` input, default 30)

**Tests:** `codedeploy/tests/deploy.bats` sources `deploy.sh` and exercises
`create_deployment`/`poll_deployment` against a stubbed AWS CLI.

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
| eslint | JavaScript/TypeScript | `.eslintrc.json` |
| flake8 | Python style | `.flake8` |
| golangci | Go | `.golangci.yml` |
| hadolint | Dockerfile | `.hadolint.yaml` |
| ktlint | Kotlin | `.editorconfig` |
| markdownlint | Markdown | `.markdownlint-cli2.yaml` or `.markdownlint.yml` |
| phpcs | PHP coding standards | `.php-cs-fixer.dist.php` |
| phpstan | PHP static analysis | `phpstan.neon` |
| pmd | Java/multi-language | `.pmd.xml` |
| protolint | Protocol Buffers | `.protolint.yaml` |
| rubocop | Ruby | `.rubocop.yml` |
| semgrep | Security scanning | `.semgrepignore` |
| shellcheck | Shell scripts | `.shellcheckrc` |
| swiftlint | Swift | `.swiftlint.yml` |
| trivy | Container & IaC vulnerability scanning | IaC or package manager files |
| yamllint | YAML | `.yamllint.yml` |

**Pattern:** Each linter action checks if it should run based on the `LINTERS`
input variable, which is populated by the variables action.

**Shared helpers (`linters/_lib/`):**

- `check_enabled.sh`: invoked by every linter action via
  `${GITHUB_ACTION_PATH}/../_lib/check_enabled.sh <NAME>` to gate execution on
  whether `<NAME>` appears (as a whole word) in the `LINTERS` list
- `lock_files.sh`: single source of truth for the package-manager lock/manifest
  files (`TRIVY_LOCK_FILES`) that mark a project for a Trivy vulnerability scan.
  Sourced by both `variables/variables.sh` (`detect_trivy`) and
  `linters/trivy/action.yml` so the list never drifts;
  `tests/lock_file_contract.py` asserts neither consumer re-introduces a
  hardcoded copy
- `clean_workspace.sh`: workspace cleanup for the two linters that lint the
  whole checkout (markdownlint, yamllint). Deletes the submodule checkouts
  listed in `.gitmodules` plus any extra directory names passed as arguments
  (markdownlint passes `vendor node_modules Libraries`). The `scripts`
  submodule is deliberately kept: github-build symlinks the root linter config
  files to `<scripts>/linters/<config>`, so removing it would leave those
  symlinks dangling and the linter would run unconfigured. Covered by
  `linters/tests/clean_workspace.bats`
- `recv_gpg_key.sh`: fetches a GPG public key with retries and keyserver
  fallback (used by phpcs and pmd before signature verification)
- `install_swiftlint.sh`: resolves a realm/SwiftLint release (pinned via the
  `swiftlint-version` input, `latest` by default), downloads the matching
  `swiftlint_linux_{amd64,arm64}.zip` and installs the statically linked
  binary, so the swiftlint action needs no Swift toolchain and no third-party
  action. Replaced the unmaintained `norio-nomura/action-swiftlint@3.2.1`
  (last released 2020); unit-tested by `linters/tests/install_swiftlint.bats`

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
- Caching for Go, Gradle, Maven, Node.js, Composer, PIP, Bundler, Carthage,
  CocoaPods, SPM, Tuist, Android
- AWS credential configuration
- SSH agent setup
- APT package installation

### slack

**Purpose:** Send build status notifications to Slack.

**Location:** `slack/`

**Key Components:**

- `action.yml`: Action definition (`using: node24`, entry point `dist/index.js`)
- `index.js`: Notification logic using Slack webhook (`parseInputs`,
  `validateJobs`, `buildHeaderAttachment`, `buildJobAttachments`,
  `sendWebhook`, `run`)
- `dist/index.js`: Committed `@vercel/ncc` bundle actually executed by the
  runner; the `pretest` script rebuilds it and fails on `git diff` so the
  bundle can never drift from the source
- `index.test.js`: Jest suite with coverage thresholds enforced in
  `package.json` (100% functions, 90% lines/statements, 80% branches)

**Features:**

- Displays build metadata (repository, branch, commit, actor)
- Shows enabled variable flags (DEPLOY_\*, SKIP_\*, UPDATE_\*)
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

**Tests:** `variables/tests/variables.bats` sources `variables.sh` (guarded by
the `BASH_SOURCE`/`$0` check so `main` does not run) and covers the tag, PR-head
and branch paths plus the `detect_trivy`/`add_linter_if_*` predicates.

### tests

**Purpose:** Repository-level contract checks for actions that cannot be run
end-to-end in CI without secrets or side effects.

**Location:** `tests/`

**Key Components:**

- `action_contracts.py`: parses every `action.yml` in the repository (28 as of
  writing) and asserts each is a well-formed composite/JS/Docker action —
  required top-level keys, input mappings with descriptions, a valid
  `runs.using`, and a `shell:` on every `run:` step
- `lock_file_contract.py`: asserts `variables/variables.sh` and
  `linters/trivy/action.yml` both consume `linters/_lib/lock_files.sh` instead
  of re-introducing a hardcoded lock-file list
- `fail_fast_contract.py`: asserts every nested `bash … -c` call site in an
  `action.yml` carries `-e` and `-o pipefail`. A composite step's own shell
  options are not inherited by the inner interpreter, so a bare `bash -c`
  running a user-supplied multi-line command string reports only the last
  command's exit status (BUG-003)
- `linters_readme_template_contract.py`: asserts the "Common Structure"
  template and the `sed` bulk-update recipe in `linters/README.md` still match
  the real linter actions — the shared `check_enabled.sh` gate and the single
  `actions/checkout` version the 19 actions agree on. The version is read from
  the actions, never hardcoded, so a checkout bump keeps the doc honest
- `linters_readme_template_contract_selftest.py`: runs the contract above
  against synthetic repo fixtures, one per way the doc can go stale, so the
  guard cannot rot into a no-op that passes on everything
- `smoke_contract.py`: asserts the `linters-smoke` disabled-path job in
  `smoke.yml` covers every `linters/*/action.yml` and that each step of those
  actions is genuinely inert with `linters: ''` — either gated on
  `steps.check.outputs.continue == 'true'` or falsified by an input the job
  pins (`ssh-key: ''`, phpstan's `apt-packages`/`php-version`)
- `linter_gate_contract.py`: asserts every step of the 19 linter actions —
  other than the shared `check` step itself — carries
  `steps.check.outputs.continue == 'true'` in its `if:`, so nothing runs when
  the linter is disabled (self-checks its own detector against fixtures first)
- `token_contract.py`: asserts every token-accepting toolchain setup step
  (`actions/setup-go|java|node|python`) passes `token:` from one of the
  action's inputs, that every `pip`/`npm`/`gem`-style install step exports
  `GITHUB_TOKEN`, and that `linters/bandit` mirrors `linters/semgrep` step for
  step -- the two pip-installed Python linters must not drift apart again

### .github/workflows

**Purpose:** CI for this repository itself.

**Location:** `.github/workflows/`

**Key Components:**

- `build.yml`: generated by github-build with `--skip_license_check
  --skip_slack`, so it carries no SOUP-check and no Slack-notification job. It
  runs the detected linters, the Slack Jest suite (`js_unit_tests`) and the bats
  suites of the three `.bats`-marked directories — `bump-actions`, `codedeploy`
  and `variables` (`shell_script_unit_tests`). Edits belong in the generator,
  not this file
- `smoke.yml`: hand-maintained (explicitly not generated) smoke harness that
  runs the `tests/` contract checks, invokes every linter action on its
  disabled path to assert the `check_enabled.sh` gate, runs the
  `linters/tests/` bats suite for `linters/_lib/` (linters/ carries no `.bats`
  marker, so the generated build.yml does not pick it up), and runs the
  variables action asserting its outputs are populated
- `external-actions-bump.yml`: hand-maintained (explicitly not generated)
  weekly cron (Monday 06:00 UTC) driving `bump-actions.sh`, opening a single
  PR for human review
- `auto-approve.yml`: generated by github-build (`auto_merge_manager.rb`), so
  edits belong in the generator, not this file. On non-draft same-repo pull
  requests it resolves the repo-wide code owners from the catch-all (`*`) line
  of `CODEOWNERS` — matching the PR author against individual handles and
  `org/team` memberships — and approves only when the author is an owner and
  the approving account is not the author itself (self-approval guard)

## Software of Unknown Provenance

See [soup.md](soup.md) for the complete list of third-party dependencies. Third-party
GitHub Actions referenced by composite actions are declared in their respective
`action.yml` files.

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

**Location:** `codedeploy/deploy/deploy.sh` (`create_deployment` and
`poll_deployment` functions, driven by `main`)

**Algorithm:**

1. Create deployment via AWS CLI (`create_deployment`)
2. Poll deployment status every `POLL_INTERVAL` seconds (default 5),
   tolerating transient `get-deployment` API errors
3. Exit on terminal states: Succeeded (0), Failed/Stopped (1). `Ready` and
   other non-terminal states keep polling, since blue/green still has
   BlockTraffic/AllowTraffic/TerminateBlueInstances phases that can fail
4. Timeout after `monitor-timeout-minutes * 60 / POLL_INTERVAL` iterations
   (default 30 minutes), returning a failure rather than a false-green build

**Complexity:** O(1) bounded by the computed iteration limit

### Slack Message Construction

**Purpose:** Build Slack Block Kit message with job statuses.

**Location:** `slack/index.js`

**Algorithm:**

1. Parse jobs JSON input
2. Extract deployment flags from variables output
3. Iterate jobs to determine overall status and color
4. Construct Block Kit message with attachments

**Complexity:** O(j) where j is the number of jobs

### External Action Reference Bumping

**Purpose:** Resolve whether an external GitHub Action reference can be bumped to
a newer upstream version, preserving the existing pin style.

**Location:** `bump-actions/bump-actions.sh` (`resolve_bump`, with the
`is_sha`/`is_floating_major`/`is_exact_semver`/`version_gt` helpers)

**Algorithm:**

1. Skip 40-char SHA pins and non-version refs (e.g. `@main`)
2. Resolve the latest upstream tag via the published release, falling back to
   the highest semver tag
3. Floating major (`vN` / `N`): bump only when the latest major increases,
   keeping the floating form (e.g. `v6` -> `v7`), verifying the tag exists
4. Exact pin (`vX.Y` / `X.Y.Z`): bump to the latest release when strictly newer
   (`version_gt` compares with `sort -V`, ignoring a leading `v`)

**Complexity:** O(r) where r is the number of distinct external references
(one upstream lookup per reference)

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
- Slack `parseInputs` rejects an empty `webhook-url` and reports the offending
  payload on a JSON parse failure; `validateJobs` asserts the parsed `jobs`
  input is an object keyed by job name whose values are objects, so a shape
  change fails fast instead of silently producing a wrong message
- `variables.sh` sanitizes every slash out of the resolved ref before it is
  used in `BUILD_NAME`/`BUILD_VERSION`, which flow downstream into S3 keys and
  CodeDeploy identifiers

#### Repository Checkout Hardening

- `persist-credentials: false` on all checkout steps to prevent credential leakage
  (except setup action where credentials are required for Java GPG/Maven operations)

#### GPG Signature Verification

- phpcs: Downloads php-cs-fixer and verifies GPG signature before execution
- pmd: Downloads PMD release and verifies GPG signature before execution
- Public keys are fetched via the shared `linters/_lib/recv_gpg_key.sh` helper,
  which retries across multiple keyservers to avoid flaky imports

#### Code Analysis

- Semgrep security scanning with `--error` flag
- Bandit Python security linting
- ESLint for JavaScript patterns
- Multiple language-specific linters for code quality

#### Regression Controls

- `tests/action_contracts.py` blocks a malformed `action.yml` from reaching a
  consumer's pipeline
- `tests/lock_file_contract.py` blocks the Trivy lock-file list from drifting
  between its two consumers
- `tests/fail_fast_contract.py` blocks a nested `bash -c` from silently
  swallowing the exit status of every command but the last
- `tests/linters_readme_template_contract.py` blocks the prescriptive
  `linters/README.md` template from drifting behind the actions it tells
  contributors to copy — the failure mode behind CONS-001, where the stale
  block still advertised the un-anchored `grep` gate that `check_enabled.sh`
  replaced
- `tests/smoke_contract.py` blocks the `linters-smoke` disabled path from
  silently ceasing to be a no-op when a linter action's step gating changes
- `tests/linter_gate_contract.py` blocks a linter step from running (and, for
  phpstan's ssh-agent, loading a deploy key) while that linter is disabled
- `tests/token_contract.py` blocks an unauthenticated toolchain download or
  package install from creeping back into any action
- The Slack `pretest` script rebuilds `dist/index.js` and fails on any diff, so
  the published bundle always matches the reviewed source
- Bats suites cover the shell entry points (`variables.sh`, `deploy.sh`,
  `bump-actions.sh`) that cannot be exercised through a normal build

### Error Handling

| Component | Error Handling |
| :--- | :--- |
| CodeDeploy | Status polling with timeout, explicit failure states |
| Slack | `run().catch(reportError)`; `reportError` logs the stack and the webhook response body before `core.setFailed`. Webhook POST bounded by a 30s axios timeout |
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
| Slack webhook unavailable | No notification; the notify step itself fails | Runs last in the workflow, so no build step is blocked; stack and response body logged by `reportError` |
| Linter timeout | Job fails | 30-minute timeout per job |
| CodeDeploy stuck | Monitoring fails the step | Configurable polling timeout (`monitor-timeout-minutes`, default 30) |
| Docker build failure | No image published | Build logs available |
| Private repo access denied | Checkout fails | SSH key validation |

### Permissions

The build workflow uses minimal permissions:

```yaml
permissions:
  contents: read
  pull-requests: read
```
