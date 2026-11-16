#!/usr/bin/env python3
"""Contract: every action this repository uses is allowed in the consumer organizations.

GitHub resolves every `uses:` of a composite action when the job starts, even
for steps whose `if:` skips them, and a consumer organization that restricts
actions fails the whole job when one of them is not on its allowlist.
`gradle/actions/setup-gradle` in setup broke every innodem-neurosciences job
that way, including jobs that never set up Java.

Allowed: actions created by GitHub (`actions/*`, `github/*`), this repository
(local paths and `cloud-officer/*`), and the third-party patterns the most
restrictive consumer organization allows.

Usage: python3 tests/allowed_actions_contract.py [repo_root]
Exits non-zero and prints every violation found.
"""

from __future__ import annotations

import fnmatch
import sys

from _contract_lib import REPO_ROOT, action_paths, composite_steps, load_yaml, report

GITHUB_OWNERS = ("actions", "github", "cloud-officer")

ALLOWED_PATTERNS = (
    "ScaCap/*",
    "ScottBrenner/*",
    "amyu/setup-android@*",
    "ankane/setup-opensearch@*",
    "aquasecurity/*",
    "aws-actions/*",
    "docker/*",
    "maxim-lobanov/*",
    "namoshek/*",
    "reviewdog/*",
    "ruby/*",
    "shivammathur/*",
    "shogo82148/*",
    "supercharge/*",
    "webfactory/*",
)


def allowed(ref: str) -> bool:
    if ref.startswith("./") or ref.startswith("docker://"):
        return True
    owner = ref.split("/", 1)[0]
    if owner.lower() in GITHUB_OWNERS:
        return True
    return any(fnmatch.fnmatchcase(ref, pattern) for pattern in ALLOWED_PATTERNS)


def main() -> int:
    root = sys.argv[1] if len(sys.argv) > 1 else REPO_ROOT
    errors: list[str] = []
    paths = [path for path in action_paths(root=root) if ".claude" not in path.split("/")]
    for path in paths:
        for step in composite_steps(load_yaml(path, root)):
            ref = str(step.get("uses") or "")
            if ref and not allowed(ref):
                errors.append(f"{path}: step '{step.get('name')}' uses {ref}, which consumer organizations do not allow")
    return report(errors, f"Checked {len(paths)} action.yml file(s), {len(errors)} violation(s).")


if __name__ == "__main__":
    sys.exit(main())
