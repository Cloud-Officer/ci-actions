#!/usr/bin/env python3
"""Contract check for the hand-maintained linters-smoke disabled-path job.

The `linters-smoke` job in `.github/workflows/smoke.yml` invokes every linter
action with an empty `linters` list and asserts nothing downstream runs. That
promise only holds while EVERY step of every linter action is inert on the
disabled path -- either because it is gated on the shared QUAL-001 output
`steps.check.outputs.continue == 'true'`, or because one of the inputs the
smoke job pins (`ssh-key: ''`, phpstan's `apt-packages`/`php-version`) makes
its own `if:` condition false.

That pairing has drifted silently before: COM-001 (issue #260) found smoke.yml
still claiming phpstan's apt/composer steps ran "independently of the
linter-enabled gate" long after PR #216 added the continue gate to both. This
check pins the invariant so the workflow comment and the actions cannot get
out of sync again.

It also asserts the job covers all of `linters/*/action.yml` and that every
input it pins is actually declared by the action it is passed to.

Usage: python3 tests/smoke_contract.py
Exits non-zero and prints every violation found.
"""

from __future__ import annotations

import glob
import os
import re
import sys

import yaml

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORKFLOW = ".github/workflows/smoke.yml"
JOB = "linters-smoke"
CONTINUE_GATE = "steps.check.outputs.continue == 'true'"
GATE_STEP_ID = "check"

# `inputs.<name> <op> '<literal>'`, the only comparison shape the linter
# actions use in their `if:` conditions.
COMPARISON = re.compile(
    r"^inputs\.(?P<name>[A-Za-z0-9_-]+)\s*(?P<op>==|!=)\s*'(?P<value>[^']*)'$"
)


def unwrap(condition: str) -> str:
    """Strip the `${{ ... }}` wrapper from a workflow expression."""
    text = condition.strip()
    if text.startswith("${{") and text.endswith("}}"):
        text = text[3:-2]
    return text.strip()


def conjunct_is_false(term: str, pinned: dict[str, str]) -> bool:
    """True when `term` is guaranteed false on the disabled path.

    `pinned` holds the inputs the smoke job passes to this action. Unknown or
    unpinned inputs are treated as "could be true" so the check stays
    conservative and only ever reports a real gap.
    """
    if term == CONTINUE_GATE:
        # The disabled path is exactly the case where the gate is false.
        return True
    match = COMPARISON.match(term)
    if not match:
        return False
    name = match.group("name")
    if name not in pinned:
        return False
    actual = pinned[name]
    expected = match.group("value")
    if match.group("op") == "==":
        return actual != expected
    return actual == expected


def step_is_inert(step: dict, pinned: dict[str, str]) -> tuple[bool, str]:
    """Return (inert, reason-if-not) for one action step on the disabled path."""
    condition = step.get("if")
    if condition is None:
        return False, "has no `if:` condition, so it always runs"
    text = unwrap(str(condition))
    if "||" in text or "(" in text:
        # Not worth a general expression evaluator; the actions only ever use
        # flat `&&` chains. Fail loudly rather than silently passing.
        return False, f"uses an unsupported `if:` expression: {text!r}"
    terms = [term.strip() for term in text.split("&&")]
    if any(conjunct_is_false(term, pinned) for term in terms):
        return True, ""
    return False, (
        f"`if: {text}` is not falsified by the smoke job's pins "
        f"({pinned or 'none'}) and does not require `{CONTINUE_GATE}`"
    )


def load_yaml(rel: str):
    with open(os.path.join(REPO_ROOT, rel), encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def collect_invocations(job: dict) -> dict[str, dict[str, str]]:
    """Map `linters/<name>` -> the inputs the smoke job pins for it."""
    invocations: dict[str, dict[str, str]] = {}
    for step in job.get("steps", []):
        uses = str(step.get("uses", ""))
        if not uses.startswith("./linters/"):
            continue
        path = uses[2:].rstrip("/")
        with_block = step.get("with") or {}
        invocations[path] = {key: str(value) for key, value in with_block.items()}
    return invocations


def main() -> int:
    errors: list[str] = []

    workflow = load_yaml(WORKFLOW)
    job = workflow.get("jobs", {}).get(JOB)
    if not isinstance(job, dict):
        print(f"{WORKFLOW}: missing job '{JOB}'", file=sys.stderr)
        return 1

    invocations = collect_invocations(job)

    available = sorted(
        os.path.dirname(p)
        for p in glob.glob("linters/*/action.yml", root_dir=REPO_ROOT)
    )
    for path in available:
        if path not in invocations:
            errors.append(
                f"{WORKFLOW}: job '{JOB}' does not exercise ./{path} -- every "
                f"linter action must be covered by the disabled path"
            )

    for path in sorted(invocations):
        pinned = invocations[path]
        action_rel = f"{path}/action.yml"
        if not os.path.exists(os.path.join(REPO_ROOT, action_rel)):
            errors.append(f"{WORKFLOW}: job '{JOB}' uses ./{path} but it has no action.yml")
            continue

        if pinned.get("linters") != "":
            errors.append(
                f"{WORKFLOW}: ./{path} must be invoked with `linters: ''` so the "
                f"shared gate resolves to continue=false, got {pinned.get('linters')!r}"
            )

        action = load_yaml(action_rel)
        declared = set((action.get("inputs") or {}).keys())
        for name in sorted(pinned):
            if name not in declared:
                errors.append(
                    f"{WORKFLOW}: ./{path} is pinned with input '{name}', which "
                    f"{action_rel} does not declare"
                )

        for index, step in enumerate(action.get("runs", {}).get("steps", [])):
            if step.get("id") == GATE_STEP_ID:
                continue  # the gate itself is meant to run on the disabled path
            inert, reason = step_is_inert(step, pinned)
            if not inert:
                name = step.get("name", f"step[{index}]")
                errors.append(f"{action_rel}: step '{name}' {reason}")

    for line in errors:
        print(line, file=sys.stderr)

    print(
        f"Checked {len(invocations)} linter invocation(s) in {WORKFLOW} job "
        f"'{JOB}', {len(errors)} violation(s)."
    )
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
