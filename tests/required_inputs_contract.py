#!/usr/bin/env python3
r"""Contract: actions whose empty inputs fail silently validate them.

CFG-002. GitHub Actions does not enforce `required: true` for composite or
local actions -- it is documentation only. An unset or misspelled secret
reference such as ${{ secrets.MISNAMED }} interpolates to an empty string with
no warning, so an action that hands that value straight to a nested interpreter
runs nothing and still exits 0. `bash -eo pipefail -c -- ""` exits 0, the step
goes green, and the Slack notification reports a healthy build for work that
never happened.

This pins the guard for the actions where that silence is the failure mode:
each must call the shared linters/_lib/require_inputs.sh gate and name every
input whose emptiness would produce a green no-op.

Actions that fail loudly on their own are deliberately not listed. `docker`
errors on an empty registry password, `setup` errors on an unusable version,
and `slack` validates `webhook-url` and the `jobs` payload in index.js.

Usage: python3 tests/required_inputs_contract.py
Exits non-zero and prints every violation found.
"""

from __future__ import annotations

import os
import sys

import yaml

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GATE = os.path.join("linters", "_lib", "require_inputs.sh")

# action.yml -> the inputs whose emptiness is silent, so must be gated
GUARDED = {
    os.path.join("aws", "action.yml"): {"shell-commands"},
    os.path.join("codedeploy", "deploy", "action.yml"): {
        "application-name",
        "deployment-group-name",
        "s3-bucket",
        "s3-key",
    },
    os.path.join("codedeploy", "s3copy", "action.yml"): {"source", "target"},
}


def validate_step(action):
    """Return the first step that calls the shared gate, or None."""
    for step in (action.get("runs") or {}).get("steps") or []:
        if GATE.replace(os.sep, "/").split("/")[-1] in (step.get("run") or ""):
            return step

    return None


def main() -> int:
    errors: list[str] = []

    if not os.path.isfile(os.path.join(REPO_ROOT, GATE)):
        print(f"{GATE}: missing shared input gate", file=sys.stderr)
        return 1

    for rel, expected in sorted(GUARDED.items()):
        path = os.path.join(REPO_ROOT, rel)

        if not os.path.isfile(path):
            errors.append(f"{rel}: missing")
            continue

        action = yaml.safe_load(open(path, encoding="utf-8"))
        step = validate_step(action)

        if step is None:
            errors.append(f"{rel}: no step calls {GATE}")
            continue

        # The gate must run before anything that could act on an empty value.
        steps = action["runs"]["steps"]

        if steps.index(step) != 0:
            errors.append(f"{rel}: the {GATE} step must be first, found at index {steps.index(step)}")

        run = step.get("run") or ""
        env = step.get("env") or {}

        for name in sorted(expected):
            if f'"{name}=' not in run:
                errors.append(f"{rel}: required input '{name}' is not passed to {GATE}")

        # Values must reach the gate through env:, never interpolated into run:.
        if "${{" in run:
            errors.append(f"{rel}: interpolates an expression into run:; pass values through env: instead")

        for key, value in env.items():
            if "${{ inputs." not in value:
                errors.append(f"{rel}: env {key} is not bound to an action input")

    for error in errors:
        print(error, file=sys.stderr)

    print(f"Checked {len(GUARDED)} action(s) against {GATE}, {len(errors)} violation(s).")

    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
