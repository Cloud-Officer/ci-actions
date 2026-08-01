#!/usr/bin/env python3
"""Contract: toolchain setup and package installs stay authenticated.

CONS-006 (#264). Every action in this repository that downloads a toolchain or
installs a package from the network authenticates with the caller's token, so a
consumer running under GitHub API rate pressure is never throttled by an
anonymous download. `linters/bandit/action.yml` was the single exception -- its
`actions/setup-python` step passed no `token:` and its pip install ran without
`GITHUB_TOKEN` -- while every other linter and `setup/action.yml` passed one.

Three checks, applied to every `action.yml` in the repository:

  1. Every step using a token-accepting toolchain setup action
     (actions/setup-python, setup-node, setup-java, setup-go) passes a
     `token:` wired to one of the action's own inputs. ruby/setup-ruby and
     shivammathur/setup-php are excluded: neither declares a `token` input.
  2. Every `run:` step that installs with a language package manager
     (pip/pipx/npm/yarn/pnpm/gem) exports `GITHUB_TOKEN`.
  3. `linters/bandit/action.yml` mirrors `linters/semgrep/action.yml`: both
     are "setup-python then pip install then run" linters with no reviewdog
     step, so their token wiring must match step kind for step kind. This is
     the regression guard for the drift CONS-006 found.

Usage: python3 tests/token_contract.py [repo_root]
Exits non-zero and prints every violation found.
"""

from __future__ import annotations

import glob
import os
import re
import sys

import yaml

# Setup actions that accept a `token` input. ruby/setup-ruby and
# shivammathur/setup-php are deliberately absent: they have no such input.
TOKEN_AWARE_SETUP_ACTIONS = (
    "actions/setup-go",
    "actions/setup-java",
    "actions/setup-node",
    "actions/setup-python",
)

# Language package managers whose installs hit an authenticated-friendly API.
PACKAGE_INSTALL_RE = re.compile(
    r"(?<![\w/-])(pip3?|pipx|npm|yarn|pnpm|gem)\s+install\b"
)

INPUT_EXPR_RE = re.compile(r"\$\{\{\s*inputs\.[\w-]*token[\w-]*\s*\}\}")

MIRROR_PAIR = (
    os.path.join("linters", "bandit", "action.yml"),
    os.path.join("linters", "semgrep", "action.yml"),
)


def composite_steps(data: object) -> list[dict]:
    """Return the composite steps of a parsed action, or an empty list."""
    if not isinstance(data, dict):
        return []
    runs = data.get("runs")
    if not isinstance(runs, dict) or runs.get("using") != "composite":
        return []
    steps = runs.get("steps")
    if not isinstance(steps, list):
        return []
    return [step for step in steps if isinstance(step, dict)]


def step_label(step: dict, index: int) -> str:
    return f"step[{index}] {step.get('name') or step.get('id') or '<unnamed>'}"


def check_file(rel: str, data: object) -> list[str]:
    errors: list[str] = []

    for index, step in enumerate(composite_steps(data)):
        where = f"{rel}: {step_label(step, index)}"
        uses = step.get("uses")

        if isinstance(uses, str) and uses.split("@")[0] in TOKEN_AWARE_SETUP_ACTIONS:
            token = (step.get("with") or {}).get("token")
            if not isinstance(token, str) or not INPUT_EXPR_RE.search(token):
                errors.append(
                    f"{where} uses '{uses}' without "
                    f"token: ${{{{ inputs.<...>token }}}}"
                )

        run = step.get("run")
        if isinstance(run, str) and PACKAGE_INSTALL_RE.search(run):
            env = step.get("env")
            if not isinstance(env, dict) or "GITHUB_TOKEN" not in env:
                errors.append(
                    f"{where} installs a package without a GITHUB_TOKEN env"
                )

    return errors


def token_shape(steps: list[dict]) -> list[tuple[str, bool]]:
    """Reduce steps to (kind, carries-a-token) so two actions can be compared."""
    shape: list[tuple[str, bool]] = []
    for step in steps:
        env = step.get("env") if isinstance(step.get("env"), dict) else {}
        if isinstance(step.get("uses"), str):
            with_block = step.get("with") if isinstance(step.get("with"), dict) else {}
            kind = str(step["uses"]).split("@")[0]
            has_token = "token" in with_block or "GITHUB_TOKEN" in env
        else:
            kind = "run"
            has_token = "GITHUB_TOKEN" in env
        shape.append((kind, has_token))
    return shape


def check_mirror(actions: dict[str, object]) -> list[str]:
    left, right = MIRROR_PAIR
    missing = [rel for rel in MIRROR_PAIR if rel not in actions]
    if missing:
        return [f"{rel}: missing, cannot compare token wiring" for rel in missing]

    left_shape = token_shape(composite_steps(actions[left]))
    right_shape = token_shape(composite_steps(actions[right]))

    if len(left_shape) != len(right_shape):
        return [
            f"{left}: has {len(left_shape)} steps but {right} has "
            f"{len(right_shape)} -- the two pip-installed Python linters must "
            f"stay structurally identical"
        ]

    errors: list[str] = []
    for index, (mine, theirs) in enumerate(zip(left_shape, right_shape)):
        if mine[0] != theirs[0]:
            errors.append(
                f"{left}: step[{index}] is '{mine[0]}' but {right} "
                f"step[{index}] is '{theirs[0]}'"
            )
        elif mine[1] != theirs[1]:
            errors.append(
                f"{left}: step[{index}] ('{mine[0]}') "
                f"{'carries' if mine[1] else 'does not carry'} a token but "
                f"{right} step[{index}] "
                f"{'does' if theirs[1] else 'does not'}"
            )
    return errors


def main(argv: list[str]) -> int:
    root = argv[1] if len(argv) > 1 else os.path.dirname(
        os.path.dirname(os.path.abspath(__file__))
    )

    paths = sorted(
        p for p in glob.glob(os.path.join(root, "**", "action.yml"), recursive=True)
        if "node_modules/" not in p
    )
    if not paths:
        print(f"no action.yml files found under {root}", file=sys.stderr)
        return 1

    actions: dict[str, object] = {}
    errors: list[str] = []

    for path in paths:
        rel = os.path.relpath(path, root)
        try:
            with open(path, encoding="utf-8") as handle:
                data = yaml.safe_load(handle)
        except yaml.YAMLError as exc:
            errors.append(f"{rel}: invalid YAML: {exc}")
            continue
        actions[rel] = data
        errors.extend(check_file(rel, data))

    errors.extend(check_mirror(actions))

    for line in errors:
        print(line, file=sys.stderr)

    print(f"Checked {len(paths)} action.yml files, {len(errors)} violation(s).")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
