#!/usr/bin/env bash

# Fails unless AWS credentials are supplied: ROLE_TO_ASSUME (OIDC), or both ACCESS_KEY_ID and SECRET_ACCESS_KEY.
#
# Usage (from a composite action step):
#   env:
#     ROLE_TO_ASSUME: ${{ inputs.aws-role-to-assume }}
#     ACCESS_KEY_ID: ${{ inputs.aws-access-key-id }}
#     SECRET_ACCESS_KEY: ${{ inputs.aws-secret-access-key }}
#   run: bash "${GITHUB_ACTION_PATH}/../linters/_lib/require_aws_credentials.sh"

set -euo pipefail

function blank()
{
  [[ -z "${1//[[:space:]]/}" ]]
}

role="${ROLE_TO_ASSUME:-}"
key_id="${ACCESS_KEY_ID:-}"
secret="${SECRET_ACCESS_KEY:-}"

if { blank "${key_id}" && ! blank "${secret}"; } || { ! blank "${key_id}" && blank "${secret}"; }; then
  echo "::error::aws-access-key-id and aws-secret-access-key must be set together"
  exit 1
fi

if blank "${role}" && blank "${key_id}"; then
  echo "::error::no AWS credentials: set aws-role-to-assume (GitHub OIDC), or aws-access-key-id and aws-secret-access-key"
  exit 1
fi
