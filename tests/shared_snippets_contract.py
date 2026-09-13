#!/usr/bin/env python3
"""Contract: the APT install and Composer cache-dir steps live in one place each.

`setup` and `linters/phpstan` used to carry byte-identical copies of both
blocks. They are now single-sourced from linters/_lib/apt_install.sh and
linters/_lib/composer_cache_dir.sh. This test enforces that:

  1. Each helper exists and each consumer action calls it.
  2. No other shell script or action.yml re-implements either block.

Usage: python3 tests/shared_snippets_contract.py
Exits non-zero and prints every violation found.
"""

from __future__ import annotations

import os
import re
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONSUMERS = (
    os.path.join("setup", "action.yml"),
    os.path.join("linters", "phpstan", "action.yml"),
)
HELPERS = {
    os.path.join("linters", "_lib", "apt_install.sh"): re.compile(r"apt-get\b[^\n]*\binstall\b[^\n]*\$\{?APT_PACKAGES"),
    os.path.join("linters", "_lib", "composer_cache_dir.sh"): re.compile(r"composer\s+config\s+cache-files-dir"),
}
SKIP_DIRS = {".git", "node_modules"}


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
    files = scanned_files()

    for helper, pattern in HELPERS.items():
        if not os.path.isfile(os.path.join(REPO_ROOT, helper)):
            errors.append(f"{helper}: missing shared helper")
            continue

        for rel in CONSUMERS:
            if os.path.basename(helper) not in read(rel):
                errors.append(f"{rel}: does not call {helper}")

        for rel in files:
            if rel == helper:
                continue
            for number, line in enumerate(read(rel).splitlines(), start=1):
                if pattern.search(line):
                    errors.append(f"{rel}:{number}: re-implements {helper} -- call the helper instead")

    for message in errors:
        print(message, file=sys.stderr)

    print(f"Checked {len(files)} file(s) against {len(HELPERS)} shared helper(s), {len(errors)} violation(s).")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
