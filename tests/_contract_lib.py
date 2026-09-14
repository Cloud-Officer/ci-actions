"""Shared harness for the tests/*_contract.py scripts.

Each contract script keeps only its domain assertions and imports the plumbing
from here: the repo root, file discovery, YAML loading, composite-step
extraction and the "print violations, print a summary, exit 1 or 0" tail.
"""

from __future__ import annotations

import glob
import os
import sys
from collections.abc import Callable, Iterable

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP_DIRS = frozenset({".git", "node_modules"})


def read(rel: str, root: str = REPO_ROOT) -> str:
    """Return the text of a file given relative to `root`."""
    with open(os.path.join(root, rel), encoding="utf-8") as handle:
        return handle.read()


def load_yaml(rel: str, root: str = REPO_ROOT) -> object:
    """Parse a YAML file given relative to `root`; raises yaml.YAMLError."""
    import yaml

    with open(os.path.join(root, rel), encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def action_paths(pattern: str = os.path.join("**", "action.yml"), root: str = REPO_ROOT) -> list[str]:
    """Return sorted paths relative to `root` matching `pattern`, outside node_modules."""
    return sorted(
        os.path.relpath(path, root)
        for path in glob.glob(os.path.join(root, pattern), recursive=True)
        if "node_modules" not in os.path.relpath(path, root).split(os.sep)
    )


def walk_files(keep: Callable[[str], bool], root: str = REPO_ROOT) -> list[str]:
    """Return sorted paths relative to `root` of every file whose name satisfies `keep`."""
    found = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(name for name in dirnames if name not in SKIP_DIRS)
        found.extend(
            os.path.relpath(os.path.join(dirpath, name), root)
            for name in filenames
            if keep(name)
        )
    return sorted(found)


def is_script_or_action(name: str) -> bool:
    """Match shell scripts and action.yml files."""
    return name.endswith(".sh") or name == "action.yml"


def composite_steps(data: object) -> list[dict]:
    """Return the mapping steps of a parsed composite action, or an empty list."""
    if not isinstance(data, dict):
        return []
    runs = data.get("runs")
    if not isinstance(runs, dict) or runs.get("using") != "composite":
        return []
    steps = runs.get("steps")
    if not isinstance(steps, list):
        return []
    return [step for step in steps if isinstance(step, dict)]


def fail(message: str) -> int:
    """Print a fatal precondition failure to stderr and return exit code 1."""
    print(message, file=sys.stderr)
    return 1


def report(errors: Iterable[str], summary: str | None = None) -> int:
    """Print every violation to stderr, then the summary to stdout; return 1 if any violation."""
    errors = list(errors)
    for line in errors:
        print(line, file=sys.stderr)
    if summary is not None:
        print(summary)
    return 1 if errors else 0
