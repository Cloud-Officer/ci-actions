#!/usr/bin/env python3
"""Contract: the Trivy lock-file list lives in exactly one place.

QUAL-010 (#238). The package-manager lock-file list used to be duplicated as
domain knowledge in two files that had to be kept in sync by hand:

  - variables/variables.sh  detect_trivy()  -> enables the TRIVY linter
  - linters/trivy/action.yml                -> adds Trivy's `vuln` scanner

They are now single-sourced from linters/_lib/lock_files.sh. This test enforces
that single-sourcing so the duplication can never silently come back:

  1. linters/_lib/lock_files.sh sources cleanly and defines a non-empty
     TRIVY_LOCK_FILES array.
  2. Each consumer sources lock_files.sh and iterates TRIVY_LOCK_FILES.
  3. No canonical lock-file name is hardcoded in either consumer -- the only
     place those names may appear is lock_files.sh itself. A list that drifts
     (a new ecosystem added to one consumer but not the other) is exactly the
     silent failure this guards against.

Usage: python3 tests/lock_file_contract.py
Exits non-zero and prints every violation found.
"""

from __future__ import annotations

import os
import subprocess
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHARED_LIST = os.path.join("linters", "_lib", "lock_files.sh")
CONSUMERS = (
    os.path.join("variables", "variables.sh"),
    os.path.join("linters", "trivy", "action.yml"),
)


def load_lock_files() -> list[str]:
    """Source the shared list in bash and return the TRIVY_LOCK_FILES entries."""
    result = subprocess.run(
        ["bash", "-c", f'source "{SHARED_LIST}"; printf "%s\\n" "${{TRIVY_LOCK_FILES[@]}}"'],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "failed to source lock_files.sh")
    return [line for line in result.stdout.splitlines() if line]


def main() -> int:
    errors: list[str] = []

    shared_path = os.path.join(REPO_ROOT, SHARED_LIST)
    if not os.path.isfile(shared_path):
        print(f"{SHARED_LIST}: missing shared lock-file list", file=sys.stderr)
        return 1

    try:
        lock_files = load_lock_files()
    except RuntimeError as exc:
        print(f"{SHARED_LIST}: {exc}", file=sys.stderr)
        return 1

    if not lock_files:
        errors.append(f"{SHARED_LIST}: TRIVY_LOCK_FILES is empty")

    for rel in CONSUMERS:
        with open(os.path.join(REPO_ROOT, rel), encoding="utf-8") as handle:
            text = handle.read()

        if "lock_files.sh" not in text:
            errors.append(f"{rel}: does not source linters/_lib/lock_files.sh")
        if "TRIVY_LOCK_FILES" not in text:
            errors.append(f"{rel}: does not reference the TRIVY_LOCK_FILES array")

        # The canonical names must exist ONLY in lock_files.sh. Finding one
        # hardcoded here means the list has been duplicated again.
        for name in lock_files:
            if name in text:
                errors.append(
                    f"{rel}: hardcodes lock-file name '{name}' -- "
                    f"it must come from the shared TRIVY_LOCK_FILES array"
                )

    for line in errors:
        print(line, file=sys.stderr)

    print(
        f"Checked {len(CONSUMERS)} consumer(s) against {len(lock_files)} "
        f"single-sourced lock files, {len(errors)} violation(s)."
    )
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
