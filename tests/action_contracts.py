#!/usr/bin/env python3
"""Structural contract check for every action.yml in the repository.

This is the safety net for the actions that cannot be invoked end-to-end in
CI without secrets or side effects (setup, aws, docker, codedeploy/*, soup,
slack). It does not run the actions; it asserts each action.yml is a
well-formed GitHub composite/JS/Docker action so a broken YAML, a missing
`shell:` on a `run:` step, or a malformed input block is caught here instead
of in a consumer's pipeline.

Usage: python3 tests/action_contracts.py
Exits non-zero and prints every violation found.
"""

from __future__ import annotations

import sys

import yaml

from _contract_lib import action_paths, fail, load_yaml, report

# node16 is omitted deliberately: GitHub removed it from hosted runners, so an
# action declaring it no longer runs, and this check exists to catch exactly that
# class of breakage before a consumer hits it. node20 is still supported by
# GitHub and stays. QUAL-010.
VALID_USING = {"composite", "docker", "node20", "node24"}


def check_file(path: str) -> list[str]:
    errors: list[str] = []

    def err(msg: str) -> None:
        errors.append(f"{path}: {msg}")

    try:
        data = load_yaml(path)
    except yaml.YAMLError as exc:
        return [f"{path}: invalid YAML: {exc}"]

    if not isinstance(data, dict):
        return [f"{path}: top level must be a mapping"]

    for key in ("name", "description", "runs"):
        if key not in data:
            err(f"missing top-level '{key}'")

    inputs = data.get("inputs")
    if inputs is not None:
        if not isinstance(inputs, dict):
            err("'inputs' must be a mapping")
        else:
            for name, spec in inputs.items():
                if not isinstance(spec, dict) or "description" not in spec:
                    err(f"input '{name}' must be a mapping with a description")

    runs = data.get("runs")
    if not isinstance(runs, dict):
        err("'runs' must be a mapping")
        return errors

    using = runs.get("using")
    if using not in VALID_USING:
        err(f"runs.using '{using}' is not one of {sorted(VALID_USING)}")

    if using == "composite":
        steps = runs.get("steps")
        if not isinstance(steps, list) or not steps:
            err("composite action needs a non-empty runs.steps list")
            return errors
        for index, step in enumerate(steps):
            where = f"step[{index}]"
            if not isinstance(step, dict):
                err(f"{where} must be a mapping")
                continue
            has_run = "run" in step
            has_uses = "uses" in step
            if has_run == has_uses:
                err(f"{where} must have exactly one of 'run' or 'uses'")
            if has_run and "shell" not in step:
                err(f"{where} has 'run' but no 'shell'")

    return errors


def main() -> int:
    paths = action_paths()
    if not paths:
        return fail("no action.yml files found")

    all_errors: list[str] = []
    for path in paths:
        all_errors.extend(check_file(path))

    return report(all_errors, f"Checked {len(paths)} action.yml files, {len(all_errors)} violation(s).")


if __name__ == "__main__":
    sys.exit(main())
