#!/usr/bin/env python3
"""Contract: .gitmodules is parsed in exactly one place.

linters/_lib/submodule_paths.sh reads submodule paths with
`git config --file .gitmodules --get-regexp`, which matches real
`submodule.<name>.path` keys whatever their spacing. This test enforces that:

  1. Every consumer sources submodule_paths.sh and calls submodule_paths.
  2. No other shell script or action.yml parses .gitmodules itself, with
     grep/sed/awk or with its own `git config --file .gitmodules`.

Usage: python3 tests/submodule_paths_contract.py
Exits non-zero and prints every violation found.
"""

from __future__ import annotations

import os
import re
import sys

from _contract_lib import REPO_ROOT, fail, is_script_or_action, read, report, walk_files

HELPER = os.path.join("linters", "_lib", "submodule_paths.sh")
CONSUMERS = (
    os.path.join("variables", "variables.sh"),
    os.path.join("linters", "_lib", "detect_trivy_scanners.sh"),
    os.path.join("linters", "_lib", "clean_workspace.sh"),
)
PARSE = re.compile(r"(\b(grep|sed|awk)\b[^\n]*\.gitmodules|--file[ =]\.gitmodules)")


def main() -> int:
    errors: list[str] = []

    if not os.path.isfile(os.path.join(REPO_ROOT, HELPER)):
        return fail(f"{HELPER}: missing shared .gitmodules parser")

    for rel in CONSUMERS:
        text = read(rel)
        if "submodule_paths.sh" not in text:
            errors.append(f"{rel}: does not source {HELPER}")
        if "< <(submodule_paths)" not in text:
            errors.append(f"{rel}: does not read paths from submodule_paths")

    files = walk_files(is_script_or_action)
    for rel in files:
        if rel == HELPER:
            continue
        for number, line in enumerate(read(rel).splitlines(), start=1):
            if PARSE.search(line):
                errors.append(f"{rel}:{number}: parses .gitmodules directly -- use submodule_paths from {HELPER}")

    return report(errors, f"Checked {len(files)} file(s) and {len(CONSUMERS)} consumer(s), {len(errors)} violation(s).")


if __name__ == "__main__":
    sys.exit(main())
