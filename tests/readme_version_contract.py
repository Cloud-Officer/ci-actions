#!/usr/bin/env python3
"""Contract: every README references the current ci-actions major version.

The root README.md is the source of truth for the current major: the highest
`Cloud-Officer/ci-actions/<path>@vN` it references. Every other README.md in
the repository must reference that same major in its `uses:` examples, so a
major roll cannot leave per-action pages telling consumers to pin the previous
line. Upgrade notes that legitimately mention older majors live in
UPGRADING.md, which this contract does not scan.

Usage: python3 tests/readme_version_contract.py
Exits non-zero and prints every violation found.
"""

from __future__ import annotations

import os
import re
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT_README = "README.md"
SKIP_DIRS = {".git", "node_modules"}
REF = re.compile(r"cloud-officer/ci-actions/[A-Za-z0-9_./-]+@v(\d+)\b", re.IGNORECASE)


def majors(text: str) -> list[tuple[int, int]]:
    """Return (line number, major) for every versioned ci-actions reference."""
    return [
        (text.count("\n", 0, match.start()) + 1, int(match.group(1)))
        for match in REF.finditer(text)
    ]


def readmes() -> list[str]:
    """Return every README.md path relative to the repo root, root README excluded."""
    found = []
    for dirpath, dirnames, filenames in os.walk(REPO_ROOT):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
        if "README.md" in filenames:
            rel = os.path.relpath(os.path.join(dirpath, "README.md"), REPO_ROOT)
            if rel != ROOT_README:
                found.append(rel)
    return sorted(found)


def read(rel: str) -> str:
    with open(os.path.join(REPO_ROOT, rel), encoding="utf-8") as handle:
        return handle.read()


def main() -> int:
    root_refs = majors(read(ROOT_README))
    if not root_refs:
        print(f"{ROOT_README}: no Cloud-Officer/ci-actions/<path>@vN reference to derive the current major from", file=sys.stderr)
        return 1
    current = max(major for _, major in root_refs)

    errors: list[str] = []
    for line, major in root_refs:
        if major != current:
            errors.append(f"{ROOT_README}:{line}: references @v{major}, expected @v{current}")

    paths = readmes()
    for rel in paths:
        for line, major in majors(read(rel)):
            if major != current:
                errors.append(f"{rel}:{line}: references @v{major}, expected @v{current}")

    for message in errors:
        print(message, file=sys.stderr)

    print(f"Checked {len(paths) + 1} README(s) against current major v{current}, {len(errors)} violation(s).")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
