#!/usr/bin/env bash
# Pull collector secrets from Infisical and merge them into .env.local.
#
# Requires INFISICAL_* bootstrap vars in .env (see README.md).
# Skips empty Infisical values. Never overwrites INFISICAL_* bootstrap vars.
# Keep INFISICAL_* bootstrap in .env; pulled secrets land in .env.local.
#
# Usage: make env-pull
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

BOOTSTRAP_ENV_FILE=".env"
SECRETS_ENV_FILE=".env.local"

if ! command -v infisical >/dev/null 2>&1; then
  echo "infisical CLI not found. Install it for your platform:" >&2
  echo "  macOS:  brew install infisical/get-cli/infisical" >&2
  echo "  Linux:  See https://infisical.com/docs/cli/overview" >&2
  echo "  Other:  https://infisical.com/docs/cli/overview" >&2
  exit 1
fi

if [[ ! -f "$BOOTSTRAP_ENV_FILE" ]]; then
  echo "Missing $BOOTSTRAP_ENV_FILE — add INFISICAL_* bootstrap vars first." >&2
  exit 1
fi

if [[ ! -f "$SECRETS_ENV_FILE" ]]; then
  cat > "$SECRETS_ENV_FILE" <<'EOF'
# Pulled from Infisical via make env-pull — do not commit.
# Keep INFISICAL_* bootstrap in .env.
EOF
fi

set -a
# shellcheck disable=SC1090
source "$BOOTSTRAP_ENV_FILE"
set +a

domain="${INFISICAL_DOMAIN:-${INFISICAL_API_URL:-}}"
project_id="${INFISICAL_PROJECT_ID:-}"
env_slug="${INFISICAL_ENV:-dev}"
client_id="${INFISICAL_CLIENT_ID:-${INFISICAL_UNIVERSAL_AUTH_CLIENT_ID:-}}"
client_secret="${INFISICAL_CLIENT_SECRET:-${INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET:-}}"

if [[ -z "$project_id" || -z "$domain" ]]; then
  echo "Set INFISICAL_PROJECT_ID and INFISICAL_API_URL (or INFISICAL_DOMAIN) in $BOOTSTRAP_ENV_FILE." >&2
  exit 1
fi

if [[ -z "$client_id" || -z "$client_secret" ]]; then
  echo "Set INFISICAL_CLIENT_ID and INFISICAL_CLIENT_SECRET in $BOOTSTRAP_ENV_FILE." >&2
  exit 1
fi

raw_export="$(mktemp)"
merged_file="$(mktemp)"
trap 'rm -f "$raw_export" "$merged_file"' EXIT

echo "Pulling Infisical secrets (env=$env_slug) into $SECRETS_ENV_FILE"
token="$(
  infisical login \
    --method=universal-auth \
    --client-id="$client_id" \
    --client-secret="$client_secret" \
    --domain="$domain" \
    --silent \
    --plain
)"

infisical export \
  --projectId="$project_id" \
  --env="$env_slug" \
  --domain="$domain" \
  --token="$token" \
  --format=dotenv \
  --output-file="$raw_export"

awk '
function trim(s) {
  sub(/^[ \t]+/, "", s)
  sub(/[ \t]+$/, "", s)
  return s
}
function should_skip(key) {
  return index(key, "INFISICAL_") == 1
}
function unquote(val,   v) {
  v = val
  if (v ~ /^'\''.*'\''$/) {
    sub(/^'\''/, "", v)
    sub(/'\''$/, "", v)
  } else if (v ~ /^".*"$/) {
    sub(/^"/, "", v)
    sub(/"$/, "", v)
  }
  return v
}
function isempty(val) {
  gsub(/[ \t]/, "", val)
  return length(val) == 0
}
function record_var(line,   eq, key) {
  eq = index(line, "=")
  if (eq == 0) return
  key = trim(substr(line, 1, eq - 1))
  if (should_skip(key)) return
  vars[key] = line
}
FNR == NR {
  if ($0 ~ /^[ \t]*#/ || $0 ~ /^[ \t]*$/) next
  eq = index($0, "=")
  if (eq == 0) next
  key = trim(substr($0, 1, eq - 1))
  if (should_skip(key)) next
  val = substr($0, eq + 1)
  if (isempty(unquote(val))) next
  incoming[key] = $0
  next
}
{
  if ($0 ~ /^[A-Za-z_][A-Za-z0-9_]*=/) record_var($0)
}
END {
  for (key in vars) merged[key] = vars[key]
  for (key in incoming) merged[key] = incoming[key]
  for (key in merged) print merged[key]
}
' "$raw_export" "$SECRETS_ENV_FILE" | LC_ALL=C sort > "$merged_file.tmp"

{
  cat <<EOF
# Pulled from Infisical via make env-pull — do not commit.
# Keep INFISICAL_* bootstrap in .env.

# Pulled from Infisical ($env_slug) via make env-pull
EOF
  cat "$merged_file.tmp"
} > "$merged_file"
rm -f "$merged_file.tmp"

mv "$merged_file" "$SECRETS_ENV_FILE"
trap - EXIT
rm -f "$raw_export"

# Drop legacy pulled secrets from .env (older env:pull wrote them here).
bootstrap_clean="$(mktemp)"
awk '
/^# Pulled from Infisical/ { exit }
/^[A-Za-z_][A-Za-z0-9_]*=/ {
  eq = index($0, "=")
  key = substr($0, 1, eq - 1)
  if (key ~ /^INFISICAL_/) {
    print
    next
  }
  next
}
{ print }
' "$BOOTSTRAP_ENV_FILE" > "$bootstrap_clean"
mv "$bootstrap_clean" "$BOOTSTRAP_ENV_FILE"

echo "Merged Infisical secrets into $SECRETS_ENV_FILE"
echo "Bootstrap vars stay in $BOOTSTRAP_ENV_FILE; skipped: INFISICAL_* (and empty Infisical values)"
