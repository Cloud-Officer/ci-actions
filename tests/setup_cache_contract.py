#!/usr/bin/env python3
"""Contract: `setup` sets up only the languages a job asks for, and caches each thing once.

  1. Version-file auto-detection is opt-in: the detect step runs only when
     `detect-version-files` is 'true', and that input defaults to 'false'.
  2. Every step gated on a detected version file is also gated on the
     language's explicit `<language>-version` input, and on
     `<language>-version-file` when the action declares one.
  3. pip is cached once, by actions/setup-python: no actions/cache step
     caches the pip directory.
  4. Node packages are cached by the explicit actions/cache step, not also
     by actions/setup-node, and an empty miss is pruned before the save.
  5. apt packages go through the cache-key helper, an actions/cache step and
     apt_install.sh with APT_CACHE_DIR bound to that cache directory.

Usage: python3 tests/setup_cache_contract.py
Exits non-zero and prints every violation found.
"""

from __future__ import annotations

import os
import re
import sys

from _contract_lib import composite_steps, load_yaml, report

SETUP = os.path.join("setup", "action.yml")
DETECT_ID = "detect-versions"
DETECTED = re.compile(r"steps\.detect-versions\.outputs\.(?P<lang>[a-z]+)-file")


def compact(value: object) -> str:
    return str(value or "").replace(" ", "")


def uses(step: dict, action: str) -> bool:
    return str(step.get("uses", "")).split("@")[0] == action


def check_detection(inputs: dict, steps: list[dict]) -> list[str]:
    errors: list[str] = []

    if str((inputs.get("detect-version-files") or {}).get("default")) != "false":
        errors.append(f"{SETUP}: input 'detect-version-files' must default to 'false'")

    detect = [step for step in steps if step.get("id") == DETECT_ID]
    if len(detect) != 1:
        errors.append(f"{SETUP}: expected one '{DETECT_ID}' step, found {len(detect)}")
    elif compact(detect[0].get("if")) != "${{inputs.detect-version-files=='true'}}":
        errors.append(f"{SETUP}: the '{DETECT_ID}' step must run only when detect-version-files is 'true'")

    for step in steps:
        condition = compact(step.get("if"))
        for lang in sorted({match.group("lang") for match in DETECTED.finditer(condition)}):
            name = step.get("name", step.get("id", "?"))
            if f"inputs.{lang}-version!='none'" not in condition:
                errors.append(f"{SETUP}: step '{name}' runs on a detected .{lang} file without inputs.{lang}-version")
            if f"{lang}-version-file" in inputs and f"inputs.{lang}-version-file!=''" not in condition:
                errors.append(f"{SETUP}: step '{name}' ignores an explicit {lang}-version-file input")

    return errors


def check_pip(steps: list[dict]) -> list[str]:
    errors: list[str] = []

    for step in steps:
        if uses(step, "actions/cache") and "pip" in compact((step.get("with") or {}).get("key")):
            errors.append(f"{SETUP}: step '{step.get('name')}' caches pip again - actions/setup-python already does")

    python = [step for step in steps if uses(step, "actions/setup-python")]
    if len(python) != 1 or compact((python[0].get("with") or {}).get("cache")) != "${{inputs.python-cache}}":
        errors.append(f"{SETUP}: actions/setup-python must cache with inputs.python-cache")

    return errors


def check_node(steps: list[dict]) -> list[str]:
    errors: list[str] = []
    node = [step for step in steps if uses(step, "actions/setup-node")]

    if len(node) != 1:
        return [f"{SETUP}: expected one actions/setup-node step, found {len(node)}"]

    with_ = node[0].get("with") or {}
    if "cache" in with_ or str(with_.get("package-manager-cache")).lower() != "false":
        errors.append(f"{SETUP}: actions/setup-node must not cache (no 'cache', package-manager-cache: false)")

    ids = [step.get("id") for step in steps]
    for step_id in ("node-cache-dir", "node-cache"):
        if step_id not in ids:
            errors.append(f"{SETUP}: missing step '{step_id}'")

    prune = [step for step in steps if "prune_empty_cache_dir.sh" in str(step.get("run", ""))]
    if len(prune) != 1:
        errors.append(f"{SETUP}: expected one step running prune_empty_cache_dir.sh, found {len(prune)}")
    elif "node-cache" in ids and ids.index("node-cache") > steps.index(prune[0]):
        errors.append(f"{SETUP}: the empty Node cache must be pruned after the cache restore")
    elif "steps.node-cache.outputs.cache-hit!='true'" not in compact(prune[0].get("if")):
        errors.append(f"{SETUP}: the Node cache prune must run only on a cache miss")

    return errors


def check_apt(steps: list[dict]) -> list[str]:
    errors: list[str] = []
    ids = [step.get("id") for step in steps]

    if "apt-cache-key" not in ids:
        return [f"{SETUP}: missing step 'apt-cache-key'"]

    key_step = steps[ids.index("apt-cache-key")]
    if "apt_cache_key.sh" not in str(key_step.get("run", "")):
        errors.append(f"{SETUP}: step 'apt-cache-key' must run apt_cache_key.sh")

    caches = [
        step for step in steps
        if uses(step, "actions/cache")
        and compact((step.get("with") or {}).get("key")) == "${{steps.apt-cache-key.outputs.key}}"
    ]
    if len(caches) != 1 or compact(caches[0]["with"].get("path")) != "${{steps.apt-cache-key.outputs.dir}}":
        errors.append(f"{SETUP}: expected one actions/cache step on the apt-cache-key dir and key")

    installs = [step for step in steps if "_lib/apt_install.sh" in str(step.get("run", ""))]
    if len(installs) != 1:
        errors.append(f"{SETUP}: expected one step running apt_install.sh, found {len(installs)}")
    elif compact((installs[0].get("env") or {}).get("APT_CACHE_DIR")) != "${{steps.apt-cache-key.outputs.dir}}":
        errors.append(f"{SETUP}: apt_install.sh must get APT_CACHE_DIR from the apt-cache-key step")
    elif caches and steps.index(caches[0]) > steps.index(installs[0]):
        errors.append(f"{SETUP}: the apt cache must be restored before apt_install.sh runs")

    return errors


def main() -> int:
    data = load_yaml(SETUP)
    inputs = data.get("inputs") or {}
    steps = composite_steps(data)
    errors = check_detection(inputs, steps) + check_pip(steps) + check_node(steps) + check_apt(steps)
    return report(errors, f"Checked {SETUP} ({len(steps)} steps), {len(errors)} violation(s).")


if __name__ == "__main__":
    sys.exit(main())
