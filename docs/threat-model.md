# Threat Model — ci-actions (reusable GitHub Actions library)

**Date:** 2026-09-07 **Scope:** the whole repository — 28 `action.yml` composite/JS actions, 4 workflows in
`.github/workflows/`, 9 shell scripts, and the `slack` Node action. No sampling: every action manifest and every
workflow was read. Out of scope: the consumer repositories that call these actions, the `github-build` generator that
emits their workflows, and `Cloud-Officer/soup` (modelled only as an external dependency).
**Method:** STRIDE, plus one attack tree for the single critical path (code execution inside a consumer's deploy job).
LINDDUN was **not** layered in: the only personal data handled is GitHub handles and commit-message authorship
(`slack/index.js:97`), forwarded to Slack — no PII, PHI, or payment data flows through any action. PASTA was not used;
there is no business-transaction surface to model.
**Status:** DRAFT — AI-generated first pass, requires human security sign-off. The accept-vs-mitigate decision on every
threat below belongs to a person, not to this document.

## System overview

`ci-actions` is not a service. It is a **credential-handling execution library**: a collection of composite GitHub
Actions that consumer repositories reference as `uses: cloud-officer/ci-actions/<action>@v3`. Every action runs inside
the *consumer's* GitHub Actions job, on a GitHub-hosted runner, with the consumer's secrets passed in as inputs.

That inverts the usual threat picture. This repository holds no data and exposes no network endpoint; its security
value is entirely **integrity of the code that other pipelines execute**, and **confinement of the secrets those
pipelines hand it**.

Data flow, grounded in `.github/workflows/build.yml` (which is itself a consumer of this library):

1. `variables` (`variables/action.yml`) checks out the consumer repo with the `SSH_KEY` deploy key, runs
   `variables/variables.sh`, and derives build identifiers and CI control flags from the **commit message**.
2. 19 `linters/*` actions run in parallel, each gated by `linters/_lib/check_enabled.sh`. Each checks out the consumer
   repo (`submodules: recursive`), installs a toolchain from the internet, and runs a linter over untrusted repository
   content, reporting through `reviewdog` to the PR.
3. `setup` (`setup/action.yml`, 940 lines) configures language runtimes, databases, AWS credentials, and an ssh-agent
   holding the deploy key.
4. `aws`, `codedeploy/{checkout,deploy,s3copy}`, and `docker` perform the actual deployment with live AWS and Docker
   Hub credentials.
5. `soup` downloads and executes `Cloud-Officer/soup` for licence compliance.
6. `slack` (`slack/index.js`, a `node24` action) posts the result to an incoming webhook.

## Assets

| Asset | Sensitivity | Where it lives |
| :--- | :--- | :--- |
| AWS access key ID / secret access key / session token | Critical | Inputs to `aws/action.yml:13`, `codedeploy/deploy/action.yml:10`, `codedeploy/s3copy/action.yml:10`, `setup/action.yml:33`; consumed by `aws-actions/configure-aws-credentials@v6` |
| Deploy artifacts and their S3 keys | High | `codedeploy/deploy/deploy.sh:22` (`bucket=${S3_BUCKET},key=${S3_KEY}`), derived from `BUILD_NAME` in `variables/variables.sh:167` |
| Docker Hub username / password | High | Inputs to `docker/action.yml:10`; consumed by `docker/login-action@v4` |
| GitHub organisation PAT (`GH_PAT`, passed as `github-token`) | Critical | Input default `${{ github.token }}` on every action; overridden with `secrets.GH_PAT` at `.github/workflows/build.yml:54`. Exported as `GITHUB_TOKEN` into package-install steps |
| Java GPG signing key and passphrase, Maven server credentials | High | `setup/action.yml` inputs `java-gpg-private-key`, `java-gpg-passphrase-env-var`, `java-server-*` |
| Service passwords (MySQL root/user, MongoDB, RabbitMQ) | Medium | `setup/action.yml` inputs `mysql-root-password`, `mysql-password`, `mongodb-password` |
| Slack incoming webhook URL | Medium | Input to `slack/action.yml:10` |
| SSH deploy key (`SSH_KEY`) | Critical | Input `ssh-key` on 24 of 28 actions; loaded into a job-scoped agent by `webfactory/ssh-agent` at `setup/action.yml:598` and `linters/phpstan/action.yml:61` |
| The action source itself (integrity, not confidentiality) | Critical | This repository, resolved by consumers through the mutable `v3` tag |
| `reviewdog-token` (job-scoped `GITHUB_TOKEN`) | Medium | Input on 9 reviewdog-reporting linters, e.g. `linters/shellcheck/action.yml:23` |

## Trust boundaries & entry points

| # | Boundary / entry point | File / route | Actors reaching it |
| :--- | :--- | :--- | :--- |
| 1 | AWS control plane (CodeDeploy, S3, STS) | `codedeploy/deploy/deploy.sh:17`, `codedeploy/s3copy/action.yml:55` | Anything with code execution in the deploy job |
| 2 | Checked-out repository content → linter execution | `linters/*/action.yml` checkout steps; `linters/_lib/clean_workspace.sh:56` | Any contributor to a consumer repo; a fork-PR author (without secrets) |
| 3 | Commit message → CI control flags | `variables/variables.sh:7` (`has_trigger`), consumed at `.github/workflows/build.yml:76` | Anyone who can push a commit or open a PR |
| 4 | Consumer workflow → composite action inputs (secrets cross here) | `.github/workflows/build.yml:52`; every `action.yml` `inputs:` block | Consumer repo maintainers; the `github-build` generator |
| 5 | Docker Hub registry push | `docker/action.yml:59` | Anything with code execution in the docker job |
| 6 | External GitHub Action references (20 distinct third parties) | `linters/shellcheck/action.yml:49`, `setup/action.yml:598`, and 81 other `uses:` refs | Upstream action maintainers; anyone who compromises them |
| 7 | GitHub PR API via reviewdog | `linters/flake8/action.yml:74` and 8 more `reporter=github-pr-review` call sites | reviewdog upstream; the PR being linted |
| 8 | Package registries and toolchain downloads (apt, npm, PyPI, RubyGems, Composer, GitHub Releases) | `linters/_lib/install_swiftlint.sh:92`, `linters/eslint/action.yml:64`, `linters/semgrep/action.yml:51`, `linters/trivy/action.yml:85`, `soup/action.yml:45` | Registry operators; package maintainers; anyone who compromises them |
| 9 | Slack incoming webhook (outbound) | `slack/index.js:194` | Build metadata leaves the org boundary |
| 10 | `pull_request_target` auto-approval | `.github/workflows/auto-approve.yml:4` | Any member of `@Cloud-Officer/Maintainers` |
| 11 | `Cloud-Officer/soup` tag resolution and execution | `soup/action.yml:42` | Anyone who can push a tag to that repository |
| 12 | `cloud-officer/ci-actions@v3` mutable tag resolution | `.github/workflows/build.yml:51` and every consumer workflow | Anyone with write access to this repository |

### Attack tree — code execution in a consumer's deploy job

The one goal worth enumerating exhaustively, because every asset above is reachable from it.

```text
GOAL: execute attacker code in a consumer job holding SSH_KEY + GH_PAT + AWS credentials
├── 1. Move what @v3 points at                                    [T-01]
│   ├── 1.1 compromise a @Cloud-Officer/Maintainers account
│   │        └── open PR -> auto-approved by GH_BOT_PAT           [T-03]
│   ├── 1.2 force-push the v3 tag directly
│   └── 1.3 land a malicious change through the weekly bump PR    [T-02]
├── 2. Compromise an upstream action this repo references         [T-02]
│   ├── 2.1 any of 20 third parties, all on floating major tags
│   └── 2.2 reviewdog_version/node-version/swiftlint "latest"
├── 3. Poison a toolchain download
│   ├── 3.1 SwiftLint zip — no signature, no checksum             [T-09]
│   ├── 3.2 trivy apt signing key — trust-on-first-use            [T-12]
│   ├── 3.3 Cloud-Officer/soup — first-tag resolution, no pin     [T-07]
│   └── 3.4 npm/PyPI/RubyGems package or transitive dependency    [T-05]
└── 4. Get the linter to execute repo-controlled content          [T-06]
    └── 4.1 .eslintrc.json / .rubocop.yml / phpstan.neon require()
        └── runs alongside the ssh-agent holding the deploy key
```

## Threats (prioritized)

Rating rubric — **Impact** (Critical/High/Medium/Low) × **Likelihood** (High/Medium/Low), combined via the matrix
below. Ordering only; no false-precision score.

| Impact \ Likelihood | High | Medium | Low |
| :--- | :--- | :--- | :--- |
| Critical | Critical | Critical | High |
| High | High | High | Medium |
| Medium | Medium | Medium | Low |
| Low | Low | Low | Low |

### T-01 — Mutable `v3` tag makes this repository a single point of compromise for every consumer pipeline · Risk: Critical

- **STRIDE category:** Tampering, Elevation of privilege
- **Abuse path:** Every consumer resolves `uses: cloud-officer/ci-actions/variables@v3`
  (`.github/workflows/build.yml:51`; `README.md` documents `v3` as the intended reference and `git tag` confirms `v1`,
  `v2`, `v3` all exist as floating tags alongside immutable `3.0.0`–`3.0.2`). An attacker with write access to this
  repository — or who force-pushes the `v3` tag — replaces the body of any action. On the next run of every consumer
  repository, that code executes with the consumer's `SSH_KEY`, `GH_PAT`, AWS credentials and Docker Hub password
  already configured in the job. There is no SHA pin, no signed tag, no release attestation, and no verification step
  between the tag and execution.
- **Likelihood × Impact:** Medium × Critical
- **Existing control:** `.github/CODEOWNERS` requires `@Cloud-Officer/Maintainers` on `*`, `.github/`, `*.sh` and
  `codedeploy/`; the smoke and contract suites (`tests/action_contracts.py` and seven siblings, run by
  `.github/workflows/smoke.yml`) block malformed manifests. Neither constrains a maintainer who intends the change.
- **Recommended mitigation:** Publish immutable release tags only and recommend SHA pinning in `README.md`; enable
  GitHub's tag protection rules on `v*` and `[0-9]*`; sign release tags and require signed commits on `master`; treat
  `v3` as a convenience alias documented as *unsafe for repositories holding production deploy credentials*.
- **Residual risk / decision:** For human sign-off. Moving consumers to SHA pins is a `github-build` generator change,
  not a change here — the two must be sequenced together.

### T-02 — No external action reference is SHA-pinned; a weekly cron actively moves them to `latest` · Risk: Critical

- **STRIDE category:** Tampering, Elevation of privilege
- **Abuse path:** Of 83 `uses:` references across the repository, **zero** are pinned to a 40-character SHA
  (`grep -rn 'uses:.*@[0-9a-f]\{40\}' --include=action.yml .` returns nothing). All 20 distinct third parties sit on
  floating major tags — `reviewdog/action-shellcheck@v1` (`linters/shellcheck/action.yml:49`),
  `webfactory/ssh-agent@v0.10.0` (`setup/action.yml:598`, holding the deploy key), `shivammathur/setup-php@v2`,
  `amyu/setup-android@v6.0`, `ScaCap/action-ktlint@v1`, `ankane/setup-opensearch@v1`, and the `actions/*` and
  `docker/*` families. Several are pinned to a literal moving target: `reviewdog_version: latest`
  (`linters/markdownlint/action.yml:62`), `node-version: latest` (`linters/eslint/action.yml:56`), `ruby-version: ruby`
  (`soup/action.yml:58`), `swiftlint-version: latest` (`linters/swiftlint/action.yml:25`),
  `image=moby/buildkit:latest` (`docker/action.yml:47`). An upstream maintainer compromise — the
  `tj-actions/changed-files` incident of March 2025 is the exact shape — retags the floating major and executes in
  every consumer job on the next run. `.github/workflows/external-actions-bump.yml` then *accelerates* this: it runs
  weekly and rewrites refs forward to whatever upstream published (`bump-actions/bump-actions.sh:73`).
- **Likelihood × Impact:** Medium × Critical
- **Existing control:** `bump-actions.sh:100` explicitly skips refs that are already SHA-pinned, so pinning is
  compatible with the cron. The bump opens a PR for human review rather than pushing to `master`
  (`.github/workflows/external-actions-bump.yml:69`).
- **Recommended mitigation:** Pin every external ref to a full commit SHA with a `# vN.N.N` trailing comment, and
  teach `bump-actions.sh` to resolve tag→SHA and rewrite both the pin and the comment. Enable Dependabot's
  `github-actions` ecosystem (see T-18) so the pins stay current with review. Replace the three `latest` toolchain
  values with explicit versions.
- **Residual risk / decision:** For human sign-off. Pinning trades a supply-chain window for a maintenance cost the
  bump cron is already designed to absorb.

### T-03 — Auto-approval with a bot PAT removes the four-eyes control on a repository every consumer executes · Risk: High

- **STRIDE category:** Elevation of privilege, Repudiation
- **Abuse path:** `.github/workflows/auto-approve.yml:88` runs `gh pr review --approve "$PR"` with
  `secrets.GH_BOT_PAT` for any non-draft PR whose author is in `@Cloud-Officer/Maintainers`. The self-approval guard
  at line 83 compares `gh api user --jq .login` (the *bot*) against the PR author, so it never fires for a
  human-authored PR — every maintainer PR is approved automatically. Chained with T-01: one compromised maintainer
  account opens a PR that modifies an action, receives an automatic approval, and — if branch protection requires one
  approval and auto-merge is enabled — reaches `master` and then `v3` with no second human ever looking at it.
- **Likelihood × Impact:** Medium × High
- **Existing control:** Real and worth keeping: the workflow is gated on
  `head.repo.full_name == github.repository` (line 20), so fork PRs never reach it; it checks out
  `github.event.pull_request.base.sha` (line 26), not the PR head, so the classic `pull_request_target` pwn-request
  does not apply; and it reads CODEOWNERS from the base commit.
- **Recommended mitigation:** Exclude paths that change execution semantics from auto-approval — `*/action.yml`,
  `*.sh`, `slack/`, `.github/workflows/` — so those still require a second human. Alternatively scope `GH_BOT_PAT` so
  it cannot approve, and use auto-approval only for the generated-workflow and dependency-bump PRs it was built for.
- **Residual risk / decision:** For human sign-off. Whether this is acceptable depends on branch-protection settings
  not visible in the repository — see Assumptions.

### T-04 — Any contributor can disable every security gate from a commit message · Risk: High

- **STRIDE category:** Tampering, Elevation of privilege
- **Abuse path:** `variables/variables.sh:7` matches CI control flags with `grep -iF "#$1"` against the first line of
  the commit message; `#skip-all` sets `SKIP_LICENSES`, `SKIP_LINTERS` and `SKIP_TESTS` to `1`
  (`variables/variables.sh:196`). Those outputs gate the jobs at `.github/workflows/build.yml:76` (Bandit), `:140`
  (Semgrep) and `:170` (Trivy) — the three security scanners — plus every other linter and both test suites. GitHub
  treats a **skipped** required status check as satisfied, so a commit message containing `#skip-all` produces a green,
  mergeable PR with no SAST, no IaC scan, no secret scan and no tests. The match is unanchored and case-insensitive, so
  it also fires accidentally: a commit titled `Document the #skip-all flag`, or a squash-merge commit whose subject
  quotes a PR title mentioning the flag, silently disables the same gates.
- **Likelihood × Impact:** High × High
- **Existing control:** `DEPLOY_ON_PROD` additionally requires a tag (`variables/variables.sh:183`), so the *deploy*
  triggers are harder to abuse than the *skip* triggers. `variables/tests/variables.bats` covers the resolution logic.
- **Recommended mitigation:** Require a token that only a maintainer can supply for the skip flags (e.g. honour them
  only when the pushing actor is a code owner, or only on `push` to `master`/tags, never on `pull_request`). Anchor the
  match to a trailer line rather than a substring anywhere in the subject. At minimum, make the security scanners
  (Semgrep, Trivy, Bandit) unskippable and split them out of `SKIP_LINTERS`.
- **Residual risk / decision:** Partially accepted already — the organisation has recorded a decision that
  `#skip-tests` skipping the unit-test jobs is by design for the post-merge tag→prod path. That decision covers
  `SKIP_TESTS`; it does **not** obviously extend to `SKIP_LINTERS` disabling Semgrep, Trivy and Bandit on a PR. Needs
  an explicit call.

### T-05 — A long-lived organisation PAT is exported into steps that execute third-party install scripts · Risk: High

- **STRIDE category:** Information disclosure, Elevation of privilege
- **Abuse path:** `.github/workflows/build.yml:54` passes `secrets.GH_PAT` as `github-token`, and every action exports
  it into the step environment as `GITHUB_TOKEN` — including steps whose entire purpose is to run untrusted code:
  `npm install "eslint@${ESLINT_VERSION}"` (`linters/eslint/action.yml:64`, executed inside the checked-out repo, so
  the repo's own `package.json` lifecycle scripts run too), `npm install -g markdownlint-cli2`
  (`linters/markdownlint/action.yml:78`), `pip install semgrep` (`linters/semgrep/action.yml:51`), `pip install bandit`
  (`linters/bandit/action.yml:55`), `pip install --upgrade flake8 flake8-docstrings` (`linters/flake8/action.yml:68`),
  `bundle install` (`soup/action.yml:71`), and `sudo apt-get install ${APT_PACKAGES}` (`setup/action.yml:639`). Any
  `postinstall`, `setup.py`, `extconf.rb` or Debian maintainer script in the resolved dependency tree reads
  `process.env.GITHUB_TOKEN` and exfiltrates an org-wide, long-lived credential. Unlike the job's own
  `GITHUB_TOKEN`, `GH_PAT` does not expire with the job and is not scoped to one repository.
- **Likelihood × Impact:** Medium × High
- **Existing control:** Genuinely good separation already exists for the third-party *actions*: `reviewdog-token` is a
  deliberately separate input defaulting to the job token specifically so the org PAT never reaches reviewdog
  (`linters/shellcheck/action.yml:16-23`), and `linters/phpstan/action.yml` uses step-scoped `COMPOSER_AUTH` rather
  than a global `auth.json` for the same reason. `tests/token_contract.py` enforces that installs stay authenticated —
  which is why the token is there (API rate limits), not an oversight.
- **Recommended mitigation:** Use the *job* `GITHUB_TOKEN` for rate-limit purposes in package-install steps and reserve
  `GH_PAT` for the checkout steps that genuinely need private-submodule access; better still, replace the PAT with a
  short-lived GitHub App installation token. Where a registry needs no GitHub auth at all (PyPI, npm public,
  RubyGems), drop the variable entirely and relax `tests/token_contract.py` for those specific steps.
- **Residual risk / decision:** For human sign-off — this trades a small rate-limit risk against a large blast radius.

### T-06 — Linters execute repository-controlled configuration in a job whose ssh-agent holds the deploy key · Risk: High

- **STRIDE category:** Elevation of privilege, Information disclosure
- **Abuse path:** `linters/phpstan/action.yml:61` starts `webfactory/ssh-agent@v0.10.0` with the `SSH_KEY` deploy key;
  the agent stays live for the rest of the job (`setup/action.yml:598` does the same for every build job). Later steps
  in that job run linters whose configuration files are **repository content, and are code**: `.eslintrc.json` can
  `require()` an arbitrary local module, `.rubocop.yml` supports `require:`, `phpstan.neon` supports `bootstrapFiles`,
  markdownlint-cli2 loads custom JS rules, and `.pmd.xml` references arbitrary rulesets
  (`linters/pmd/action.yml:87` runs `pmd check -R ".pmd.xml"` straight from the checkout). A contributor who can add or
  modify one of those files in a consumer repository gets code execution in a job that can authenticate as the org
  deploy key via the agent socket, and that has `GH_PAT` in its environment (T-05). The private key itself is not
  extractable from the agent, but every repository the key grants is reachable.
- **Likelihood × Impact:** Medium × High
- **Existing control:** `tests/linter_gate_contract.py` blocks a linter step — the phpstan ssh-agent explicitly
  included — from running while that linter is disabled. `persist-credentials: false` on every checkout means
  `actions/checkout` deletes the SSH key file and git config at the end of its own step, so the key is not left on
  disk. The ssh-*agent* is the remaining exposure, not the key file.
- **Recommended mitigation:** Do not start the ssh-agent in linter jobs at all — `linters/phpstan` is the only linter
  that does, and its checkout already handles private submodules via `ssh-key`. Where an agent is unavoidable, use
  `ssh-agent -t <seconds>` or kill the agent before the linter step. Consider running linters against a workspace
  stripped of executable lint configuration when the PR modifies those files.
- **Residual risk / decision:** For human sign-off. Removing the phpstan ssh-agent is a small, testable change; the
  broader "lint config is code" exposure is inherent to every linter platform.

### T-07 — `soup` resolves and executes an unpinned tag from `Cloud-Officer/soup`, then runs `bundle install` · Risk: High

- **STRIDE category:** Tampering, Elevation of privilege
- **Abuse path:** `soup/action.yml:42` picks `.[0].name` from `GET /repos/Cloud-Officer/soup/tags` — the *first tag the
  API happens to return*, which is not a semver-latest guarantee and is not a pin. It downloads that tag's zip
  (`:45`), unzips it, runs `bundle install` against the archive's own `Gemfile` (`:71`), then executes `bin/soup.rb`
  (`:73`). There is no checksum, no signature, and no version constraint anywhere in the chain. Anyone able to push a
  tag to `Cloud-Officer/soup` — or to influence which tag sorts first — achieves code execution in every consumer's
  licence-compliance job, with `GITHUB_TOKEN` (the org PAT, T-05) in the environment. Separately, `${PARAMETERS}` at
  `:73` is deliberately unquoted, so a caller-supplied `parameters` input is word-split into `soup.rb` arguments.
- **Likelihood × Impact:** Medium × High
- **Existing control:** The download is over HTTPS to `github.com`, and the tag listing is authenticated. `soup` is a
  first-party repository under the same organisation, so this is an internal rather than external trust boundary.
- **Recommended mitigation:** Pin the soup version with an input (default to a known-good tag, not "first tag
  returned"), verify a published checksum or signature before unzip, and run `bundle install --deployment` against a
  committed `Gemfile.lock`. Quote `${PARAMETERS}` or pass it as an array.
- **Residual risk / decision:** For human sign-off. First-party provenance lowers likelihood but does not remove the
  unpinned-execution pattern.

### T-08 — Consumer-supplied `shell-commands` is executed verbatim with AWS credentials configured · Risk: Medium

- **STRIDE category:** Elevation of privilege, Tampering
- **Abuse path:** `aws/action.yml:65` runs `bash -eo pipefail -c -- "${SHELL_COMMANDS}"` immediately after
  `aws-actions/configure-aws-credentials@v6` has configured live AWS credentials. The same pattern appears at
  `linters/phpcs/action.yml:99` (`COMPOSER_COMMAND`) and `:108` (`PHP_CS_FIXER_COMMAND`). Arbitrary execution is the
  documented purpose of the `aws` action, so this is not a defect *here* — but a consumer workflow that interpolates
  `${{ github.event.pull_request.title }}`, `${{ github.head_ref }}` or an issue body into `shell-commands` produces
  textbook GitHub Actions script injection, and the result runs with production AWS credentials. Nothing in
  `aws/README.md` warns against it.
- **Likelihood × Impact:** Low × High
- **Existing control:** This repository is disciplined about the pattern internally: exactly one `run:` block in the
  whole repository interpolates a `${{ }}` expression (`variables/action.yml:78`, and `github.action_path` is
  runner-controlled). Every other value crosses into shell via `env:`, which is the correct mitigation, and
  `linters/_lib/require_inputs.sh` documents the rule in its header.
- **Recommended mitigation:** Document the constraint prominently in `aws/README.md` and `linters/phpcs/README.md`:
  never interpolate `github.event.*`, `github.head_ref` or any PR-controlled value into these inputs. Consider a
  contract test in `tests/` that scans consumer-facing examples for the anti-pattern.
- **Residual risk / decision:** Accept with documentation — the capability is the product.

### T-09 — SwiftLint is downloaded and executed with no signature or checksum verification · Risk: Medium

- **STRIDE category:** Tampering
- **Abuse path:** `linters/_lib/install_swiftlint.sh:92` downloads a release zip from
  `https://github.com/realm/SwiftLint/releases/download/...`, unzips it (`:98`), `chmod +x`-es the binary (`:117`) and
  executes it over the checkout. `SWIFTLINT_VERSION` defaults to `latest` (`linters/swiftlint/action.yml:25`) and is
  resolved from the GitHub API at run time (`:129`), so both *what* is downloaded and *that it is authentic* rest
  entirely on TLS to github.com. This is inconsistent with the two siblings that got it right: `linters/pmd` verifies
  a detached GPG signature against a full 40-character fingerprint (`linters/pmd/action.yml:75`), and `linters/phpcs`
  does the same (`linters/phpcs/action.yml:81`), with a comment explaining precisely why long key IDs are unsafe.
- **Likelihood × Impact:** Low × High
- **Existing control:** HTTPS with `curl --fail`; the shared `linters/_lib/recv_gpg_key.sh` helper already exists and
  is used by the other two actions, so the mechanism is available.
- **Recommended mitigation:** Pin `SWIFTLINT_VERSION` to a release and verify the published SHA-256 of the asset, or
  GPG-verify via the existing `recv_gpg_key.sh` helper if upstream signs releases. Add a contract test asserting every
  binary download in `linters/` is followed by a verification step.
- **Residual risk / decision:** For human sign-off.

### T-10 — Caller-supplied `apt-packages` is word-split into a root `apt-get` command line · Risk: Medium

- **STRIDE category:** Elevation of privilege
- **Abuse path:** `linters/phpstan/action.yml:75` and `setup/action.yml:639` both run
  `sudo apt-get --yes --no-install-recommends install ${APT_PACKAGES}` with the expansion deliberately unquoted so a
  space-separated list splits into multiple packages. Word splitting does not distinguish package names from
  *options*: a value such as `-o APT::Update::Pre-Invoke::=<command>` or `-o Dir::Etc::SourceList=<attacker path>` is
  accepted as an apt-get argument and runs under `sudo`. The input is caller-controlled, so this is only reachable by
  whoever writes the consumer workflow — but that workflow is generated by `github-build` from repository
  configuration, widening the set of people who can influence it.
- **Likelihood × Impact:** Low × High
- **Existing control:** Both steps are gated (`inputs.apt-packages != 'none'`, plus the linter-enabled check on
  phpstan), and `.github/workflows/smoke.yml:139` pins `apt-packages: 'none'` defensively on the disabled path.
- **Recommended mitigation:** Read the list into a bash array and validate each element against
  `^[a-z0-9][a-z0-9+.-]*$` before passing it, then invoke `apt-get install -- "${pkgs[@]}"`. The `--` terminator alone
  closes the option-injection path.
- **Residual risk / decision:** For human sign-off. Cheap to fix; low likelihood.

### T-11 — `semgrep --config=auto` fetches its rule set from a third party at scan time and sends repository metadata out · Risk: Medium

- **STRIDE category:** Tampering, Information disclosure
- **Abuse path:** `linters/semgrep/action.yml:58` runs `semgrep scan --config=auto`. `auto` resolves the rule set from
  the semgrep.dev registry over the network on every run and transmits repository metadata to do so. Semgrep rules are
  executable configuration (patterns plus `fix` directives), so the security gate that decides whether a build passes
  is defined by a third party at run time, is not reproducible across runs, and fails open if the registry is
  unreachable in a way the action does not distinguish from "no findings". `pip install semgrep` (`:51`) is likewise
  unpinned.
- **Likelihood × Impact:** Medium × Medium
- **Existing control:** `--error` makes findings fail the build rather than warn; `--severity=ERROR` bounds the noise.
  The job narrows its own permissions at `.github/workflows/build.yml:134`.
- **Recommended mitigation:** Vendor a rule set (`--config=p/ci --config=./.semgrep.yml`, both pinned) or mirror the
  registry ruleset into the repository so scans are reproducible and offline-capable; pin the `semgrep` version. Note
  separately that the `actions: read` permission granted at `.github/workflows/build.yml:135` is justified in
  `docs/architecture.md` as needed for a SARIF upload, but the action performs no SARIF upload — the grant is stale
  and should be dropped.
- **Residual risk / decision:** For human sign-off; `--config=auto` is a deliberate coverage-vs-reproducibility trade.

### T-12 — The Trivy apt signing key is trusted on first use with no fingerprint check · Risk: Medium

- **STRIDE category:** Tampering
- **Abuse path:** `linters/trivy/action.yml:85` pipes
  `wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor | sudo tee
  /usr/share/keyrings/trivy.gpg`, then registers that keyring as trusted for the repository (`:105`) and
  `sudo apt-get install -y trivy` (`:107`). The key is accepted purely because TLS to a GitHub Pages host succeeded —
  there is no expected-fingerprint assertion, so a compromised or substituted key is indistinguishable from the real
  one, and whatever it signs is then installed as a root package. The installed binary is the organisation's IaC,
  secret and vulnerability gate. `trivy` version is unpinned (`apt-get install -y trivy` takes whatever the repo
  serves).
- **Likelihood × Impact:** Low × High
- **Existing control:** HTTPS throughout; `signed-by=` correctly scopes the keyring to this one repository rather than
  adding it to the global trusted set; the codename is verified to exist before the source is written (`:100`).
- **Recommended mitigation:** Assert the expected key fingerprint after `--dearmor` (fail the step on mismatch), the
  way `linters/pmd` and `linters/phpcs` already assert full fingerprints for their GPG keys. Pin the Trivy version.
- **Residual risk / decision:** For human sign-off.

### T-13 — Dependabot coverage is not declared in the repository · Risk: Low

- **STRIDE category:** Tampering (supply chain)
- **Abuse path:** `.github/workflows/build.yml:15` includes `dependabot/**` in its push triggers and the git history
  shows Dependabot security PRs landing (`021f363`, `f5bc9a6`, and 46 more bump commits), so Dependabot is clearly
  enabled — but there is no `.github/dependabot.yml` in the repository. Coverage therefore depends on repository-level
  UI settings that are neither versioned, reviewable, nor auditable, and there is no evidence the `github-actions`
  ecosystem (the 83 unpinned refs of T-02) is monitored at all, as opposed to only npm in `/slack`. There is also no
  `SECURITY.md`, so an external reporter has no disclosure channel.
- **Likelihood × Impact:** Low × Medium
- **Existing control:** Dependabot security updates are demonstrably active for the npm ecosystem in `slack/`.
- **Recommended mitigation:** Commit `.github/dependabot.yml` covering `npm` (`/slack`) and `github-actions` (`/`),
  and add `SECURITY.md` with a disclosure contact. Both are direct ISO 27001 A.8.8 evidence.
- **Residual risk / decision:** Recommend mitigate — low cost, closes an audit gap.

### T-14 — Stale `actions: read` grant on the semgrep job · Risk: Low

- **STRIDE category:** Elevation of privilege
- **Abuse path:** `.github/workflows/build.yml:135` grants `actions: read` to the semgrep job.
  `docs/architecture.md` justifies it as needed "because the SARIF upload needs to read the workflow run", but
  `linters/semgrep/action.yml` performs no SARIF upload — it only `pip install`s and runs `semgrep scan`. The grant
  widens what a compromised step in that job can read (workflow runs, logs, artifacts) for no functional reason, and
  the documentation asserting otherwise makes the drift harder to notice.
- **Likelihood × Impact:** Low × Low
- **Existing control:** The job otherwise narrows below the workflow default by dropping `pull-requests: write`.
- **Recommended mitigation:** Drop `actions: read` and correct the paragraph in `docs/architecture.md`. Note the file
  is generated by `github-build` — fix the generator, not the workflow.
- **Residual risk / decision:** Recommend mitigate.

### T-15 — flake8 disables PEP 668 protection before installing into the system Python · Risk: Low

- **STRIDE category:** Tampering
- **Abuse path:** `linters/flake8/action.yml:67` runs `sudo rm -f /usr/lib/python3*/EXTERNALLY-MANAGED` and then
  `pip install --upgrade flake8 flake8-docstrings` (`:68`) into the system interpreter. Removing the marker
  deliberately defeats the guard that keeps pip from writing into a distribution-managed environment, so package
  install scripts (and anything they pull in transitively) write to system paths that later steps in the same job
  execute from — with `GITHUB_TOKEN` in the environment (T-05). No version is pinned.
- **Likelihood × Impact:** Low × Medium
- **Existing control:** The step is gated on the linter being enabled; runners are ephemeral, so contamination does not
  persist beyond the job.
- **Recommended mitigation:** Install into a virtualenv or use `pip install --user`/`pipx` rather than removing the
  marker; pin `flake8` and `flake8-docstrings`.
- **Residual risk / decision:** For human sign-off; runner ephemerality bounds the impact.

### T-16 — Divergent `.gitmodules` parsing leaves a latent path-traversal trap · Risk: Low

- **STRIDE category:** Tampering
- **Abuse path:** `linters/trivy/action.yml:65` and `variables/variables.sh:98` both parse `.gitmodules` with the
  unanchored `grep 'path = ' | sed 's/.*path = //'` form, which matches any line merely containing that text — a URL
  such as `https://example.com/path = x.git` included. `.gitmodules` is repository content, and on a PR it is
  attacker-controlled. Today neither call site is exploitable: both feed the values into quoted `find` arguments,
  which cannot escape or execute. But `linters/_lib/clean_workspace.sh:41-56` already fixed exactly this parsing bug
  and added explicit `/*` and `*..*` rejection (`:48-53`) precisely because *its* values reach `rm -rf`. The two
  remaining copies are the pre-fix version; if either ever grows a filesystem-mutating consumer, the traversal is
  reintroduced silently.
- **Likelihood × Impact:** Low × Low
- **Existing control:** Both current consumers are read-only `find` invocations with properly quoted array elements.
- **Recommended mitigation:** Move the hardened parser out of `clean_workspace.sh` into `linters/_lib/` as a shared
  function and have all three call sites use it — the same single-sourcing pattern already applied to
  `linters/_lib/lock_files.sh` and enforced by `tests/lock_file_contract.py`.
- **Residual risk / decision:** Recommend mitigate as hygiene; not currently exploitable.

### T-17 — The Slack action logs the full outbound payload · Risk: Low

- **STRIDE category:** Information disclosure
- **Abuse path:** `slack/index.js:193` logs the complete Slack payload to the job log, and `:195` logs the response
  body; `reportError` (`:214-219`) logs the error stack and the axios response body on failure. The payload embeds the
  commit message (`:106`), repository, ref, and actor login (`:97`). The webhook URL itself is never logged, and
  GitHub masks it when it arrives from `secrets.*` — but a consumer that passes it as a literal string gets no masking,
  and any secret that a developer put in a commit message is reproduced verbatim into the job log and into Slack.
- **Likelihood × Impact:** Low × Medium
- **Existing control:** `parseInputs` rejects an empty `webhook-url` (`:53`); the POST is bounded by a 30s timeout
  (`:194`); the URL is not among the logged values.
- **Recommended mitigation:** Gate the payload dump behind `core.isDebug()` rather than logging it unconditionally,
  and document that `webhook-url` must come from `secrets.*` so GitHub's masking applies.
- **Residual risk / decision:** Recommend mitigate; trivial change.

### T-18 — The GitHub token is embedded in a git remote URL · Risk: Low

- **STRIDE category:** Information disclosure
- **Abuse path:** `variables/variables.sh:146` fetches tags over
  `https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git`. Credentials in a URL are recoverable
  from git's own error output, from `GIT_TRACE`/`GIT_CURL_VERBOSE` if a debugging session enables them, and from any
  process listing during the fetch. The token here is the org PAT (T-05).
- **Likelihood × Impact:** Low × Medium
- **Existing control:** The script does not run under `set -x`, so bash never echoes the expanded command; GitHub masks
  registered secrets in logs; the comment at `:141` documents why the authenticated URL is needed (the
  `persist-credentials: false` checkout strips `core.sshCommand`, so `git fetch origin` fails on tag builds). The
  reasoning is sound — only the mechanism is improvable.
- **Recommended mitigation:** Pass the credential through `-c http.extraheader="AUTHORIZATION: basic $(...)"` or a
  `GIT_ASKPASS` helper instead of interpolating it into the URL.
- **Residual risk / decision:** Accept or mitigate — for human sign-off.

## What was NOT covered

- **Consumer repositories and the `github-build` generator.** Several mitigations above (SHA pinning of
  `ci-actions@v3`, the `actions: read` grant, the skip-flag gating) are only fixable in `github-build`, which
  generates the consumer workflows. Those generator-side changes were not analysed.
- **Runtime GitHub configuration.** Branch protection rules, required status checks, auto-merge settings, tag
  protection, PAT scopes for `GH_PAT`/`GH_BOT_PAT`, and the membership of `@Cloud-Officer/Maintainers` are not in the
  repository and were not inspected. T-01, T-03 and T-04 all depend materially on them.
- **The `cis/` directory** and the `slack/node_modules` tree were not reviewed in depth.
- **Dependency-level CVEs.** No SCA run was performed here; `.soup.json` and `docs/soup.md` hold the SOUP inventory,
  and Trivy/Dependabot cover this ground in CI.
- **`Cloud-Officer/soup` itself** was modelled only as an external dependency (T-07), not audited.

## ISO 27001:2022 mapping

| Control | Coverage | Gaps surfaced |
| :--- | :--- | :--- |
| **A.5.7** Threat intelligence | The dominant threat class for this repository — CI/CD action supply-chain compromise via mutable tags — is a documented, repeatedly-exploited pattern (`tj-actions/changed-files`, March 2025; `reviewdog/action-setup`, same incident chain — and this repository references `reviewdog/action-setup@v1` at `linters/markdownlint/action.yml:59` and `linters/swiftlint/action.yml:53`). T-01 and T-02 are written against that intelligence. | No documented process for tracking action-ecosystem advisories; the weekly bump cron moves refs forward without consulting them. |
| **A.8.8** Management of technical vulnerabilities | Trivy (`linters/trivy`), Semgrep (`linters/semgrep`), Bandit (`linters/bandit`) and Dependabot provide continuous vulnerability management for consumers and for this repo. | T-13: no committed `.github/dependabot.yml`, so ecosystem coverage is unversioned; no `SECURITY.md` disclosure channel. T-04: the scanners are skippable from a commit message. |
| **A.8.25** Secure development lifecycle | This document is the design-phase threat model. `docs/architecture.md` documents components and risk controls; `tests/` holds ten contract suites that block classes of regression; CODEOWNERS enforces review ownership. | T-03: auto-approval means a maintainer PR can reach `master` without a second human reviewer, weakening the review stage of the SDLC. |
| **A.8.27** Secure architecture & engineering principles | Trust boundaries are enumerated above and match `docs/architecture.md`'s component model; least-privilege is applied deliberately in places (the `reviewdog-token` split, step-scoped `COMPOSER_AUTH`, `persist-credentials: false` everywhere). | T-05 and T-06: the org PAT and the ssh-agent are job-scoped rather than step-scoped, so least-privilege stops at the job boundary. T-14: a permission grant that documentation justifies but code does not use. |
| **A.8.28** Secure coding | Strong existing practice: exactly one `${{ }}` interpolation into any `run:` block repo-wide, `env:`-passing enforced by convention and documented in `linters/_lib/require_inputs.sh`; `set -euo pipefail` in every script's `main()`; GPG fingerprint verification in `linters/pmd` and `linters/phpcs` with the rationale recorded in comments. | T-09, T-10, T-12: unverified download, option injection, and TOFU key trust — all inconsistencies with practice the repository already demonstrates elsewhere. |
| **A.8.29** Security testing in development and acceptance | The abuse paths above are directly usable as test cases; `.github/workflows/smoke.yml` already runs eight contract suites plus bats coverage of the shell entry points. | No test asserts security properties specifically: no contract test for "every binary download is verified", "every `apt-get install` uses `--`", or "no external `uses:` is unpinned". Each is mechanically checkable in the existing `tests/` harness. |
| **A.8.32** Change management | CODEOWNERS, PR templates, the smoke/contract gate, and immutable `3.0.x` release tags. | T-01: the `v3` tag consumers actually use is mutable and unprotected. T-03: automated approval on maintainer PRs. |

## Assumptions & out of scope

1. **Branch protection is assumed but unverified.** T-01, T-03 and T-04 assume `master` requires PR review and passing
   status checks. If auto-merge is enabled alongside the auto-approve workflow, T-03 rises to Critical. Confirm before
   sign-off.
2. **`GH_PAT` is assumed to be a long-lived, org-scoped classic PAT**, based on its use for private-submodule checkout
   across repositories. If it is a fine-grained, short-lived, single-repo token, T-05 drops to Medium.
3. **A skipped required check is assumed to satisfy branch protection**, which is GitHub's documented behaviour. If the
   required checks are configured differently, T-04's likelihood drops.
4. **Fork PRs are assumed not to receive secrets**, per GitHub's default for `pull_request`. This is why T-06's
   likelihood is Medium rather than High — it needs a contributor with write access, not an anonymous fork author.
5. **The organisation is assumed to control `Cloud-Officer/soup`** and its tag-push permissions (T-07).
6. No runtime testing, no exploitation, and no changes to any action code were performed. This exercise was read-only
   analysis of the repository at commit `acd94a5`.

## Sign-off

- Modeled by: AI (draft) · Date: 2026-09-07
- Reviewed & accepted by: __________________ (human) · Date: __________
- Risk acceptance decisions recorded for: T-04 (partial — `SKIP_TESTS` previously accepted), T-08 (accept with
  documentation proposed). All other accept/mitigate calls remain open.
