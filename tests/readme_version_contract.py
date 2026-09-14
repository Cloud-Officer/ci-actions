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

import re
import sys

from _contract_lib import fail, read, report, walk_files

ROOT_README = "README.md"
REF = re.compile(r"cloud-officer/ci-actions/[A-Za-z0-9_./-]+@v(\d+)\b", re.IGNORECASE)


def majors(text: str) -> list[tuple[int, int]]:
    """Return (line number, major) for every versioned ci-actions reference."""
    return [
        (text.count("\n", 0, match.start()) + 1, int(match.group(1)))
        for match in REF.finditer(text)
    ]


def main() -> int:
    root_refs = majors(read(ROOT_README))
    if not root_refs:
        return fail(f"{ROOT_README}: no Cloud-Officer/ci-actions/<path>@vN reference to derive the current major from")
    current = max(major for _, major in root_refs)

    errors: list[str] = []
    for line, major in root_refs:
        if major != current:
            errors.append(f"{ROOT_README}:{line}: references @v{major}, expected @v{current}")

    paths = [rel for rel in walk_files(lambda name: name == "README.md") if rel != ROOT_README]
    for rel in paths:
        for line, major in majors(read(rel)):
            if major != current:
                errors.append(f"{rel}:{line}: references @v{major}, expected @v{current}")

    return report(errors, f"Checked {len(paths) + 1} README(s) against current major v{current}, {len(errors)} violation(s).")


if __name__ == "__main__":
    sys.exit(main())
