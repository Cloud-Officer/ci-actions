# Ownership Map & Bus Factor — cloud-officer/ci-actions

**Date:** 2026-09-07
**Window:** full history (2022-03-22 → 2026-09-04, 518 commits), weighted to the last 12 months
**Thresholds:** bus factor at >50% of current lines; knowledge silo at a single owner >75%
**Method:** `git blame` line ownership on the default branch (`master`) + commit recency. Blame ≠ understanding — see Caveats.

## Headline risks

- **Repo bus factor: 1.** One contributor holds 13,633 of 14,406 current lines (**94.6%**).
- **Sensitive files with bus factor 1: 33 of 33 examined** (every CI/CD workflow, every deploy
  and credential-handling action, every security-scanner gate and its suppression file).
- **Bus factor 1 repo-wide:** 107 of 107 non-empty tracked files. **99 files are 100% single-owner.**
- **CODEOWNERS drift: structural, not per-file.** `.github/CODEOWNERS` points every path at
  `@Cloud-Officer/Maintainers`; that team resolves to two accounts — `ydesgagn` and the
  `cloudofficer-admin` service account — so the declared review path contains **one human**.
- **Stale sensitive code: 0.** Every tracked file was modified within the last 9 months; the most
  recent sensitive change is 2026-09-04. Staleness is not a risk here — concentration is.

This repository is consumed by downstream repos as `cloud-officer/ci-actions@v3`, so the
concentration below is a **supply-chain** risk, not just a maintenance one: the same single
owner authors the deploy actions, the security-scanner gates, and the ignore files that
suppress those scanners' findings.

## Contributors (identities folded)

| Contributor | Current lines | Share | Commits | Last commit | Active? |
| --- | --- | --- | --- | --- | --- |
| Yves Desgagné | 13,633 | 94.6% | 476 | 2026-09-04 | yes |
| Tommy Lacroix | 772 | 5.4% | 30 | 2026-03-20 | yes (low: 6 commits/12mo) |
| Martin Poirier Théorêt | 1 | <0.1% | 1 | 2022-04-14 | no |
| Francis Lacroix | 0 | 0% | 2 | 2022-06-01 | no |
| dependabot[bot] | 0 | 0% | 9 | 2025-09-15 | bot |

No `.mailmap` exists. Four alias merges were applied by hand and are the only identity
folding performed:

- `Yves Desgagné <yves@cloudofficer.ca>` + `Yves Desgagne <yves@cloudofficer.ca>` (accent dropped)
- The same author name stored in two Unicode normalisations (NFC and NFD), which `git blame`
  reports as two distinct authors. Unfolded, this inflates the apparent owner count on 8 files;
  every figure in this report uses the folded value.
- `Tommy Lacroix <tommy@nuagelab.com>` + `Tommy Lacroix <tlacroix@nuagelab.com>`

## Risk matrix

Change frequency is commits in the trailing 12 months: **high** ≥ 20, **medium** 5–19, **low** < 5.

| File / module | Change freq | Top owner (%) | Bus factor | Sensitive? | Risk |
| --- | --- | --- | --- | --- | --- |
| `.github/` (workflows, CODEOWNERS) | high (63) | Yves 98% | 1 | yes | critical |
| `codedeploy/` | high (36) | Yves 100% | 1 | yes | critical |
| `aws/` | medium (11) | Yves 100% | 1 | yes | critical |
| `(root)` (`.soup.json`, `.trivyignore`, `.semgrepignore`, `.bandit`, `trivy.yaml`) | high (85) | Yves 100% | 1 | yes | high |
| `linters/` (47 files, 19 linter actions + `_lib`) | high (254) | Yves ~100% | 1 | yes | high |
| `variables/` | high (39) | Yves 82% | 1 | yes | high |
| `setup/` | high (23) | Yves ~100% | 1 | yes | high |
| `docker/` | medium (9) | Yves 100% | 1 | yes | high |
| `soup/` | medium (16) | Yves 99% | 1 | yes | medium |
| `bump-actions/` | medium (6) | Yves 100% | 1 | yes | medium |
| `tests/` (9 contract tests) | medium (11) | Yves 100% | 1 | no | medium |
| `slack/` | high (27) | Yves 58% | 1 | no | medium |
| `docs/` (`architecture.md`, `soup.md`) | high (62) | Yves 100% | 1 | no | low |

`slack/` is the only module where a second contributor holds a meaningful share
(Tommy Lacroix, 502 lines / 42%), and the only module whose bus factor is even close to 2.

## Single points of failure (bus factor 1 on sensitive code)

All 33 files below are owned by **Yves Desgagné** (active), so the "Owner active?" column
is `yes` throughout and is omitted. Ranked by consequence, not by ownership share.

| File | Owner (%) | Last changed | Why it matters |
| --- | --- | --- | --- |
| `aws/action.yml` | 100% | 2026-08-31 | Takes `aws-access-key-id`, `aws-secret-access-key`, `ssh-key`; runs arbitrary `shell-commands` |
| `codedeploy/deploy/action.yml` | 100% | 2026-08-31 | Production deploy path for every consumer repo |
| `codedeploy/deploy/deploy.sh` | 100% | 2026-05-18 | Deploy logic; 1 commit ever — written once, never reviewed by a second author |
| `codedeploy/s3copy/action.yml` | 100% | 2026-08-31 | Writes deploy artifacts to S3 |
| `codedeploy/checkout/action.yml` | 100% | 2026-06-22 | Checkout with `GH_PAT`-class token |
| `docker/action.yml` | 100% | 2026-06-22 | Image build/push with registry credentials |
| `.github/workflows/auto-approve.yml` | 100% | 2026-09-04 | **Grants PR approvals automatically**; see segregation-of-duties note below |
| `.github/workflows/build.yml` | 94% | 2026-09-04 | Release/tag pipeline; only file with a second owner (Tommy, 15 lines) |
| `.github/workflows/external-actions-bump.yml` | 100% | 2026-08-30 | Pushes to the repo using `GH_PAT` over an `x-access-token` URL |
| `.github/workflows/smoke.yml` | 100% | 2026-08-31 | The only end-to-end verification of all 28 actions |
| `.github/CODEOWNERS` | 100% | 2026-05-19 | Defines the review path — authored by the person it names |
| `setup/action.yml` | ~100% | 2026-08-31 | 940 lines; toolchain bootstrap for every job, largest single file |
| `variables/variables.sh` | 100% | 2026-08-30 | Computes the variables every downstream workflow branches on |
| `variables/action.yml` | 100% | 2026-08-30 | Wrapper for the above |
| `bump-actions/bump-actions.sh` | 100% | 2026-08-30 | Rewrites external action references across repos — supply-chain pin control |
| `linters/_lib/check_enabled.sh` | 100% | 2026-05-22 | Single gate that can turn **any** linter off |
| `linters/_lib/recv_gpg_key.sh` | 100% | 2026-08-31 | GPG key import over keyservers (trust anchor for pmd/phpcs) |
| `linters/_lib/lock_files.sh` | 100% | 2026-06-13 | 1 commit ever |
| `linters/_lib/require_inputs.sh` | 100% | 2026-08-31 | 1 commit ever; the fail-loud guard for unset secrets |
| `linters/_lib/clean_workspace.sh` | 100% | 2026-08-30 | Workspace teardown between jobs |
| `linters/_lib/install_swiftlint.sh` | 100% | 2026-08-01 | 1 commit ever; downloads and installs a toolchain |
| `linters/trivy/action.yml` | 100% | 2026-08-31 | IaC/dependency security scanning |
| `linters/semgrep/action.yml` | 100% | 2026-07-26 | SAST |
| `linters/bandit/action.yml` | 100% | 2026-08-01 | Python security scanning |
| `.trivyignore` | 100% | 2026-09-04 | **Suppresses** Trivy findings |
| `.semgrepignore` | 100% | 2026-06-03 | **Suppresses** Semgrep findings |
| `.bandit` | 100% | 2026-06-02 | **Suppresses** Bandit findings |
| `.soup.json` | 100% | 2026-09-04 | SOUP inventory — compliance evidence |
| `soup/action.yml` | 99% | 2026-08-31 | Generates that evidence |
| `slack/action.yml` | 100% | 2026-02-23 | Notification path with webhook token |
| `slack/index.js` | 98% | 2026-08-30 | Bundled to `slack/dist/index.js`; the only shipped JS |
| `tests/action_contracts.py` | 100% | 2026-08-31 | Validates all 28 `action.yml` — the safety net itself |
| `tests/token_contract.py` | 100% | 2026-08-01 | 1 commit ever; asserts token handling |

Five of these files have **exactly one commit in their entire history**:
`codedeploy/deploy/deploy.sh`, `linters/_lib/lock_files.sh`, `linters/_lib/require_inputs.sh`,
`linters/_lib/install_swiftlint.sh`, and `tests/token_contract.py`. Repo-wide, 16 tracked files
are one-commit files (the rest are test and template files). A file written in one commit by
one author has had no second pair of eyes on it at any point, review process notwithstanding.

## CODEOWNERS drift

There is **no per-file drift** — `.github/CODEOWNERS` maps every path to the same team, and
the actual blame owner is inside that team. The drift is structural.

| File | Declared owner | Actual owner | Note |
| --- | --- | --- | --- |
| `*` (catch-all) | `@Cloud-Officer/Maintainers` | Yves Desgagné (94.6%) | Team = `ydesgagn` + `cloudofficer-admin` (service account). One human. |
| `codedeploy/`, `*.sh`, `.github/`, 8 dotfiles | `@Cloud-Officer/Maintainers` | Yves Desgagné (100%) | Redundant: identical to the `*` line, so they add no differentiation |
| `linters/`, `aws/`, `docker/`, `setup/`, `slack/`, `soup/`, `variables/`, `tests/` | `*` catch-all only | Yves Desgagné | The highest-churn module (`linters/`, 254 commits/12mo) has no explicit owner entry |
| — | — | Tommy Lacroix (5.4%) | The only other human with surviving code is **not** in the Maintainers team |

`.github/workflows/auto-approve.yml` auto-approves any PR whose author is in the catch-all
CODEOWNERS team. It does guard against literal self-approval (`APPROVER = AUTHOR` → skip),
but the approver is the `GH_BOT_PAT` service account, so a PR from the sole human maintainer
is approved by a bot the same maintainer controls. Read plainly: **the repo's approval control
is satisfiable by one person.** That is the A.5.3 finding, and it compounds the bus factor —
the same individual is the sole author, the sole code owner, and the effective approver.

## Stale sensitive code

**None.** Every tracked file was modified within the last 9 months (oldest sensitive touch:
`slack/action.yml`, 2026-02-23). The owner of every sensitive file is active. Recorded here as
a real zero, not a skipped check.

## Co-change clusters (pairs co-occurring in ≥ 5 commits, last 12 months)

| Cluster (files) | Owners | Note |
| --- | --- | --- |
| `.soup.json` ↔ `docs/soup.md` (23) | Yves only | SOUP inventory and its rendered doc move together — expected, but both single-owned |
| `slack/package-lock.json` ↔ `.soup.json` (21), `docs/soup.md` (21), `.github/workflows/build.yml` (16), `docs/architecture.md` (11) | Yves only | The lockfile is the SOUP source of truth, so every dependency bump ripples into compliance evidence and CI. Hidden coupling between a dependency file and three unrelated-looking documents |
| `.github/workflows/build.yml` ↔ `docs/architecture.md` (8) | Yves + Tommy / Yves | Architecture doc is kept in step with the pipeline by hand |
| `variables/tests/variables.bats` ↔ `variables/variables.sh` (7) | Yves + Tommy / Yves | Healthy: the one place where code and test co-change with two contributors present |
| `docs/architecture.md` ↔ `variables/variables.sh` (5), `README.md` (5), `docs/soup.md` (5), `.soup.json` (5) | Yves only | `docs/architecture.md` is a coupling hub — it changes with nearly everything |
| `.github/workflows/build.yml` ↔ `docs/soup.md` (5), `.soup.json` (5), `.gitignore` (5) | Yves only | — |

No cluster spans two different *owners* — because there is effectively one owner. The clusters
are still useful: they show that a `slack/` dependency bump silently obligates edits to
compliance evidence, and that knowledge of that obligation lives in one head.

## Recommended actions (cultural, not just tooling)

Ordered by how much risk each removes per unit of effort.

1. **Close the approval loop first.** Add at least one more human to
   `@Cloud-Officer/Maintainers`, or exclude the `.github/workflows/`, `codedeploy/`, and
   `aws/` paths from `auto-approve.yml` so credential- and deploy-touching changes always take
   a second human. This is the cheapest fix and the one an ISO auditor will look for.
2. **Pair on the seven one-commit files.** `deploy.sh`, `require_inputs.sh`,
   `install_swiftlint.sh`, `lock_files.sh`, and `token_contract.py` have never been read by a
   second author. A single walkthrough session each converts "unknown" into "shared".
3. **Rotate `linters/` review to Tommy Lacroix.** He already contributes (6 commits/12mo) and
   owns 42% of `slack/`. `linters/` is the highest-churn module and the lowest-blast-radius
   place to build a second reviewer's context.
4. **Document the suppression files.** `.trivyignore`, `.semgrepignore`, and `.bandit` decide
   what security findings are ignored, and are 100% single-owned with no rationale recorded
   in-repo. Require a comment naming the CVE/rule and the reason for each entry, so the
   *decisions* survive independently of the person who made them.
5. **Write down the lockfile → SOUP → docs obligation.** The co-change data shows
   `slack/package-lock.json` drags `.soup.json` and `docs/soup.md` with it 21 times in a year.
   That rule is currently tacit; put it in `CONTRIBUTING` or enforce it in `smoke.yml`.
6. **Aim for knowledge overlap, not role duplication.** The goal is not a second maintainer who
   does the same work — it is a second person who could safely make an emergency change to
   `aws/action.yml` or `codedeploy/deploy/` under time pressure.
7. **Raise contract-test coverage on the credential paths.** `tests/token_contract.py` is the
   right idea; extending it means the code documents its own invariants and a newcomer can
   change `aws/action.yml` with a net underneath.

## ISO 27001 mapping

- **A.5.3 Segregation of duties** — Gap. The sole author of the deploy and credential-handling
  actions is also the sole member of the code-owner team and the effective approver of his own
  pull requests (via a bot PAT he controls). Recommendation 1 is the remediation.
- **A.8.25 / A.8.27 Secure development** — The security-scanner actions and their suppression
  files are single-owned, so both the control and the exception to the control are set by one
  person with no independent review.
- **Clause 7.2 Competence and awareness** — This document is the record of where critical
  knowledge is concentrated (94.6% in one contributor) and of the plan to spread it
  (recommendations 2, 3, 6).
- **Risk register entry** — "Bus factor 1 on CI/CD supply-chain actions consumed by all
  downstream repositories" is a documented operational risk with the mitigations above.

## Caveats & method

- **`git blame` shows who last touched a line, not who understands it best.** Knowledge spreads
  through pairing, review, and documentation that git cannot see. Every number here is a
  conversation starter, not a verdict on any individual.
- **Risk, not blame.** Concentration is an organizational property. A 94.6% share reflects who
  was available to do the work, not a failure by the person who did it.
- **Thresholds are defaults**: bus factor at >50% of current lines, silo at >75%. Both are
  configurable conventions, not truth.
- **Identity folding was manual** (no `.mailmap`): four merges, listed in the Contributors
  section. The Unicode NFC/NFD split is worth fixing with a real `.mailmap` — unfolded, it makes
  ownership look more distributed than it is.
- **Scope:** all 126 tracked files on `master`; 107 were analysed for line ownership.
  **Excluded as vendored/generated:** `slack/dist/` (ncc bundle), `slack/package-lock.json`,
  `.idea/` (IDE config), `LICENSE`, `cis/PolicyBanner.rtf` (binary resource) — 15 files.
- **Four tracked files have zero lines** and no blame output: `.shellcheckrc`,
  `bump-actions/.bats`, `codedeploy/.bats`, `variables/.bats`. These are empty marker files
  owned by the `github-build` generator; they carry no knowledge risk.
- **Untracked paths were not analysed.** `docs/threat-model.md` is present but untracked, so git
  history cannot answer for it; it is skipped and noted here rather than silently included.
- **Several workflow files are generated**, not hand-written: `.github/workflows/auto-approve.yml`
  and `build.yml` carry an `AUTO-GENERATED by github-build` banner. Their blame attributes the
  *generator's* output to whoever ran it — the real ownership of that logic lives in the
  `github-build` repository and is outside this analysis. `smoke.yml` is hand-maintained.
- **No prior `docs/ownership-map.md` existed**; this is the first run. The clone is full, not
  shallow or grafted, and every git command exited cleanly.
