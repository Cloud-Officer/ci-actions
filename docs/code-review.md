# Code Review Report

**Repository:** Cloud-Officer/ci-actions
**Date:** 2026-05-07
**Reviewer:** AI Code Review (Deep, Multi-Agent)
**Health Score:** B+

A reusable GitHub Actions library (28 composite actions, ~4,095 LOC across YAML/Bash/JavaScript) with strong security-hardening discipline, comprehensive self-linting in CI, and well-maintained documentation. The most material gaps are in test coverage architecture (production code is silently re-implemented in tests) and in workflow ergonomics (no caching, no concurrency cancellation). No critical security findings; no exploitable vulnerabilities found.

---

## Review Coverage

- ✅ Tech stack and structure (28 composite actions, 1 Node.js action, 1 Bash module)
- ✅ Security audit (secrets, injection, auth, TLS, GitHub Actions hardening)
- ✅ Dependency analysis (npm + external actions + tool versions)
- ✅ Code quality (action.yml composition, bash hygiene, JS quality)
- ✅ Testing (unit coverage, behavioral gaps, coupling)
- ✅ Concurrency (slack/index.js)
- ✅ Git/repository hygiene (branch protection, CODEOWNERS, history)
- ✅ Configuration management (linter configs, version pinning, consistency)
- ✅ Bug patterns and error handling (bash defensiveness, GHA semantics)
- ✅ Backwards compatibility (cross-checked vs github-build consumer)
- ✅ Documentation (README, architecture, per-action READMEs)
- ✅ CI/CD (build.yml, auto-merge.yml, dependency monitoring)
- ✅ In-code comment quality
- ⚠️ IaC review skipped (this repo provides IaC tooling but has no IaC of its own)
- ⚠️ Performance/Observability/API/AI/ML/Compliance/i18n N/A (not a backend or user-facing app)

---

## Summary

| Severity | Count |
| -------- | ----- |
| 🔴 Critical | 0 |
| 🟠 High | 3 |
| 🟡 Medium | 12 |
| 🔵 Low | 14 |
| ⚪ Info | 1 |

**Total confirmed findings (above confidence threshold): 30**
**Filtered (below 80 confidence, see appendix): 12**
**Rejected by adversarial validation: 28**

---

## Detailed Findings

### TEST-002 🟠 HIGH: Bats tests redefine production functions instead of sourcing variables.sh

**Category:** Testing > Coverage Architecture
**File:** variables/tests/variables.bats:14-67
**Effort:** M (1 day)

**Issue:**
The bats setup() calls `extract_functions()` which manually re-defines `has_trigger`, `on_beta`, `on_rc`, `on_prod`, `on_macos`, `on_tvos`, `set_flag_from_trigger`, `add_linter_if_file`, `add_linter_if_dir` inline. The production file `variables.sh` is never `source`d. Comment line 23 even acknowledges this: `# Define the functions manually to avoid side effects`.

**Impact:**
Tests pass even if `variables.sh` is broken, deleted, or has its function bodies altered. Tests exercise the test-file's own copy of the logic, not the production code under audit. Any refactor of `variables.sh` can leave tests green while breaking real CI runs in consumer repos.

**Recommended Fix:**
Replace the inline redefinition with a sourced + isolated approach: in setup(), `source variables.sh` (after stubbing GitHub env vars). If specific functions need isolation, refactor `variables.sh` to be safely sourceable (e.g., guard the main body with `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` so it only runs as a script). This restores the test-to-prod link.

---

### TEST-006 🟠 HIGH: No dist/index.js drift verification for slack action

**Category:** Testing > Build Artifact
**File:** slack/action.yml:18, .github/workflows/build.yml
**Effort:** S (<2hr)

**Issue:**
`slack/action.yml` runs `dist/index.js` (the ncc-bundled artifact). CI runs `npm ci` and `npm test` (Jest), but never runs `npm run build` followed by a `git diff --exit-code dist/` check. Jest tests target `index.js` (source), not the shipped bundle.

**Impact:**
A developer can edit `slack/index.js`, get green tests, and merge without regenerating `dist/index.js`. Consumers pulling `@v2` then run the **stale** bundle while CI signals "all good." Classic ncc-bundled-action drift.

**Recommended Fix:**
Add a CI step in `js_unit_tests`:

```yaml
- name: Verify dist is in sync
  run: |
    cd slack
    npm run build
    git diff --exit-code dist/ || (echo "dist/ is out of date; run 'npm run build' and commit"; exit 1)
```

---

### TEST-008 🟠 HIGH: variables.sh main script body has zero behavioral coverage

**Category:** Testing > Behavioral Coverage
**File:** variables/variables.sh:56-87
**Effort:** M (1 day)

**Issue:**
Lines 56-87 (TIMESTAMP capture, SHORT_COMMIT, SAFE_BRANCH derivation, `MODIFIED_GITHUB_RUN_NUMBER + 15000`, the if/elif/else for tag/PR/branch detection, three different `COMMIT_MESSAGE` retrieval paths via `git tag -l`, `git log` on SHORT_COMMIT, and `git log` on GITHUB_SHA) are never executed by any test. The closest test (variables.bats:652 "variables are written to GITHUB_ENV and GITHUB_OUTPUT") sidesteps the logic entirely by hardcoding `BUILD_NAME="test-build"` etc.

**Impact:**
Bugs in tag stripping, SAFE_BRANCH slash-replacement, the +15000 arithmetic, or any of the three COMMIT_MESSAGE retrieval branches would ship undetected. This is the highest-risk untested logic in the repo (the variables action is consumed by every workflow built from github-build).

**Recommended Fix:**
Add bats integration tests that source `variables.sh` (per TEST-002) under controlled GitHub env (e.g., set `GITHUB_REF=refs/tags/v1.2.3`, run, assert outputs in a temp `GITHUB_ENV`). At minimum cover: tag event, PR event (`GITHUB_HEAD_REF` set), branch push event.

---

### TEST-001 🟡 MEDIUM: 7.4% unit-test coverage across composite actions

**Category:** Testing > Coverage
**File:** repo-wide (27 actions, 2 with tests)
**Effort:** L (2-3 days)

**Issue:**
Of 27 composite actions, only `slack/` (Jest) and `variables/` (bats) have unit tests. Coverage = 2/27 = 7.4%. CI smoke-exercises 7 more linters (actionlint, eslint, markdownlint, semgrep, shellcheck, trivy, yamllint) plus setup/variables, leaving 18 actions with no tests at all.

**Impact:**
Most actions are thin wrappers around third-party tools, so unit-test ROI is moderate. But high-blast-radius actions (`aws/`, `codedeploy/deploy/`, `codedeploy/s3copy/`, `docker/`, `soup/`) touch production infrastructure and have neither unit nor smoke coverage.

**Recommended Fix:**
Prioritise smoke tests in `build.yml` for the 5 high-risk actions (mock AWS via localstack, dummy Dockerfile, etc.). Lower priority: per-linter smoke tests by running the linter against a known-bad fixture in CI.

---

### TEST-012 🟡 MEDIUM: 18 actions have neither unit nor CI smoke coverage

**Category:** Testing > CI Smoke Tests
**File:** .github/workflows/build.yml
**Effort:** L (2-3 days)

**Issue:**
Actions exercised by `build.yml`: variables, setup, actionlint, eslint, markdownlint, semgrep, shellcheck, trivy, yamllint. Actions never exercised: `aws`, `codedeploy/{checkout,deploy,s3copy}`, `docker`, `soup`, plus 12 linters (`bandit`, `cfnlint`, `flake8`, `golangci`, `hadolint`, `ktlint`, `phpcs`, `phpstan`, `pmd`, `protolint`, `rubocop`, `swiftlint`).

**Impact:**
Breaking changes to these 18 actions are only discovered when a consumer's pipeline fails in production.

**Recommended Fix:**
Add a `smoke` job that does `cloud-officer/ci-actions/<action>@${{ github.sha }}` against trivial fixtures. For `codedeploy/deploy` and `aws`, run with `dry-run` or against a localstack endpoint.

---

### TEST-009 🟡 MEDIUM: TRIVY and CFNLINT auto-detection blocks are untested

**Category:** Testing > Behavioral Coverage
**File:** variables/variables.sh:150, 167-179
**Effort:** S (<2hr)

**Issue:**
The `find -maxdepth 3` block at lines 167-179 scans for 18 different filenames (Dockerfile, *.tf, package-lock.json, etc.) to add `TRIVY` to `LINTERS`. The `add_linter_if_file CFNLINT .cfnlintrc` call at line 150 is also untested. Neither `TRIVY` nor `CFNLINT` appears in any bats assertion.

**Impact:**
Adding/removing a trigger filename, breaking the find expression's escaping, or changing `-maxdepth` would not be caught by tests.

**Recommended Fix:**
Add bats cases that create each trigger file in the test temp dir and assert TRIVY/CFNLINT appear in `LINTERS`. Also add a negative case (no trigger files → not added).

---

### TEST-015 🟡 MEDIUM: Slack tests coupled to internal block-kit structure

**Category:** Testing > Coupling
**File:** slack/index.test.js:197-205, 354-358, 376-381, 425-429
**Effort:** S (<2hr)

**Issue:**
Tests reach into block-kit internals (`callArg.attachments[0].blocks.filter(b => b.type === 'context')`, `.flatMap(b => b.fields || [])`, `jobAttachments[0].blocks[0].fields.length`). Type-filter assertions are reasonably resilient, but `attachments.slice(1)[0].blocks[0]` index-access tightly couples to the current 4-block layout.

**Impact:**
Refactors that preserve user-visible Slack output (e.g., switching from section+context to header_block_kit) break the test suite even when behavior is unchanged. Discourages legitimate refactoring.

**Recommended Fix:**
Replace index-based assertions with type-/property-based ones. For the "color resets between job pairs" test (line 431-456), assert against the rendered `attachments[].color` array rather than block traversal.

---

### GIT-001 🟡 MEDIUM: Branch protection has require_code_owner_reviews disabled

**Category:** Git Hygiene > Branch Protection
**File:** repo settings (gh api branches/master/protection)
**Effort:** XS (<30min)

**Issue:**
`required_pull_request_reviews.require_code_owner_reviews` is `false`. The `.github/CODEOWNERS` file exists but is not enforced by branch protection — only the auto-merge workflow consults it (and that workflow only auto-approves PRs from owners, it doesn't require owners to approve non-owner PRs).

**Impact:**
A non-owner PR can be merged with one approval from any human, regardless of who owns the touched paths. The CODEOWNERS file is currently advisory-only.

**Recommended Fix:**
Toggle `require_code_owner_reviews: true` via Settings → Branches → master, or via `gh api -X PUT /repos/{owner}/{repo}/branches/master/protection`.

---

### GIT-007 🟡 MEDIUM: CODEOWNERS bus-factor of 1

**Category:** Git Hygiene > Ownership
**File:** .github/CODEOWNERS
**Effort:** XS (<30min)

**Issue:**
Every line in `.github/CODEOWNERS` lists only `@ydesgagn`. No team handle, no second individual.

**Impact:**
If `@ydesgagn` is unavailable (vacation, departure, account compromise), no owner-review workflow can complete. Branch protection currently doesn't enforce CODEOWNERS (see GIT-001), so the operational impact is partly absorbed by the bypass list (`tlacroix`, `ydesgagn`), but the file itself is fragile.

**Recommended Fix:**
Add a second owner or a team handle (`@Cloud-Officer/devops` or similar) so ownership survives offboarding.

---

### GIT-008 🟡 MEDIUM: CODEOWNERS uses individual handles instead of team

**Category:** Git Hygiene > Ownership
**File:** .github/CODEOWNERS
**Effort:** XS (<30min)

**Issue:**
No `@org/team-slug` patterns in CODEOWNERS — only bare individuals. The `auto-merge.yml` workflow is engineered to support team membership lookups (`gh api orgs/{org}/teams/{slug}/memberships`), so the tooling is already team-aware.

**Impact:**
Onboarding/offboarding requires direct CODEOWNERS edits instead of org-team membership changes.

**Recommended Fix:**
Replace `@ydesgagn` entries with a team handle. The auto-merge workflow already handles the team-slug case.

---

### BUG-009 🟡 MEDIUM: codedeploy/deploy reports success on timeout AND mislabels the duration

**Category:** Bug Patterns > Error Propagation
**File:** codedeploy/deploy/action.yml:60, 90-95
**Effort:** S (<2hr)

**Issue:**
The polling loop is `while [ ${counter} -lt 120 ]; do ... sleep 5 ...`, giving ~119 × 5 = 595 seconds (~10 minutes), but the timeout echo says `"Aborting deployment monitoring as > 5 mins!"`. Additionally, the script falls off the end without `exit 1`, so the workflow reports success while the deployment continues in AWS.

The success-on-timeout is intentional (commented at lines 92-94: "Intentionally not exiting with error code here ... avoid burning GitHub Actions minutes"). The `> 5 mins` message, however, is factually wrong.

**Impact:**
Consumers reading the log think they got a 5-minute timeout when they actually waited 10. Worse, downstream steps assume deployment succeeded when it may still be in progress.

**Recommended Fix:**
Update the message to `> 10 mins` (or change `120` to `60` if 5 mins was the intent). Optionally promote the timeout to `exit 2` with an explicit "deployment in progress, check console" message that consumers can choose to treat as warning.

---

### COMPAT-009 🟡 MEDIUM: Mutable v2 tag silently propagates breaking changes to consumers

**Category:** Backwards Compat > Versioning
**File:** repo tags (v2 currently at 88480fb, master at f3ea0a9)
**Effort:** M (1 day)

**Issue:**
`v2` is moved with each release. Recent commits shipped breaking-style changes under `v2` without major version bump: rubocop default ruby 3.4 → 4.0 (PR #177), slack runtime node20 → node24, removed checkov action, `python-architecture` default removal. There is no CHANGELOG, no GitHub Releases (`gh api releases` returns `[]`), and no MIGRATION.md. Consumers (github-build, 13+ pin sites) reference `@v2`.

**Impact:**
A consumer pinned to `@v2` got Ruby 4.0 as their default ruby-version overnight. The "v2" major-version contract is being violated by behaviour-changing patch tags.

**Recommended Fix:**
Either (a) bump to `v3` for behaviour-changing defaults, or (b) publish GitHub Releases with release notes that consumers can subscribe to. Document a versioning policy in README ("v2 is rolling; pin to `2.0.x` for stability"). The 13 immutable point tags (2.0.0..2.0.12) already exist — promote them.

---

### CFG-008 🟡 MEDIUM: Default php-version pinned to 8.2 in phpstan and phpcs

**Category:** Configuration > Tool Versions
**File:** linters/phpstan/action.yml:23, linters/phpcs/action.yml:19
**Effort:** XS (<30min)

**Issue:**
Both linters default `php-version` to `'8.2'`. PHP 8.4 is current stable (Nov 2024+); 8.2 is still security-supported but lags two minor releases. No "intentionally using latest" comment on this field.

**Impact:**
Consumers who don't override get analyzed against an outdated PHP grammar; new language features won't lint correctly.

**Recommended Fix:**
Bump default to `'8.3'` or `'8.4'`, or document a chosen pinning policy. Either way, treat as a controlled change with a corresponding tag bump (see COMPAT-009).

---

### CFG-014 🟡 MEDIUM: Workflow uses Node 25 (non-LTS) by default

**Category:** Configuration > Runtime
**File:** .github/workflows/build.yml:22
**Effort:** XS (<30min)

**Issue:**
`env.NODE-VERSION: 25.9.0`. Node 25 is an odd-numbered (non-LTS) release; current LTS lines are 22.x and 24.x. Also, the env var name `NODE-VERSION` uses a hyphen instead of the conventional underscore.

**Impact:**
Non-LTS Node receives only ~6 months of support. The Jest test job depends on it. Maintenance burden compounds.

**Recommended Fix:**
Switch to `NODE_VERSION: 24.x` (current LTS as of cutoff). Rename env var to underscore form for consistency with surrounding GitHub conventions.

---

### CI-005 🟡 MEDIUM: No npm cache for slack Jest job

**Category:** CI/CD > Optimization
**File:** .github/workflows/build.yml (js_unit_tests job)
**Effort:** XS (<30min)

**Issue:**
The `setup` action invocation does not pass `node-cache: 'npm'`, and the `setup/action.yml` does not include any compensating `actions/cache` step for `~/.npm` or `node_modules`. Every CI run does a clean `npm ci` download for slack.

**Impact:**
30-60 seconds wasted per run, plus npm registry rate-limit pressure.

**Recommended Fix:**
Pass `node-cache: 'npm'` to `setup@v2` in the `js_unit_tests` job. The setup action already plumbs that input through to `actions/setup-node@v6`'s `cache:` parameter (line 638).

---

### CI-006 🟡 MEDIUM: No concurrency cancellation in build.yml

**Category:** CI/CD > Optimization
**File:** .github/workflows/build.yml
**Effort:** XS (<30min)

**Issue:**
No `concurrency:` block at workflow or job level. Rapid PR pushes (synchronize events) run all jobs to completion instead of cancelling superseded runs.

**Impact:**
Wasted runner-minutes (free for public repos but noisy for the user) and slower feedback as obsolete runs block the queue.

**Recommended Fix:**
Add to `build.yml`:

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
```

---

### DOC-002 🟡 MEDIUM: aws/README.md has misleading title and broken YAML example

**Category:** Documentation > Accuracy
**File:** aws/README.md:1, 46-49
**Effort:** XS (<30min)

**Issue:**

- Line 1 reads `# GitHub Action: Deploy` but line 3 describes "executes AWS CLI or shell commands" — title doesn't match purpose.
- The `variables` job in the example (lines 46-49) is indented at 2 spaces while the parallel `aws` job uses 4 spaces, making the YAML structurally invalid.

**Impact:**
Consumers copying the example get a YAML parse error. The misleading title may confuse users into thinking this is a deployment action when it's a generic shell-command runner.

**Recommended Fix:**
Rename to `# GitHub Action: AWS`. Re-indent lines 46-49 to match the rest of the file. Validate the example via `yq` / `actionlint` in CI.

---

### QUAL-014 🔵 LOW: Doubled-quote typo in soup/action.yml URL construction

**Category:** Code Quality > Bash Hygiene
**File:** soup/action.yml:44
**Effort:** XS (<30min)

**Issue:**
Line 44 reads `asset_url=""https://github.com/Cloud-Officer/soup/archive/refs/tags/${latest_tag}.zip""` with **doubled** double quotes. Bash collapses adjacent quoted strings so the URL is functionally correct, but a single accidental space inside the doubled quotes would silently corrupt the URL.

**Recommended Fix:**
Replace with a single pair: `asset_url="https://github.com/Cloud-Officer/soup/archive/refs/tags/${latest_tag}.zip"`.

---

### QUAL-008 🔵 LOW: Inconsistent first-step naming across linter actions

**Category:** Code Quality > Consistency
**File:** linters/{eslint,bandit,semgrep,actionlint}/action.yml:20
**Effort:** XS (<30min)

**Issue:**
4 of 19 linters (eslint, bandit, semgrep, actionlint) start with bare `- id: check`. The other 15 use `- name: Check if X is enabled`. The README example also uses the bare form, so the style is documented but mixed.

**Recommended Fix:**
Pick one style and apply consistently. Adding the human-readable `name:` is the more ergonomic choice for log readers.

---

### QUAL-018 🔵 LOW: slack/index.js uses console.log instead of @actions/core

**Category:** Code Quality > Logging
**File:** slack/index.js:149, 151
**Effort:** XS (<30min)

**Issue:**
`console.log(JSON.stringify(data, undefined, 2))` and `console.log(JSON.stringify(response.data, undefined, 2))` unconditionally dump the full Slack payload + response on every run. `@actions/core` is already imported (line 1) and used elsewhere (`core.setFailed`).

**Impact:**
No security risk (data contains only non-secret GitHub context), but logs are noisy.

**Recommended Fix:**

```js
core.debug(JSON.stringify(data, undefined, 2));
const response = await axios.post(webhookUrl, data, { timeout: 30000 });
core.debug(JSON.stringify(response.data, undefined, 2));
```

The dumps then only appear when the consumer enables Actions Step Debug (`ACTIONS_STEP_DEBUG=true`).

---

### COMPAT-007 🔵 LOW: Rubocop default ruby-version bumped 3.4 → 4.0 under v2

**Category:** Backwards Compat > Defaults
**File:** linters/rubocop/action.yml:19 (commit c271d3f, PR #81)
**Effort:** XS (<30min)

**Issue:**
The default jumped a major Ruby version under the same `v2` floating tag. Consumers pinned to `@v2` who do not pass `ruby-version` get Ruby 4.0 silently.

**Impact:**
Ruby 4.0 introduces real grammar/library changes that can break Gemfiles silently.

**Recommended Fix:**
Document this default change in README / per-action README. Long-term: address via COMPAT-009 (versioning policy).

---

### DOC-001 🔵 LOW: BUG_REPORT.MD uses uppercase extension

**Category:** Documentation > Conventions
**File:** .github/ISSUE_TEMPLATE/BUG_REPORT.MD
**Effort:** XS (<30min)

**Issue:**
Sibling file uses `.md` (lowercase). Cosmetic inconsistency.

**Recommended Fix:**
`git mv .github/ISSUE_TEMPLATE/BUG_REPORT.MD .github/ISSUE_TEMPLATE/BUG_REPORT.md`.

---

### DOC-003 🔵 LOW: Inconsistent `@v2` vs `@master` examples across READMEs

**Category:** Documentation > Versioning Guidance
**File:** README.md:30 vs slack/README.md, soup/README.md, aws/README.md
**Effort:** XS (<30min)

**Issue:**
Top-level README installs `@v2`. Per-action READMEs reference `@master`. Casing also differs (`Cloud-Officer` vs `cloud-officer`).

**Recommended Fix:**
Standardise on `@v2` everywhere (the documented stable contract). Use `Cloud-Officer` casing consistently.

---

### DOC-005 🔵 LOW: codedeploy timeout message says "5 mins" but waits ~10

**Category:** Documentation > Comment Accuracy
**File:** codedeploy/deploy/action.yml:95
**Effort:** XS (<30min)

**Issue:**
See BUG-009 — the misleading log text is the documentation half of that finding.

**Recommended Fix:**
Echo `"Aborting deployment monitoring as > 10 mins!"` to match the actual loop bound.

---

### DOC-006 🔵 LOW: flake8 step labeled "Install flake8-docstrings" only installs flake8

**Category:** Documentation > Stale References
**File:** linters/flake8/action.yml:46-54
**Effort:** XS (<30min)

**Issue:**
Step name and `# flake8-docstrings` comment claim the plugin is being installed, but the run block only `pip install --upgrade flake8`. flake8-docstrings is not installed transitively.

**Recommended Fix:**
Either (a) actually install `flake8-docstrings` if it's needed, or (b) rename the step to "Install flake8" and remove the stale comment.

---

### DOC-008 🔵 LOW: Bats test title contradicts its assertion

**Category:** Documentation > Test Naming
**File:** variables/tests/variables.bats:290
**Effort:** XS (<30min)

**Issue:**
Test name: `"similar but different trigger does not match"`. Assertion: `[ "$status" -eq 0 ]` (status 0 = match). Comment "should still match because grep -F matches substring" acknowledges the conflict. The test enshrines the substring-collision behavior of `grep -iF` rather than naming it as a known limitation.

**Recommended Fix:**
Rename the test to `"trigger substring still matches (documented grep -iF behavior)"` and add a top-of-file note on the limitation, OR fix `has_trigger` to use word-boundary matching (e.g., `grep -wF`) and align the test.

---

### DEP-001 🔵 LOW: @actions/core is one major version behind

**Category:** Dependencies > Version Lag
**File:** slack/package.json:13
**Effort:** XS (<30min)

**Issue:**
Declared `^2.0.3`; latest published is `3.0.1`. Caret range will not auto-upgrade across the major boundary.

**Recommended Fix:**
Bump to `^3.0.1`, run `npm install`, regenerate `dist/` (see TEST-006), test, commit.

---

### DEP-002 🔵 LOW: aquasecurity/trivy-action one minor behind

**Category:** Dependencies > Version Lag
**File:** linters/trivy/action.yml:91
**Effort:** XS (<30min)

**Issue:**
Pinned to `0.35.0`; latest is `0.36.0` (April 2026, brings Trivy v0.70.0). Mitigated by `skip-setup-trivy: true` and direct apt install.

**Recommended Fix:**
Bump to `0.36.0` when convenient; low urgency.

---

### DEP-003 🔵 LOW: webfactory/ssh-agent one minor behind

**Category:** Dependencies > Version Lag
**File:** setup/action.yml:513, linters/phpstan/action.yml:61
**Effort:** XS (<30min)

**Issue:**
Pinned to `v0.9.1`; latest is `v0.10.0` (March 2026, upgrades Node runtime to 24).

**Recommended Fix:**
Bump in both files when convenient.

---

### SEC-012 🔵 LOW: APT_PACKAGES expanded unquoted in setup and phpstan

**Category:** Security > Argument Injection
**File:** setup/action.yml:554, linters/phpstan/action.yml:75
**Effort:** S (<2hr)

**Issue:**
`sudo apt-get --yes --no-install-recommends install ${APT_PACKAGES}` is intentionally unquoted to permit multiple package names. Bash variable expansion does NOT re-tokenize `;` as a command separator (so the literal `pkg; rm -rf /` PoC does not RCE), but it DOES word-split, so an attacker controlling the input can pass arbitrary apt arguments (e.g., `-o APT::Update::Pre-Invoke::="..."`) which is privileged-argument injection.

**Impact:**
Low risk because the input comes from workflow authors (trusted), not external users. But the surface is larger than typical and worth hardening.

**Recommended Fix:**
Validate against a regex (`^[a-z0-9+._-]+( [a-z0-9+._-]+)*$`) or use `xargs -d ' ' apt-get install --` so apt sees positional args and shell metacharacters cannot become flags.

---

### TEST-002 (related) ⚪ INFO: Subtle substring-match in `has_trigger`

**Category:** Bug Patterns > Latent
**File:** variables/variables.sh:7
**Effort:** S (<2hr)

**Issue:**
`has_trigger()` uses `grep -iF "#$1"` (case-insensitive fixed-string substring). `#beta-deploy-test` matches trigger `#beta-deploy`. The bats test at line 290 documents this as expected. No collisions today (all triggers have distinct prefixes), but a future trigger like `#deploy` would match every other `#deploy-*` trigger.

**Recommended Fix:**
Switch to `grep -iwF "#$1"` (word boundaries) or token-by-token comparison. Update the test to assert non-match instead of locking in the bug.

---

## ✅ Positive Observations & Strengths

This repo is in genuinely good shape. The team has invested in security hygiene, documentation, and self-dogfooding to a degree well above average for a CI-actions library.

### Architecture & Design

- **Consistent composition pattern across 19 linter actions:** identical input shape (`linters`, `ssh-key`, `github-token`), identical `check` step gate, identical checkout flow. Makes the actions trivially generic for the github-build consumer.
- **Smart Trivy auto-detection:** scans 18 file types under `-maxdepth 3` and adds `TRIVY` to the linter set automatically (`variables/variables.sh:167-179`). Defensive `-prune` for submodule paths.
- **Variables-driven flag system:** all CI control flags (`#beta-deploy`, `#skip-tests`, `#deploy-options=...`, etc.) centralised in `variables.sh` with consistent `set_flag_from_trigger` helper. Easy to extend.
- **Slack action is decomposed into single-responsibility functions** (`parseInputs`, `buildVariableFields`, `buildHeaderAttachment`, `buildJobAttachments`, `sendWebhook`, `run`) — none over 60 lines.

### Code Quality

- **All 28 actions explicitly declare `shell: bash` on every run step** (52/52 — no implicit-shell drift).
- **All inputs and outputs have `description:` fields.**
- **Naming is overwhelmingly consistent** (kebab-case for inputs across all actions).
- **Zero linter-disable comments anywhere** (no eslint-disable, shellcheck disable, swiftlint:disable, etc.).
- **Variables.sh refactor introduces clean higher-order helpers** (`has_trigger`, `set_flag_from_trigger`, `add_linter_if_file/dir`) — small, well-named, no function exceeds ~20 lines.

### Security Practices

- **Inputs uniformly passed via `env:` mapping**, never directly interpolated into `run:` scripts. This is GitHub's recommended hardening against script injection from untrusted contexts (`${{ github.event.* }}`) and is applied across all 28 composite actions.
- **`persist-credentials: false` on every `actions/checkout@v6`** in linter actions — prevents the workflow `GITHUB_TOKEN` from leaking into `.git/config`.
- **No hardcoded secrets, AWS keys, GitHub tokens, Slack tokens, or Firebase keys found** anywhere in source or config.
- **No deprecated `::set-output::` commands** — all outputs use the modern `${GITHUB_OUTPUT}` file pattern.
- **GPG signature verification on PMD and php-cs-fixer downloads** (linters/pmd/action.yml:67-68, linters/phpcs/action.yml:83) — strong supply-chain hygiene.
- **Trivy installed from signed apt repo with GPG verification** (linters/trivy/action.yml:84-87).
- **Auto-merge workflow uses `pull_request_target` correctly:** checks out `github.event.pull_request.base.sha` (not the PR head), so secrets never meet untrusted code. PR author handle is passed via `env:` (not interpolation).
- **`build.yml` triggers on `pull_request` (not `pull_request_target`)** — fork PRs correctly do not get secrets.
- **AWS credentials are configured via `aws-actions/configure-aws-credentials@v5`**, never written to disk or echoed.
- **Required signed commits enforced on master.**
- **GitHub Advanced Security suite fully enabled:** secret scanning, push protection, AI detection, Dependabot security updates, validity checks.

### Testing

- **axios.post is mocked** in slack tests — deterministic and fast.
- **Test environments are isolated:** Jest mocks GitHub env vars in `beforeEach`/`afterEach`; bats `setup()` uses `mktemp -d` per test.
- **Both test suites are wired into CI** (`build.yml` jobs `js_unit_tests`, `shell_script_unit_tests`) and gated by the `SKIP_TESTS` flag.
- **No use of `Date.now()`, `Math.random()`, or `setTimeout`** in tests — no time/randomness flakiness.
- **`/* istanbul ignore next */` correctly excludes the CLI entry point** from coverage.
- **Bats covers all 17 linter detection branches** plus a "no linters" negative case and a "partial linters" mixed case.

### DevOps & CI/CD

- **Workflow-level permissions are read-only** (`contents: read, pull-requests: read`) — least-privilege baseline.
- **Semgrep job declares its own narrower permissions** (`actions: read, contents: read`) — exemplary least-privilege override.
- **All jobs set `timeout-minutes: 30`** — avoids runaway billing/locked runners.
- **Strong linter coverage in self-CI:** actionlint, yamllint, shellcheck, eslint, markdownlint, semgrep (SAST), trivy (IaC + secrets + vuln) — covers 7 distinct concern areas.
- **Cross-platform testing on a public repo** (where GitHub-hosted runners are free) is a strength, not a cost concern.
- **Branch protection on master is comprehensive:** 1 required review, dismiss stale reviews, require last-push approval, force-push blocked, deletion blocked, signed commits required, 10 required status checks, conversation resolution required.
- **`delete_branch_on_merge: true`** keeps the branch list tidy.
- **Squash merges only** — clean linear history.
- **Repo-level Dependabot security updates are enabled** — CVE coverage without a config file.

### Documentation

- **README is well-structured:** badge, ToC, intro, install, per-action links, CI control flag reference table, debugging tips, contributing section.
- **`docs/architecture.md` is comprehensive:** ToC, ASCII diagram, component interactions, software unit listing for every action with purpose/location/inputs, three critical algorithms with complexity analysis, detailed risk controls (security, error handling, logging, failure modes, permissions).
- **All 28 actions have a per-action README** documenting inputs, outputs, and a usage example.
- **`.soup.json` contains real per-package metadata** (license, version, risk_level, last_verified_at, requirements, verification_reasoning) for all 29 npm dependencies — not a stub.
- **In-code comments explain the WHY** in several places: codedeploy timeout intentional-success comment, trivy install workaround for the 2026-03-01 aquasecurity repo wipe, eslint v8 pin for jQuery compatibility, "Capture timestamp once to avoid race" in variables.sh.
- **Pinned versions are annotated** with "Intentionally using latest" or specific rationale comments.

### Dependencies & Maintenance

- **axios pinned at 1.16.0 (latest)** — patched against all 2026 axios CVEs (prototype pollution gadgets, header injection, NO_PROXY bypass, CRLF, SSRF, DoS).
- **`.soup.json` covers 100% of the npm dependency tree** with license, risk, and verification metadata.
- **Active dependency-update cadence visible in git log** — automated `update-YYYYMMDD-HHMMSS` branches keep everything current.
- **`.ruby-version` (4.0.3) matches current Ruby stable.**
- **Trivy install workaround documented in code** for the upstream aquasecurity repo wipe — shows active maintenance.

### Configuration Management

- **`.semgrep.yml` + `.semgrepignore`** scope checks tightly (excludes test/vendor/fixtures/mocks).
- **`.markdownlint-cli2.yaml`** disables only overly-strict rules (first-line-heading, line-length, single-h1) while keeping the default ruleset.
- **`.eslintrc.json`** uses `eslint:recommended` with sane overrides and clear inline comments.
- **`.shellcheckrc` empty** (zero-config = use shellcheck defaults) — acceptable.
- **Linter enable/disable via the `LINTERS` string is centralised in variables.sh** with bats coverage for all 17 detection branches.

### Error Handling & Resilience

- **Slack action has explicit 30s axios timeout** + top-level `.catch` that surfaces errors via `core.setFailed`.
- **No `process.exit` calls** in slack/index.js — avoids the classic "exit before flush" pitfall.
- **No `continue-on-error: true` anywhere** in the repo — failures propagate.

---

## Appendices

### Dependency Status (slack/package.json)

| Package | Current | Latest | Severity |
| ------- | ------- | ------ | -------- |
| @actions/core | 2.0.3 | 3.0.1 | LOW (1 major behind) |
| axios | 1.16.0 | 1.16.0 | OK |
| @vercel/ncc (dev) | 0.38.4 | 0.38.4 | OK |
| jest (dev) | 30.2.0 (resolved 30.3.0) | 30.3.0 | OK |

### Notable External Action Versions

| Action | Current | Latest | Notes |
| ------ | ------- | ------ | ----- |
| aquasecurity/trivy-action | 0.35.0 | 0.36.0 | DEP-002 |
| webfactory/ssh-agent | v0.9.1 | v0.10.0 | DEP-003 |
| All other actions (`@v3`/`@v5`/`@v6` floating tags) | current | current | Per repo policy — acceptable |

### Files Reviewed

- All 28 `action.yml` files
- `slack/index.js`, `slack/index.test.js`, `slack/package.json`, `slack/action.yml`
- `variables/variables.sh`, `variables/tests/variables.bats`, `variables/action.yml`
- `.github/workflows/build.yml`, `.github/workflows/auto-merge.yml`
- `.github/CODEOWNERS`, `.github/PULL_REQUEST_TEMPLATE.md`, `.github/ISSUE_TEMPLATE/*`
- `README.md`, `docs/architecture.md`, `docs/soup.md`, `.soup.json`
- All linter configs: `.eslintrc.json`, `.yamllint.yml`, `.markdownlint-cli2.yaml`, `.shellcheckrc`, `.semgrep.yml`, `.semgrepignore`, `.trivyignore`
- `.gitignore`, `.ruby-version`
- Cross-referenced against sibling repo `github-build` for consumer impact

### Filtered (Low Confidence)

The following findings survived adversarial validation but scored below the 80-confidence threshold (with no Critical-severity exception). Listed here for human spot-checking; not included in main findings or action items.

| Severity | Conf | File:Line | Description |
| -------- | ---- | --------- | ----------- |
| MEDIUM | 75 | linters/phpstan/action.yml:109 | SEC-011: composer auth.json persists on self-hosted runners (this workflow uses GitHub-hosted, mitigated) |
| MEDIUM | 75 | linters/bandit/action.yml:40 | DEP-004: tj-actions/bandit publisher had a 2025 supply-chain incident — consider commit-SHA pinning specifically for tj-actions |
| MEDIUM | 75 | codedeploy/deploy/action.yml:81 | BUG-008: `Ready` status treated as success; correct for in-place but premature for blue/green |
| MEDIUM | 75 | slack/index.test.js:86,114,141,168 | TEST-014: hardcoded hex color literals duplicate already-imported `COLORS` constant |
| MEDIUM | 70 | .github/workflows/build.yml:50,65,80,95... | CI-002: GH_PAT broadly exposed across all jobs; consider GitHub App token or job-scoped tokens |
| MEDIUM | 65 | variables/variables.sh | QUAL-016/BUG-013: missing `set -euo pipefail`; partly mitigated by GHA default `-eo pipefail` shell flags |
| MEDIUM | 60 | .github/workflows/auto-merge.yml:10-13 | CI-001: `issues:write` and `contents:write` are unused by the auto-merge workflow |
| MEDIUM | 60 | slack/index.test.js:238-266 | TEST-003: weak assertions (`toHaveBeenCalled()` only) on edge-case tests |
| MEDIUM | 55 | .github/workflows/auto-merge.yml | SEC-004: auto-approve gated only on CODEOWNERS membership; mitigated by single-owner CODEOWNERS, signed commits, and 10 required status checks |
| MEDIUM | 55 | soup/action.yml:42-47 | SEC-010: typo (doubled quotes) confirmed; security framing rejected (same-org repo over HTTPS) |
| MEDIUM | 55 | setup/action.yml | QUAL-001: 832-line god-action; remediation (split per-toolchain into v3) has poor ROI given consumer migration cost |
| LOW | 40 | linters/*/action.yml | QUAL-024: ~285 lines duplicated across 19 linter actions; GHA composite-calling-composite semantics blunt the refactor benefit |

### Rejected by Adversarial Validation (28)

For transparency, key rejections include: SEC-001/002/003 (eval-as-feature in aws/phpstan/phpcs — trusted workflow-author input, env-mapped, GitHub trust model); SEC-005/006/007 (env injection — mitigated by `head -n 1`, runner-trusted contexts, and hardcoded callers); SEC-008/009 (floating tags — explicit policy exclusion); SEC-013 (slack logs contain only public GitHub context); BUG-001/005/006/011/014/015/016 (premise relied on missing `-eo pipefail` which IS GHA bash default; or relied on env vars that GitHub guarantees); CI-004 (factually wrong — AWS creds not actually passed to lint jobs); CI-007 (no dependabot.yml is by design — github-build's DependabotManager intentionally substitutes a cron workflow); CI-008 (factually wrong — only 1 review required, no 2-reviewer rule to bypass); COMPAT-006 (only description text changed, not the input key); COMPAT-008 (CHANGELOG not required per skill exclusions); CFG-006 (`'4.0'` vs `4.0.3` are functionally equivalent for setup-ruby); QUAL-022 (`|| true` on cleanup is idiomatic best-effort, not silent failure).

---

## Action Items

### 🟠 High

- [ ] **TEST-002** Replace bats `extract_functions()` with `source variables.sh`; restore the test-to-prod link.
- [ ] **TEST-006** Add `npm run build && git diff --exit-code dist/` to `js_unit_tests` to catch dist drift.
- [ ] **TEST-008** Cover the variables.sh main body (tag/PR/branch detection, COMMIT_MESSAGE retrieval, MODIFIED_GITHUB_RUN_NUMBER) with bats integration tests.

### 🟡 Medium

- [ ] **TEST-001** Plan a coverage uplift for the 5 high-blast-radius actions (aws, codedeploy/*, docker, soup) — at minimum CI smoke tests.
- [ ] **TEST-012** Add smoke jobs in build.yml for the 18 unexercised actions.
- [ ] **TEST-009** Add bats tests for TRIVY auto-detection (18 trigger files) and CFNLINT detection.
- [ ] **TEST-015** Replace index-based block-kit assertions with type-/property-based ones.
- [ ] **GIT-001** Enable `require_code_owner_reviews` on master (or remove CODEOWNERS to avoid suggesting enforcement that isn't there).
- [ ] **GIT-007** Add a second CODEOWNER to remove bus-factor of 1.
- [ ] **GIT-008** Migrate CODEOWNERS to a team handle (`@Cloud-Officer/devops`).
- [ ] **BUG-009** Fix the misleading "5 mins" message in codedeploy/deploy (loop is actually ~10 mins).
- [ ] **COMPAT-009** Establish a versioning policy: bump to v3 for behaviour-changing defaults, OR publish GitHub Releases with notes.
- [ ] **CFG-008** Decide on a default php-version (8.3 or 8.4) and tag it explicitly.
- [ ] **CFG-014** Switch NODE-VERSION to current LTS (24.x). Rename env var to underscore form.
- [ ] **CI-005** Pass `node-cache: 'npm'` to setup@v2 in js_unit_tests.
- [ ] **CI-006** Add `concurrency:` block to build.yml to cancel superseded runs.
- [ ] **DOC-002** Fix aws/README.md title and YAML indentation.

### 🔵 Low

- [ ] **QUAL-014** Fix the doubled-quote typo in soup/action.yml:44.
- [ ] **QUAL-008** Add `name:` to the first step in eslint/bandit/semgrep/actionlint actions for consistency.
- [ ] **QUAL-018** Replace `console.log` in slack/index.js with `core.debug` (gated by `core.isDebug()`).
- [ ] **COMPAT-007** Document the rubocop ruby 3.4 → 4.0 default change in the rubocop README.
- [ ] **DOC-001** Rename BUG_REPORT.MD → BUG_REPORT.md.
- [ ] **DOC-003** Standardise on `@v2` and `Cloud-Officer` casing across all README examples.
- [ ] **DOC-005** Update the codedeploy timeout echo to "> 10 mins".
- [ ] **DOC-006** Either install flake8-docstrings or rename the flake8 step.
- [ ] **DOC-008** Rename the substring-match bats test to reflect actual behavior, OR fix `has_trigger` to use word boundaries.
- [ ] **DEP-001** Bump @actions/core ^2.0.3 → ^3.0.1 (regenerate dist/).
- [ ] **DEP-002** Bump aquasecurity/trivy-action 0.35.0 → 0.36.0.
- [ ] **DEP-003** Bump webfactory/ssh-agent v0.9.1 → v0.10.0.
- [ ] **SEC-012** Validate APT_PACKAGES against a regex or use `xargs -d ' '` to prevent argument injection.

### ⚪ Info

- [ ] Consider switching `has_trigger` from `grep -iF` to `grep -iwF` to prevent future trigger-name substring collisions.

---

*Report generated: 2026-05-07*
*Files scanned: 30 source files, 29 npm dependencies, 28 composite actions, 2 workflows*
