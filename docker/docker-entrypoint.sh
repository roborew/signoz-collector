#!/usr/bin/env bash
# Wrap the container command with `infisical run` when Infisical auth + project + API host are set.
set -euo pipefail

if [[ "${INFISICAL_USE_CLI:-}" == "false" || "${INFISICAL_USE_CLI:-}" == "0" || "${INFISICAL_RUNTIME:-}" == "0" ]]; then
  exec "$@"
fi

domain="${INFISICAL_DOMAIN:-${INFISICAL_API_URL:-}}"
project_id="${INFISICAL_PROJECT_ID:-}"

if [[ -z "$project_id" || -z "$domain" ]]; then
  exec "$@"
fi

token="${INFISICAL_TOKEN:-}"
if [[ -z "$token" ]]; then
  client_id="${INFISICAL_CLIENT_ID:-${INFISICAL_UNIVERSAL_AUTH_CLIENT_ID:-}}"
  client_secret="${INFISICAL_CLIENT_SECRET:-${INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET:-}}"
  if [[ -n "$client_id" && -n "$client_secret" ]]; then
    token="$(
      infisical login \
        --method=universal-auth \
        --client-id="$client_id" \
        --client-secret="$client_secret" \
        --domain="$domain" \
        --silent \
        --plain
    )" || {
      echo "docker-entrypoint: infisical universal-auth login failed" >&2
      exit 1
    }
  else
    exec "$@"
  fi
fi

export INFISICAL_TOKEN="$token"

exec infisical run \
  --projectId="$project_id" \
  --env="${INFISICAL_ENV:-dev}" \
  --domain="$domain" \
  -- "$@"
