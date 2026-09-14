#!/usr/bin/env python3
"""Contract: the AWS actions accept GitHub OIDC as well as static access keys.

CFG-001 (#306). `aws`, `codedeploy/deploy` and `codedeploy/s3copy` used to
require a long-lived IAM access key pair. They now also accept
`aws-role-to-assume`, so a workflow with `permissions: id-token: write` can
assume a role through GitHub OIDC with no stored AWS secret. This test pins
that wiring:

  1. Each action declares the OIDC inputs and no longer requires the key pair.
  2. Its first step runs linters/_lib/require_aws_credentials.sh with the role
     and both keys bound from the action's inputs.
  3. Its configure-aws-credentials step passes the role, the keys and the OIDC
     options through from the inputs.
  4. `setup` configures AWS credentials when only a role is supplied.

Usage: python3 tests/aws_credentials_contract.py
Exits non-zero and prints every violation found.
"""

from __future__ import annotations

import os
import sys

from _contract_lib import composite_steps, load_yaml, report

ACTIONS = (
    os.path.join("aws", "action.yml"),
    os.path.join("codedeploy", "deploy", "action.yml"),
    os.path.join("codedeploy", "s3copy", "action.yml"),
)
SETUP = os.path.join("setup", "action.yml")
GATE = "require_aws_credentials.sh"
CONFIGURE = "aws-actions/configure-aws-credentials"
OIDC_INPUTS = ("aws-role-to-assume", "aws-audience", "aws-role-session-name", "aws-role-duration-seconds")
GATE_ENV = {
    "ROLE_TO_ASSUME": "aws-role-to-assume",
    "ACCESS_KEY_ID": "aws-access-key-id",
    "SECRET_ACCESS_KEY": "aws-secret-access-key",
}
CONFIGURE_WITH = {
    "aws-region": "aws-region",
    "role-to-assume": "aws-role-to-assume",
    "aws-access-key-id": "aws-access-key-id",
    "aws-secret-access-key": "aws-secret-access-key",
    "audience": "aws-audience",
    "role-session-name": "aws-role-session-name",
    "role-duration-seconds": "aws-role-duration-seconds",
}


def bound_to(value: object, input_name: str) -> bool:
    return str(value).replace(" ", "") == f"${{{{inputs.{input_name}}}}}"


def check_action(rel: str) -> list[str]:
    errors: list[str] = []
    data = load_yaml(rel)
    inputs = data.get("inputs") or {}

    for name in OIDC_INPUTS:
        if name not in inputs:
            errors.append(f"{rel}: missing input '{name}'")
    for name in ("aws-access-key-id", "aws-secret-access-key"):
        if (inputs.get(name) or {}).get("required") is not False:
            errors.append(f"{rel}: input '{name}' must be required: false so a role can replace it")

    steps = composite_steps(data)
    if not steps or GATE not in str(steps[0].get("run", "")):
        errors.append(f"{rel}: the first step must run {GATE}")
    else:
        env = steps[0].get("env") or {}
        for variable, input_name in GATE_ENV.items():
            if not bound_to(env.get(variable), input_name):
                errors.append(f"{rel}: first step env {variable} must be ${{{{ inputs.{input_name} }}}}")

    configure = [step for step in steps if str(step.get("uses", "")).split("@")[0] == CONFIGURE]
    if len(configure) != 1:
        errors.append(f"{rel}: expected exactly one {CONFIGURE} step, found {len(configure)}")
    else:
        with_block = configure[0].get("with") or {}
        for key, input_name in CONFIGURE_WITH.items():
            if not bound_to(with_block.get(key), input_name):
                errors.append(f"{rel}: {CONFIGURE} must pass {key}: ${{{{ inputs.{input_name} }}}}")

    return errors


def check_setup() -> list[str]:
    configure = [step for step in composite_steps(load_yaml(SETUP)) if str(step.get("uses", "")).split("@")[0] == CONFIGURE]
    if len(configure) != 1:
        return [f"{SETUP}: expected exactly one {CONFIGURE} step, found {len(configure)}"]
    condition = str(configure[0].get("if", ""))
    if "inputs.aws-role-to-assume" not in condition:
        return [f"{SETUP}: the {CONFIGURE} step must also run when only aws-role-to-assume is set (if: {condition!r})"]
    return []


def main() -> int:
    errors: list[str] = []
    for rel in ACTIONS:
        errors.extend(check_action(rel))
    errors.extend(check_setup())
    return report(errors, f"Checked {len(ACTIONS) + 1} action(s) for GitHub OIDC credential support, {len(errors)} violation(s).")


if __name__ == "__main__":
    sys.exit(main())
