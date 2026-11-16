#!/usr/bin/env python3
"""Contract: `setup` sets up only the languages a job asks for, and caches each thing once.

  1. Version-file auto-detection can be turned off: the detect step runs only
     when `detect-version-files` is 'true', and that input defaults to 'true'
     so v3 consumers that rely on version files keep working.
  2. Every step gated on a detected version file is also gated on the
     language's explicit `<language>-version` input, and on
     `<language>-version-file` when the action declares one.
  3. pip is cached once, by actions/setup-python: no actions/cache step
     caches the pip directory.
  4. Node packages are cached by the explicit actions/cache step, not also
     by actions/setup-node, and an empty miss is pruned before the save.
  5. apt packages go through the cache-key helper, an actions/cache step and
     apt_install.sh with APT_CACHE_DIR bound to that cache directory.
  6. Gradle is cached once, by gradle/actions/setup-gradle, only when the job
     asks for it or the repository has Gradle build files; actions/setup-java
     never caches Gradle and no actions/cache step caches ~/.gradle.
  7. The Maven repository is restored by actions/cache only when a pom.xml
     exists, and not when `java-cache: maven` already has setup-java cache it.
  8. The opt-in Python virtualenv is keyed on the exact Python version and
     the dependency files, restored without restore-keys and activated after
     the restore.
  9. The Python interpreter is restored from the python-tool-cache helper's
     path and key by an actions/cache step that runs before actions/setup-python.

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

    if str((inputs.get("detect-version-files") or {}).get("default")) != "true":
        errors.append(f"{SETUP}: input 'detect-version-files' must default to 'true'")

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


def check_java(steps: list[dict]) -> list[str]:
    errors: list[str] = []
    java_gate = "inputs.java-version!='none'||inputs.java-version-file!=''||steps.detect-versions.outputs.java-file"

    java = [step for step in steps if uses(step, "actions/setup-java")]
    if len(java) != 1 or compact((java[0].get("with") or {}).get("cache")) != (
        "${{inputs.java-cache!='gradle'&&inputs.java-cache||''}}"
    ):
        errors.append(f"{SETUP}: actions/setup-java must not cache Gradle (setup-gradle does)")

    for step in steps:
        if uses(step, "actions/cache") and ".gradle" in compact((step.get("with") or {}).get("path")):
            errors.append(f"{SETUP}: step '{step.get('name')}' caches ~/.gradle - gradle/actions/setup-gradle does")

    gradle = [step for step in steps if uses(step, "gradle/actions/setup-gradle")]
    if len(gradle) != 1:
        errors.append(f"{SETUP}: expected one gradle/actions/setup-gradle step, found {len(gradle)}")
    else:
        condition = compact(gradle[0].get("if"))
        for part in (java_gate, "inputs.java-cache=='gradle'", "hashFiles('**/*.gradle*','**/gradle-wrapper.properties')!=''"):
            if part not in condition:
                errors.append(f"{SETUP}: setup-gradle condition is missing {part}")

    maven = [
        step for step in steps
        if uses(step, "actions/cache") and compact((step.get("with") or {}).get("path")) == "~/.m2/repository"
    ]
    if len(maven) != 1:
        errors.append(f"{SETUP}: expected one actions/cache step on ~/.m2/repository, found {len(maven)}")
    else:
        condition = compact(maven[0].get("if"))
        for part in (java_gate, "inputs.java-cache!='maven'", "hashFiles('**/pom.xml')!=''"):
            if part not in condition:
                errors.append(f"{SETUP}: Maven cache condition is missing {part}")

    return errors


def check_python_venv(inputs: dict, outputs: dict, steps: list[dict]) -> list[str]:
    errors: list[str] = []
    ids = [step.get("id") for step in steps]

    if str((inputs.get("python-venv-cache") or {}).get("default")) != "false":
        errors.append(f"{SETUP}: input 'python-venv-cache' must default to 'false'")

    for step_id in ("setup-python", "python-venv-key", "python-venv-cache"):
        if step_id not in ids:
            errors.append(f"{SETUP}: missing step '{step_id}'")
    if errors:
        return errors

    key_step = steps[ids.index("python-venv-key")]
    key_env = {name: compact(value) for name, value in (key_step.get("env") or {}).items()}
    if "python_venv_cache_key.sh" not in str(key_step.get("run", "")):
        errors.append(f"{SETUP}: step 'python-venv-key' must run python_venv_cache_key.sh")
    if "inputs.python-venv-cache=='true'" not in compact(key_step.get("if")):
        errors.append(f"{SETUP}: step 'python-venv-key' must run only when python-venv-cache is 'true'")
    if key_env.get("PYTHON_VERSION") != "${{steps.setup-python.outputs.python-version}}":
        errors.append(f"{SETUP}: the venv key must use the exact Python version actions/setup-python resolved")
    dependency_hash = key_env.get("DEPENDENCY_HASH", "")
    for pattern in ("hashFiles(inputs.python-cache-dependency-path)", "'**/*requirements*.txt'", "'**/pyproject.toml'",
                    "'**/setup.py'", "'**/setup.cfg'", "'**/Pipfile.lock'", "'**/poetry.lock'", "'**/uv.lock'"):
        if pattern not in dependency_hash:
            errors.append(f"{SETUP}: the venv key must hash {pattern}")

    cache = steps[ids.index("python-venv-cache")]
    with_ = cache.get("with") or {}
    if not uses(cache, "actions/cache"):
        errors.append(f"{SETUP}: step 'python-venv-cache' must use actions/cache")
    if compact(with_.get("key")) != "${{steps.python-venv-key.outputs.key}}" \
            or compact(with_.get("path")) != "${{steps.python-venv-key.outputs.dir}}":
        errors.append(f"{SETUP}: step 'python-venv-cache' must cache the python-venv-key dir under its key")
    if "restore-keys" in with_:
        errors.append(f"{SETUP}: step 'python-venv-cache' must not restore a stale venv through restore-keys")

    activate = [step for step in steps if "python_venv_activate.sh" in str(step.get("run", ""))]
    if len(activate) != 1:
        errors.append(f"{SETUP}: expected one step running python_venv_activate.sh, found {len(activate)}")
    else:
        env = {name: compact(value) for name, value in (activate[0].get("env") or {}).items()}
        if steps.index(activate[0]) < steps.index(cache):
            errors.append(f"{SETUP}: the venv must be activated after the cache restore")
        if env.get("VENV_DIR") != "${{steps.python-venv-key.outputs.dir}}" \
                or env.get("PYTHON") != "${{steps.setup-python.outputs.python-path}}":
            errors.append(f"{SETUP}: python_venv_activate.sh must get VENV_DIR from python-venv-key and PYTHON from setup-python")

    hit = compact((outputs.get("python-venv-cache-hit") or {}).get("value"))
    if hit != "${{steps.python-venv-cache.outputs.cache-hit}}":
        errors.append(f"{SETUP}: output 'python-venv-cache-hit' must expose the python-venv-cache step's cache-hit")

    return errors


def check_python_interpreter(steps: list[dict]) -> list[str]:
    errors: list[str] = []
    ids = [step.get("id") for step in steps]

    if "python-tool-cache" not in ids:
        return [f"{SETUP}: missing step 'python-tool-cache'"]

    key_step = steps[ids.index("python-tool-cache")]
    if "_lib/python_tool_cache.sh" not in str(key_step.get("run", "")):
        errors.append(f"{SETUP}: step 'python-tool-cache' must run python_tool_cache.sh")

    caches = [
        step for step in steps
        if uses(step, "actions/cache")
        and compact((step.get("with") or {}).get("key")) == "${{steps.python-tool-cache.outputs.key}}"
    ]
    if len(caches) != 1 or compact(caches[0]["with"].get("path")) != "${{steps.python-tool-cache.outputs.path}}":
        return errors + [f"{SETUP}: expected one actions/cache step on the python-tool-cache path and key"]

    if compact(caches[0].get("if")) != "${{steps.python-tool-cache.outputs.key!=''}}":
        errors.append(f"{SETUP}: the Python interpreter cache must run only when python-tool-cache wrote a key")

    python = [step for step in steps if uses(step, "actions/setup-python")]
    if python and not steps.index(key_step) < steps.index(caches[0]) < steps.index(python[0]):
        errors.append(f"{SETUP}: the Python interpreter must be restored after its key and before actions/setup-python")

    return errors


def main() -> int:
    data = load_yaml(SETUP)
    inputs = data.get("inputs") or {}
    steps = composite_steps(data)
    errors = (
        check_detection(inputs, steps) + check_pip(steps) + check_node(steps) + check_apt(steps) + check_java(steps)
        + check_python_venv(inputs, data.get("outputs") or {}, steps) + check_python_interpreter(steps)
    )
    return report(errors, f"Checked {SETUP} ({len(steps)} steps), {len(errors)} violation(s).")


if __name__ == "__main__":
    sys.exit(main())
