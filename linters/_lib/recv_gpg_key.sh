#!/usr/bin/env bash

# Fetches a GPG public key with retries and keyserver fallback; keyserver.ubuntu.com is intermittently unavailable.
#
# Usage (from a composite action step):
#   run: bash "${GITHUB_ACTION_PATH}/../_lib/recv_gpg_key.sh" <KEY_ID_OR_FINGERPRINT>

set -euo pipefail

key="${1:?usage: recv_gpg_key.sh KEY_ID_OR_FINGERPRINT}"
keyservers=(
  hkps://keyserver.ubuntu.com
  hkps://keys.openpgp.org
  hkps://pgp.mit.edu
)

attempts=3

for attempt in $(seq 1 "${attempts}"); do
  for keyserver in "${keyservers[@]}"; do
    if gpg --keyserver "${keyserver}" --recv-keys "${key}"; then
      echo "Imported GPG key ${key} from ${keyserver} (attempt ${attempt})"
      exit 0
    fi
    echo "gpg --recv-keys ${key} from ${keyserver} failed (attempt ${attempt})" >&2
  done
  if [ "${attempt}" -lt "${attempts}" ]; then
    sleep $(( attempt * 5 ))
  fi
done

echo "::error::Failed to import GPG key ${key} from any keyserver after ${attempts} attempts" >&2
exit 1
