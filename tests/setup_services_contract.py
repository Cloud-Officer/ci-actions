#!/usr/bin/env python3
"""Contract: setup starts MongoDB and RabbitMQ from gated run: steps, never Docker-based actions."""

from __future__ import annotations

import os
import sys

from _contract_lib import REPO_ROOT, composite_steps, load_yaml, report

SETUP = os.path.join("setup", "action.yml")
DOCKER_ACTIONS = ("supercharge/mongodb-github-action", "namoshek/rabbitmq-github-action")
SERVICES = {
    "Setup MongoDB": {
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
    "Setup RabbitMQ": {
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


def check_service(name: str, spec: dict, steps: list[dict]) -> list[str]:
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
    expected_run = f'bash "${{GITHUB_ACTION_PATH}}/../{spec["script"]}"'
    if str(step.get("run", "")).strip() != expected_run:
        errors.append(f"{where} must run {expected_run}")
    if not os.path.isfile(os.path.join(REPO_ROOT, spec["script"])):
        errors.append(f"{where}: {spec['script']} does not exist")

    env = step.get("env") or {}
    for variable, input_name in spec["env"].items():
        if compact(env.get(variable)) != f"${{{{inputs.{input_name}}}}}":
            errors.append(f"{where} env {variable} must be ${{{{ inputs.{input_name} }}}}")
    return errors


def main() -> int:
    steps = composite_steps(load_yaml(SETUP))
    errors: list[str] = []
    for step in steps:
        action = str(step.get("uses", "")).split("@")[0]
        if action in DOCKER_ACTIONS:
            errors.append(f"{SETUP}: '{step.get('name')}' uses the Docker-based action {action}, which is built on every run")
    for name, spec in SERVICES.items():
        errors.extend(check_service(name, spec, steps))
    return report(errors, f"Checked {len(SERVICES)} service step(s) in {SETUP}, {len(errors)} violation(s).")


if __name__ == "__main__":
    sys.exit(main())
