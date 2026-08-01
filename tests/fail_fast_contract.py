#!/usr/bin/env python3
"""Contract: user-supplied command strings run with fail-fast semantics.

BUG-003 (#257). Several actions hand a user-supplied, possibly multi-line
command string to a nested interpreter:

  - aws/action.yml                (shell-commands)
  - linters/phpcs/action.yml      (composer-command, php-cs-fixer-command)
  - linters/phpstan/action.yml    (composer-command, php-stan-command)

A composite step's own `shell: bash` options are NOT inherited by that nested
`bash -c`, so a bare `bash -c -- "${CMDS}"` reports only the LAST command's
exit status: `false\\ntrue` exits 0 and the CI step goes green while an
intermediate command failed. Every such call site must therefore carry `-e`
and `-o pipefail` itself.

This test enforces both halves of that:

  1. Static: no action.yml may invoke `bash ... -c` without `-e` and
     `-o pipefail` in the options preceding `-c`.
  2. Behavioural: the hardened prefix really does fail fast on this bash
     (early failure, failing pipe stage) and still succeeds for well-formed
     input, while the bare form swallows the failure -- the exact regression.

Usage: python3 tests/fail_fast_contract.py
Exits non-zero and prints every violation found.
"""

from __future__ import annotations

import glob
import os
import re
import subprocess
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# A `bash <opts> -c` invocation on a single line. The options are captured
# non-greedily so `opts` is everything between `bash` and the first ` -c`.
BASH_C = re.compile(r"\bbash\b(?P<opts>[^\n]*?)\s-c\b")


def missing_flags(opts: str) -> list[str]:
    """Return the fail-fast flags absent from a `bash ... -c` option string."""
    tokens = opts.split()
    # `-e` may be bundled with other short flags, e.g. `-eo pipefail`. Long
    # options (`--norc`) never carry it.
    has_errexit = any(
        token.startswith("-")
        and not token.startswith("--")
        and "e" in token[1:]
        for token in tokens
    )
    missing: list[str] = []
    if not has_errexit:
        missing.append("-e")
    if "pipefail" not in tokens:
        missing.append("-o pipefail")
    return missing


def scan_text(path: str, text: str) -> list[str]:
    """Report every non-fail-fast `bash ... -c` call site in one file."""
    errors: list[str] = []
    for lineno, line in enumerate(text.splitlines(), start=1):
        match = BASH_C.search(line)
        if match is None:
            continue
        missing = missing_flags(match.group("opts"))
        if missing:
            errors.append(
                f"{path}:{lineno}: nested 'bash -c' is missing "
                f"{' and '.join(missing)} -- only the last command's exit "
                f"status would be reported: {line.strip()}"
            )
    return errors


def run_snippet(argv: list[str]) -> int:
    """Run a bash invocation and return its exit status."""
    return subprocess.run(
        argv,
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    ).returncode


HARDENED = ["bash", "-eo", "pipefail", "-c", "--"]
BARE = ["bash", "-c", "--"]

# (argv, must_succeed, what it proves)
BEHAVIOUR_CASES = (
    (HARDENED + ["false\ntrue"], False, "an early failure must fail the whole script (errexit)"),
    (HARDENED + ["false | true"], False, "a failing pipe stage must fail the script (pipefail)"),
    (HARDENED + ["true\ntrue"], True, "well-formed input still succeeds (behaviour-preserving)"),
    # The bare form is what the fix replaces. If this ever stops succeeding the
    # bug guarded against no longer exists and this contract can be revisited.
    (BARE + ["false\ntrue"], True, "the bare form swallows the failure -- the BUG-003 regression"),
)


def check_behaviour() -> list[str]:
    """Assert `bash -eo pipefail -c --` actually fails fast on this bash."""
    errors: list[str] = []
    for argv, must_succeed, why in BEHAVIOUR_CASES:
        succeeded = run_snippet(argv) == 0
        if succeeded != must_succeed:
            errors.append(
                f"behaviour check failed: {' '.join(argv[:-1])} "
                f"{argv[-1]!r} {'failed' if must_succeed else 'exited 0'} -- {why}"
            )
    return errors


def check_detector() -> list[str]:
    """Self-check: the scanner flags the bug and accepts the fix."""
    errors: list[str] = []
    cases = (
        ('run: bash -eo pipefail -c -- "${CMDS}"', 0),
        ('run: bash -c -- "${CMDS}"', 1),
        ('run: bash -e -c -- "${CMDS}"', 1),          # errexit only, no pipefail
        ('run: bash -o pipefail -c -- "${CMDS}"', 1),  # pipefail only, no errexit
        ('shell: bash', 0),                            # not an interpreter call
        ('run: bash "${GITHUB_ACTION_PATH}/deploy.sh"', 0),
    )
    for line, expected in cases:
        found = len(scan_text("<self-check>", line))
        if found != expected:
            errors.append(
                f"detector self-check failed for {line!r}: "
                f"expected {expected} finding(s), got {found}"
            )
    return errors


def main() -> int:
    paths = sorted(
        path for path in glob.glob("**/action.yml", recursive=True)
        if "node_modules/" not in path
    )
    if not paths:
        print("no action.yml files found", file=sys.stderr)
        return 1

    errors = check_detector() + check_behaviour()
    for path in paths:
        with open(path, encoding="utf-8") as handle:
            errors.extend(scan_text(path, handle.read()))

    for line in errors:
        print(line, file=sys.stderr)

    print(f"Checked {len(paths)} action.yml files for fail-fast "
          f"'bash -c' call sites, {len(errors)} violation(s).")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
