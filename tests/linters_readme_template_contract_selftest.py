#!/usr/bin/env python3
"""Self-test for tests/linters_readme_template_contract.py (CONS-001, #259).

The contract test only ever runs against the real repo, where -- once the
drift is fixed -- it passes. That proves nothing about its ability to *catch*
the next drift. This self-test points it at synthetic repo fixtures and
asserts it reports the expected violation for each way the doc can go stale,
so the guard cannot silently rot into a no-op.

Usage: python3 tests/linters_readme_template_contract_selftest.py
Exits non-zero and prints every failed case.
"""

from __future__ import annotations

import contextlib
import io
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import linters_readme_template_contract as contract  # noqa: E402

SHARED_GATE_RUN = 'bash "${GITHUB_ACTION_PATH}/../_lib/check_enabled.sh" ACTIONLINT'
LEGACY_GATE_RUN = (
    'if echo "${LINTERS}" | grep ACTIONLINT &> /dev/null; '
    'then echo "continue=true" >> "${GITHUB_OUTPUT}"; '
    'else echo "continue=false" >> "${GITHUB_OUTPUT}"; fi'
)


def action_yml(gate_run: str = SHARED_GATE_RUN, checkout: str = "v7") -> str:
    return f"""---
name: 'Actionlint'
description: 'Execute actionlint'

runs:
  using: "composite"
  steps:
    - id: check
      shell: bash
      run: {gate_run}

    - name: Checkout
      uses: actions/checkout@{checkout}
"""


def readme(
    gate_run: str = SHARED_GATE_RUN,
    checkout: str = "v7",
    sed_from: str = "v6",
    sed_to: str = "v7",
    heading: str = "### Common Structure",
    template: str | None = None,
    include_sed: bool = True,
) -> str:
    if template is None:
        template = f"""---
name: 'LinterName'
description: 'Execute lintername'

runs:
  using: "composite"
  steps:
    - id: check
      shell: bash
      run: {gate_run}

    - name: Checkout
      uses: actions/checkout@{checkout}
"""
    recipe = ""
    if include_sed:
        recipe = (
            "\n**Tip:** Use find and sed for bulk updates:\n\n"
            "```bash\n"
            "find linters -name \"action.yml\" -exec sed -i '' "
            f"'s/actions\\/checkout@{sed_from}/actions\\/checkout@{sed_to}/g' {{}} \\;\n"
            "```\n"
        )
    return f"""# Linter GitHub Actions

{heading}

```yaml
{template}```
{recipe}"""


def build(root: str, actions: dict[str, str], readme_text: str | None) -> None:
    for name, text in actions.items():
        directory = os.path.join(root, "linters", name)
        os.makedirs(directory, exist_ok=True)
        with open(os.path.join(directory, "action.yml"), "w", encoding="utf-8") as handle:
            handle.write(text)
    if readme_text is not None:
        os.makedirs(os.path.join(root, "linters"), exist_ok=True)
        with open(os.path.join(root, contract.README), "w", encoding="utf-8") as handle:
            handle.write(readme_text)


def run(actions: dict[str, str], readme_text: str | None) -> tuple[int, str]:
    """Run the contract against a fixture repo; return (exit code, output)."""
    with tempfile.TemporaryDirectory() as root:
        build(root, actions, readme_text)
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer), contextlib.redirect_stderr(buffer):
            code = contract.main(root)
        return code, buffer.getvalue()


GOOD_ACTIONS = {"actionlint": action_yml(), "bandit": action_yml()}

# (case name, actions, readme, expected exit code, expected substring)
CASES: list[tuple[str, dict[str, str], str | None, int, str]] = [
    (
        "clean repo passes",
        GOOD_ACTIONS,
        readme(),
        0,
        "0 violation(s).",
    ),
    (
        "no linter actions at all",
        {},
        readme(),
        1,
        "no linter action.yml files found",
    ),
    (
        "actions disagree on checkout version",
        {"actionlint": action_yml(), "bandit": action_yml(checkout="v6")},
        readme(),
        1,
        "expected one actions/checkout version",
    ),
    (
        "action check step bypasses the shared gate",
        {"actionlint": action_yml(gate_run="echo hi"), "bandit": action_yml()},
        readme(),
        1,
        "check step does not call the shared",
    ),
    (
        "action check step still inlines the grep gate",
        {"actionlint": action_yml(gate_run=LEGACY_GATE_RUN), "bandit": action_yml()},
        readme(),
        1,
        "check step still uses the inline grep gate",
    ),
    (
        "action has no check step",
        {
            "actionlint": (
                "---\nname: x\ndescription: x\nruns:\n  using: composite\n"
                "  steps:\n    - name: Checkout\n      uses: actions/checkout@v7\n"
            ),
            "bandit": action_yml(),
        },
        readme(),
        1,
        "has no `id: check` step",
    ),
    (
        "README missing entirely",
        GOOD_ACTIONS,
        None,
        1,
        "cannot read",
    ),
    (
        "README has no Common Structure heading",
        GOOD_ACTIONS,
        readme(heading="### Something Else"),
        1,
        "no yaml block under",
    ),
    (
        "template block is not parseable YAML",
        GOOD_ACTIONS,
        readme(template="runs: [unclosed\n"),
        1,
        "no parseable",
    ),
    (
        "template block is YAML but not a mapping",
        GOOD_ACTIONS,
        readme(template="- not\n- a mapping\n"),
        1,
        "no parseable",
    ),
    (
        "template block has runs but no steps list",
        GOOD_ACTIONS,
        readme(template="---\nruns:\n  using: composite\n"),
        1,
        "no parseable",
    ),
    (
        "template shows the pre-QUAL-001 inline gate",
        GOOD_ACTIONS,
        readme(gate_run=LEGACY_GATE_RUN),
        1,
        "still shows the inline",
    ),
    (
        "template gate is neither shared nor legacy",
        GOOD_ACTIONS,
        readme(gate_run="echo hi"),
        1,
        "does not show the shared",
    ),
    (
        "template has no checkout step",
        GOOD_ACTIONS,
        readme(
            template=(
                "---\nruns:\n  using: composite\n  steps:\n    - id: check\n"
                f"      shell: bash\n      run: {SHARED_GATE_RUN}\n"
            )
        ),
        1,
        "has no actions/checkout step",
    ),
    (
        "template pins a stale checkout version",
        GOOD_ACTIONS,
        readme(checkout="v6"),
        1,
        "pins actions/checkout@v6",
    ),
    (
        "sed recipe bumps to a stale version",
        GOOD_ACTIONS,
        readme(sed_from="v5", sed_to="v6"),
        1,
        "sed example bumps checkout v5 -> v6",
    ),
    (
        "sed recipe is missing",
        GOOD_ACTIONS,
        readme(include_sed=False),
        1,
        "no actions/checkout sed bulk-update example found",
    ),
]


def main() -> int:
    failures: list[str] = []

    for name, actions, readme_text, want_code, want_text in CASES:
        code, output = run(actions, readme_text)
        if code != want_code:
            failures.append(f"{name}: expected exit {want_code}, got {code}\n{output}")
        elif want_text not in output:
            failures.append(f"{name}: expected {want_text!r} in output, got:\n{output}")

    for line in failures:
        print(line, file=sys.stderr)

    print(f"Ran {len(CASES)} contract self-test case(s), {len(failures)} failure(s).")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
