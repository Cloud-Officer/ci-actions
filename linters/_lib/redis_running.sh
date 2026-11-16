#!/usr/bin/env bash

# Writes running=true|false to GITHUB_OUTPUT for whether a Redis server answers PING on 127.0.0.1:${PORT}.

set -euo pipefail

[ -n "${PORT:-}" ] || { echo "::error::PORT is required"; exit 1; }

reply=""
if exec 3<>"/dev/tcp/127.0.0.1/${PORT}" 2>/dev/null; then
  printf 'PING\r\n' >&3
  IFS= read -r -t 2 reply <&3 || true
  exec 3>&-
fi

reply="${reply%$'\r'}"

if [ "${reply}" = "+PONG" ] || [[ "${reply}" == "-NOAUTH"* ]]; then
  echo "Redis is already running on port ${PORT}"
  echo "running=true" >> "${GITHUB_OUTPUT}"
else
  echo "running=false" >> "${GITHUB_OUTPUT}"
fi
