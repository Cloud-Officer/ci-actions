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

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HELPER = os.path.join("linters", "_lib", "submodule_paths.sh")
CONSUMERS = (
    os.path.join("variables", "variables.sh"),
    os.path.join("linters", "_lib", "detect_trivy_scanners.sh"),
    os.path.join("linters", "_lib", "clean_workspace.sh"),
)
SKIP_DIRS = {".git", "node_modules"}
PARSE = re.compile(r"(\b(grep|sed|awk)\b[^\n]*\.gitmodules|--file[ =]\.gitmodules)")


def scanned_files() -> list[str]:
    """Return every shell script and action.yml relative to the repo root."""
    found = []
    for dirpath, dirnames, filenames in os.walk(REPO_ROOT):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
        for name in filenames:
            if name.endswith(".sh") or name == "action.yml":
                found.append(os.path.relpath(os.path.join(dirpath, name), REPO_ROOT))
    return sorted(found)


def read(rel: str) -> str:
    with open(os.path.join(REPO_ROOT, rel), encoding="utf-8") as handle:
        return handle.read()


def main() -> int:
    errors: list[str] = []

    if not os.path.isfile(os.path.join(REPO_ROOT, HELPER)):
        print(f"{HELPER}: missing shared .gitmodules parser", file=sys.stderr)
        return 1

    for rel in CONSUMERS:
        text = read(rel)
        if "submodule_paths.sh" not in text:
            errors.append(f"{rel}: does not source {HELPER}")
        if "< <(submodule_paths)" not in text:
            errors.append(f"{rel}: does not read paths from submodule_paths")

    files = scanned_files()
    for rel in files:
        if rel == HELPER:
            continue
        for number, line in enumerate(read(rel).splitlines(), start=1):
            if PARSE.search(line):
                errors.append(f"{rel}:{number}: parses .gitmodules directly -- use submodule_paths from {HELPER}")

    for message in errors:
        print(message, file=sys.stderr)

    print(f"Checked {len(files)} file(s) and {len(CONSUMERS)} consumer(s), {len(errors)} violation(s).")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
