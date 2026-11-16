#!/usr/bin/env python3
"""Contract: setup launches MongoDB and RabbitMQ in gated run: steps right after Checkout and waits for them last."""

from __future__ import annotations

import os
import sys

from _contract_lib import REPO_ROOT, composite_steps, load_yaml, report

SETUP = os.path.join("setup", "action.yml")
DOCKER_ACTIONS = ("supercharge/mongodb-github-action", "namoshek/rabbitmq-github-action")
SERVICES = {
    "MongoDB": {
        "gate": "mongodb-version",
        "script": "linters/_lib/start_mongodb.sh",
        "env": {
            "MONGODB_VERSION": "mongodb-version",
            "MONGODB_REPLICA_SET": "mongodb-replica-set",
            "MONGODB_PORT": "mongodb-port",
            "MONGODB_DB": "mongodb-db",
            "MONGODB_USERNAME": "mongodb-username",
            "MONGODB_PASSWORD": "mongodb-password",
        },
    },
    "RabbitMQ": {
        "gate": "rabbitmq-version",
        "script": "linters/_lib/start_rabbitmq.sh",
        "env": {
            "RABBITMQ_VERSION": "rabbitmq-version",
            "RABBITMQ_PORTS": "rabbitmq-ports",
            "RABBITMQ_CERTIFICATES": "rabbitmq-certificates",
            "RABBITMQ_CONFIG": "rabbitmq-config",
            "RABBITMQ_DEFINITIONS": "rabbitmq-definitions",
            "RABBITMQ_PLUGINS": "rabbitmq-plugins",
            "RABBITMQ_CONTAINER_NAME": "rabbitmq-container-name",
        },
    },
}


def compact(value: object) -> str:
    return str(value).replace(" ", "")


def check_step(name: str, phase: str, spec: dict, steps: list[dict]) -> list[str]:
    matches = [step for step in steps if step.get("name") == name]
    if len(matches) != 1:
        return [f"{SETUP}: expected exactly one '{name}' step, found {len(matches)}"]
    step = matches[0]
    errors: list[str] = []
    where = f"{SETUP}: '{name}'"

    if "uses" in step:
        errors.append(f"{where} must be a run: step, not uses: {step['uses']}")
    if compact(step.get("if")) != f"${{{{inputs.{spec['gate']}!='none'}}}}":
        errors.append(f"{where} must be gated on inputs.{spec['gate']} != 'none' (if: {step.get('if')!r})")
    expected_run = f'bash "${{GITHUB_ACTION_PATH}}/../{spec["script"]}" {phase}'
    if str(step.get("run", "")).strip() != expected_run:
        errors.append(f"{where} must run {expected_run}")
    if not os.path.isfile(os.path.join(REPO_ROOT, spec["script"])):
        errors.append(f"{where}: {spec['script']} does not exist")

    env = step.get("env") or {}
    for variable, input_name in spec["env"].items():
        if compact(env.get(variable)) != f"${{{{inputs.{input_name}}}}}":
            errors.append(f"{where} env {variable} must be ${{{{ inputs.{input_name} }}}}")
    return errors


def check_order(steps: list[dict]) -> list[str]:
    names = [str(step.get("name", "")) for step in steps]
    starts = {f"Start {service}" for service in SERVICES}
    waits = {f"Wait for {service}" for service in SERVICES}
    if not (starts | waits) <= set(names):
        return []
    errors: list[str] = []
    first_other = next(i for i, name in enumerate(names) if name != "Checkout" and name not in starts)
    last_other = max(i for i, name in enumerate(names) if name not in waits)
    for name in sorted(starts):
        if names.index(name) > first_other:
            errors.append(f"{SETUP}: '{name}' must come right after Checkout, before '{names[first_other]}'")
    for name in sorted(waits):
        if names.index(name) < last_other:
            errors.append(f"{SETUP}: '{name}' must come after every other step, including '{names[last_other]}'")
    return errors


def main() -> int:
    steps = composite_steps(load_yaml(SETUP))
    errors: list[str] = []
    for step in steps:
        action = str(step.get("uses", "")).split("@")[0]
        if action in DOCKER_ACTIONS:
            errors.append(f"{SETUP}: '{step.get('name')}' uses the Docker-based action {action}, which is built on every run")
    for service, spec in SERVICES.items():
        errors.extend(check_step(f"Start {service}", "launch", spec, steps))
        errors.extend(check_step(f"Wait for {service}", "wait", spec, steps))
    errors.extend(check_order(steps))
    return report(errors, f"Checked {len(SERVICES)} service(s) in {SETUP}, {len(errors)} violation(s).")


if __name__ == "__main__":
    sys.exit(main())
