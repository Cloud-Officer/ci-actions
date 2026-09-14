#!/usr/bin/env python3
"""Self-test for tests/_contract_lib.py, the harness every contract script imports.

Usage: python3 tests/contract_lib_selftest.py
Exits non-zero and prints every failed case.
"""

from __future__ import annotations

import contextlib
import io
import os
import sys
import tempfile

import yaml

from _contract_lib import action_paths, composite_steps, fail, is_script_or_action, load_yaml, report, walk_files


def captured(func, *args):
    """Run func(*args); return (result, stdout, stderr)."""
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        result = func(*args)
    return result, out.getvalue(), err.getvalue()


def touch(root: str, rel: str, text: str = "") -> None:
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


def case_report_with_errors() -> str | None:
    code, out, err = captured(report, ["a: bad", "b: bad"], "Checked 2, 2 violation(s).")
    if (code, out, err) != (1, "Checked 2, 2 violation(s).\n", "a: bad\nb: bad\n"):
        return f"got {(code, out, err)!r}"
    return None


def case_report_clean() -> str | None:
    code, out, err = captured(report, [], "Checked 2, 0 violation(s).")
    if (code, out, err) != (0, "Checked 2, 0 violation(s).\n", ""):
        return f"got {(code, out, err)!r}"
    return None


def case_report_without_summary() -> str | None:
    code, out, err = captured(report, iter(["only: error"]))
    if (code, out, err) != (1, "", "only: error\n"):
        return f"got {(code, out, err)!r}"
    return None


def case_fail() -> str | None:
    code, out, err = captured(fail, "missing thing")
    if (code, out, err) != (1, "", "missing thing\n"):
        return f"got {(code, out, err)!r}"
    return None


def case_composite_steps() -> str | None:
    composite = {"runs": {"using": "composite", "steps": [{"run": "x"}, "bare", {"uses": "y"}]}}
    checks = [
        (composite_steps(composite), [{"run": "x"}, {"uses": "y"}]),
        (composite_steps({"runs": {"using": "node24", "steps": [{"run": "x"}]}}), []),
        (composite_steps({"runs": {"using": "composite", "steps": "nope"}}), []),
        (composite_steps(["not", "a", "mapping"]), []),
    ]
    bad = [(got, want) for got, want in checks if got != want]
    return f"mismatches {bad!r}" if bad else None


def case_action_paths_and_walk_files() -> str | None:
    with tempfile.TemporaryDirectory() as root:
        for rel in ("a/action.yml", "b/c/action.yml", "node_modules/x/action.yml", ".git/hooks/pre.sh", "d/run.sh", "d/notes.md"):
            touch(root, rel)
        problems = []
        if action_paths(root=root) != ["a/action.yml", "b/c/action.yml"]:
            problems.append(f"action_paths: {action_paths(root=root)!r}")
        if action_paths(os.path.join("b", "*", "action.yml"), root) != ["b/c/action.yml"]:
            problems.append(f"action_paths(pattern): {action_paths(os.path.join('b', '*', 'action.yml'), root)!r}")
        if walk_files(is_script_or_action, root) != ["a/action.yml", "b/c/action.yml", "d/run.sh"]:
            problems.append(f"walk_files: {walk_files(is_script_or_action, root)!r}")
        return "; ".join(problems) or None


def case_load_yaml() -> str | None:
    with tempfile.TemporaryDirectory() as root:
        touch(root, "good.yml", "runs: {using: composite}\n")
        touch(root, "broken.yml", "runs: {steps: [\n")
        if load_yaml("good.yml", root) != {"runs": {"using": "composite"}}:
            return "good.yml did not parse"
        try:
            load_yaml("broken.yml", root)
        except yaml.YAMLError as exc:
            return None if "broken.yml" in str(exc) else f"error does not name the file: {exc}"
        return "broken.yml did not raise yaml.YAMLError"


CASES = [
    ("report prints errors to stderr, summary to stdout, returns 1", case_report_with_errors),
    ("report returns 0 and prints only the summary when clean", case_report_clean),
    ("report without a summary prints only errors", case_report_without_summary),
    ("fail prints to stderr and returns 1", case_fail),
    ("composite_steps keeps only mapping steps of composite actions", case_composite_steps),
    ("action_paths and walk_files skip node_modules and .git", case_action_paths_and_walk_files),
    ("load_yaml parses and raises YAMLError naming the file", case_load_yaml),
]


def main() -> int:
    failures = []
    for name, case in CASES:
        problem = case()
        if problem:
            failures.append(f"{name}: {problem}")
    return report(failures, f"Ran {len(CASES)} contract library self-test case(s), {len(failures)} failure(s).")


if __name__ == "__main__":
    sys.exit(main())
