#!/usr/bin/env bash

# Fetch a GPG public key with retries and keyserver fallback.
#
# Usage (from a composite action step):
#   run: bash "${GITHUB_ACTION_PATH}/../_lib/recv_gpg_key.sh" <KEY_ID_OR_FINGERPRINT>
#
# keyserver.ubuntu.com is well known to be slow / intermittently unavailable,
# which made the pmd/phpcs linters flaky. Try several keyservers, a few times,
# before failing the step with an actionable message.

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
  # Only back off between attempts. Sleeping after the last one delayed the
  # error by 15 seconds without ever retrying again (BUG-018).
  if [ "${attempt}" -lt "${attempts}" ]; then
    sleep $(( attempt * 5 ))
  fi
done

echo "::error::Failed to import GPG key ${key} from any keyserver after ${attempts} attempts" >&2
exit 1
