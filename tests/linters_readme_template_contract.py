#!/usr/bin/env python3
"""Contract: the linters/README.md "Common Structure" template is not stale.

CONS-001 (#259). linters/README.md documents a canonical action.yml skeleton
that contributors are told to copy when adding a linter, plus a `sed` recipe
for bulk-updating the checkout action. Both drifted behind the real actions:
PR #200 replaced the inline `grep` gate with the shared
linters/_lib/check_enabled.sh, and PR #248 bumped actions/checkout to v7 --
neither touched this prescriptive doc. A contributor copying the stale block
would reintroduce the un-anchored substring `grep` that check_enabled.sh's
`grep -qwF` deliberately fixed.

This test pins the doc to the actions instead of to a hardcoded version:

  1. All linter actions agree on one actions/checkout version, and every one
     of their `id: check` steps delegates to the shared gate.
  2. The README template block uses the shared gate and that same checkout
     version, and shows no inline `grep` gate.
  3. The README's `sed` bulk-update example rewrites *to* that same version.

Usage: python3 tests/linters_readme_template_contract.py
Exits non-zero and prints every violation found.
"""

from __future__ import annotations

import glob
import os
import re
import sys

import yaml

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
README = os.path.join("linters", "README.md")
SHARED_GATE = "_lib/check_enabled.sh"
# The pre-QUAL-001 inline gate: `if echo "${LINTERS}" | grep NAME ...`.
LEGACY_GATE = re.compile(r'echo\s+"\$\{LINTERS\}"\s*\|\s*grep')
CHECKOUT = re.compile(r"actions[/\\]+checkout@(v\d+)")
# ```yaml ... ``` fenced block, non-greedy.
YAML_FENCE = re.compile(r"```yaml\n(.*?)```", re.DOTALL)
# find ... sed -i '' 's/actions\/checkout@vA/actions\/checkout@vB/g'
SED_BUMP = re.compile(r"s/actions\\?/checkout@(v\d+)/actions\\?/checkout@(v\d+)/")


def check_step_run(text: str) -> str | None:
    """Return the `run:` body of the `id: check` step, or None if absent."""
    try:
        data = yaml.safe_load(text)
    except yaml.YAMLError:
        return None
    if not isinstance(data, dict):
        return None
    runs = data.get("runs")
    steps = runs.get("steps") if isinstance(runs, dict) else None
    if not isinstance(steps, list):
        return None
    for step in steps:
        if isinstance(step, dict) and step.get("id") == "check":
            run = step.get("run")
            return run if isinstance(run, str) else None
    return None


def template_block(readme: str) -> str | None:
    """Return the yaml fence that follows the '### Common Structure' heading."""
    _, _, after = readme.partition("### Common Structure")
    if not after:
        return None
    match = YAML_FENCE.search(after)
    return match.group(1) if match else None


def check_actions(action_paths: list[str], repo_root: str) -> tuple[set[str], list[str]]:
    """Validate the real linter actions; return their checkout versions + errors."""
    errors: list[str] = []
    versions: set[str] = set()

    for path in action_paths:
        rel = os.path.relpath(path, repo_root)
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        versions.update(CHECKOUT.findall(text))
        gate = check_step_run(text)
        if gate is None:
            errors.append(f"{rel}: has no `id: check` step with a `run:` gate")
        elif LEGACY_GATE.search(gate):
            errors.append(f"{rel}: check step still uses the inline grep gate")
        elif SHARED_GATE not in gate:
            errors.append(f"{rel}: check step does not call the shared {SHARED_GATE}")

    return versions, errors


def check_readme(readme: str, current: str) -> list[str]:
    """Validate the documented template and sed recipe against `current`."""
    errors: list[str] = []

    block = template_block(readme)
    if block is None:
        errors.append(f"{README}: no yaml block under '### Common Structure'")
    else:
        gate = check_step_run(block)
        if gate is None:
            errors.append(
                f"{README}: Common Structure template has no parseable "
                f"`id: check` step with a `run:` gate"
            )
        elif LEGACY_GATE.search(gate):
            errors.append(
                f"{README}: Common Structure template still shows the inline "
                f"grep gate removed by QUAL-001"
            )
        elif SHARED_GATE not in gate:
            errors.append(
                f"{README}: Common Structure template does not show the shared "
                f"{SHARED_GATE} gate"
            )

        block_versions = set(CHECKOUT.findall(block))
        if not block_versions:
            errors.append(f"{README}: Common Structure template has no actions/checkout step")
        for stale in sorted(block_versions - {current}):
            errors.append(
                f"{README}: Common Structure template pins actions/checkout@{stale}, "
                f"the linter actions use @{current}"
            )

    bumps = SED_BUMP.findall(readme)
    if not bumps:
        errors.append(f"{README}: no actions/checkout sed bulk-update example found")
    for source, target in bumps:
        if target != current:
            errors.append(
                f"{README}: sed example bumps checkout {source} -> {target}, "
                f"the linter actions use @{current}"
            )

    return errors


def main(repo_root: str = REPO_ROOT) -> int:
    action_paths = sorted(glob.glob(os.path.join(repo_root, "linters", "*", "action.yml")))
    if not action_paths:
        print("no linter action.yml files found", file=sys.stderr)
        return 1

    # 1. The actions are the source of truth -- they must be self-consistent.
    versions, errors = check_actions(action_paths, repo_root)

    if len(versions) != 1:
        errors.append(
            f"linters/*/action.yml: expected one actions/checkout version, "
            f"found {sorted(versions) or ['none']}"
        )
        for line in errors:
            print(line, file=sys.stderr)
        return 1

    current = versions.pop()

    # 2 + 3. The documented template and sed recipe must match the actions.
    readme_path = os.path.join(repo_root, README)
    try:
        with open(readme_path, encoding="utf-8") as handle:
            readme = handle.read()
    except OSError as exc:
        print(f"{README}: cannot read ({exc})", file=sys.stderr)
        return 1

    errors.extend(check_readme(readme, current))

    for line in errors:
        print(line, file=sys.stderr)

    print(
        f"Checked {README} against {len(action_paths)} linter action(s) "
        f"(actions/checkout@{current}), {len(errors)} violation(s)."
    )
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
