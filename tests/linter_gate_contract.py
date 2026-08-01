#!/usr/bin/env python3
"""Contract: every linter step runs only when that linter is enabled.

QUAL-003 (#261). Each linter composite action opens with a `check` step that
sources `linters/_lib/check_enabled.sh` and publishes
`steps.check.outputs.continue`. Every later step must carry that gate in its
`if:` so nothing at all happens when the linter is not in LINTERS.

`linters/phpstan/action.yml` broke the pattern: its Setup SSH Agent step was
gated only on `inputs.ssh-key != ''`, so the ssh-agent started and loaded the
consumer's deploy key even on jobs where PHPStan was disabled. That is a
credential-hygiene problem and it is invisible to `action_contracts.py` --
the YAML is perfectly well formed. This test asserts the gating instead:

  1. Every linter action's first step is the shared enabled check (`id: check`).
  2. Every other step's `if:` contains the `continue == 'true'` gate. Extra
     conditions may be ANDed on (e.g. `inputs.ssh-key != '' && <gate>`), but
     the gate itself is never optional.

`self_check()` runs first, over synthetic fixtures, so a detector that has
stopped detecting anything cannot report a clean scan.

Usage: python3 tests/linter_gate_contract.py
Exits non-zero and prints every violation found.
"""

from __future__ import annotations

import glob
import os
import sys
import tempfile

import yaml

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LINTERS_GLOB = os.path.join("linters", "*", "action.yml")
CHECK_STEP_ID = "check"
GATE = "steps.check.outputs.continue == 'true'"


def check_file(path: str, root: str = REPO_ROOT) -> list[str]:
    """Return every gating violation found in one linter action.yml."""
    errors: list[str] = []

    def err(msg: str) -> None:
        errors.append(f"{path}: {msg}")

    try:
        with open(os.path.join(root, path), encoding="utf-8") as handle:
            data = yaml.safe_load(handle)
    except yaml.YAMLError as exc:
        return [f"{path}: invalid YAML: {exc}"]

    steps = data.get("runs", {}).get("steps") if isinstance(data, dict) else None
    if not isinstance(steps, list) or not steps:
        return [f"{path}: composite action needs a non-empty runs.steps list"]

    first = steps[0]
    if not isinstance(first, dict) or first.get("id") != CHECK_STEP_ID:
        err(f"step[0] must be the shared enabled check (id: {CHECK_STEP_ID})")

    for index, step in enumerate(steps[1:], start=1):
        if not isinstance(step, dict):
            err(f"step[{index}] must be a mapping")
            continue
        condition = str(step.get("if", ""))
        if GATE not in condition:
            err(
                f"step[{index}] '{step.get('name', '?')}' is not gated on "
                f"`{GATE}` (if: {condition!r})"
            )

    return errors


# name -> (yaml source, substring that must appear in the reported violation)
FIXTURES = {
    "gated.yml": (
        """
        runs:
          steps:
            - {id: check, run: 'check_enabled.sh PHPSTAN', shell: bash}
            - name: Setup SSH Agent
              if: "${{ inputs.ssh-key != '' && steps.check.outputs.continue == 'true' }}"
              uses: webfactory/ssh-agent@v0.10.0
        """,
        None,
    ),
    "ungated.yml": (
        """
        runs:
          steps:
            - {id: check, run: 'check_enabled.sh PHPSTAN', shell: bash}
            - name: Setup SSH Agent
              if: "${{ inputs.ssh-key != '' }}"
              uses: webfactory/ssh-agent@v0.10.0
        """,
        "is not gated on",
    ),
    "no_condition.yml": (
        """
        runs:
          steps:
            - {id: check, run: 'check_enabled.sh PHPSTAN', shell: bash}
            - {name: Run PHPStan, run: phpstan, shell: bash}
        """,
        "is not gated on",
    ),
    "no_check_step.yml": (
        """
        runs:
          steps:
            - {name: Checkout, uses: actions/checkout@v7}
        """,
        "must be the shared enabled check",
    ),
    "empty_steps.yml": ("runs: {steps: []}", "non-empty runs.steps list"),
    "not_a_mapping.yml": ("- just a list", "non-empty runs.steps list"),
    "step_not_a_mapping.yml": (
        """
        runs:
          steps:
            - {id: check, run: 'check_enabled.sh PHPSTAN', shell: bash}
            - a bare string
        """,
        "must be a mapping",
    ),
    "broken.yml": ("runs: {steps: [", "invalid YAML"),
}


def self_check() -> list[str]:
    """Assert the detector flags known-bad shapes and passes a known-good one."""
    errors: list[str] = []
    with tempfile.TemporaryDirectory() as root:
        for name, (source, expected) in FIXTURES.items():
            with open(os.path.join(root, name), "w", encoding="utf-8") as handle:
                handle.write(source)
            found = check_file(name, root=root)
            if expected is None:
                if found:
                    errors.append(f"self-check: {name} should be clean, got {found}")
            elif not any(expected in line for line in found):
                errors.append(
                    f"self-check: {name} should report {expected!r}, got {found}"
                )
    return errors


def main() -> int:
    all_errors = self_check()

    paths = sorted(
        os.path.relpath(p, REPO_ROOT)
        for p in glob.glob(os.path.join(REPO_ROOT, LINTERS_GLOB))
    )
    if not paths:
        print("no linter action.yml files found", file=sys.stderr)
        return 1

    for path in paths:
        all_errors.extend(check_file(path))

    for line in all_errors:
        print(line, file=sys.stderr)

    print(
        f"Checked {len(paths)} linter action.yml files and "
        f"{len(FIXTURES)} self-check fixtures, {len(all_errors)} violation(s)."
    )
    return 1 if all_errors else 0


if __name__ == "__main__":
    sys.exit(main())
