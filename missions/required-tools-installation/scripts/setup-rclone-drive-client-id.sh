#!/usr/bin/env bash
# setup-rclone-drive-client-id.sh — Unix (macOS/Linux)
#
# Expects authenticated gcloud + a Drive-capable service-account JSON.
# Ensures Internal OAuth consent, provisions an OAuth client for rclone Drive
# (https://rclone.org/drive/#making-your-own-client-id), and writes
# client_id / client_secret into rclone config.
#
# API note (2026): clientauthconfig.googleapis.com /v1/projects/{n}/brands returns
# HTTP 404. This script uses IAP OAuth Admin REST (iap.googleapis.com) which still
# creates Internal brands + clients suitable for rclone client_id/client_secret.
# Google has deprecated IAP OAuth Admin APIs (turn-down timeline on gcloud warnings);
# when those stop working, replace ensure_internal_brand / create_desktop_client.
#
# Forbidden: printing client_secret or oauth-client.json contents to stdout/stderr.
# Windows: exit 5 — use setup-rclone-drive-client-id.ps1 (follow-up PR).
#
# Exit codes: 0 ok | 1 usage | 2 preconditions | 3 GCP/oauth | 4 rclone | 5 windows
set -euo pipefail

# Prefer bare gcloud/rclone on PATH (Mission Control shells include ~/bin).
# Incomplete registry exposure is a parent install failure — do not PATH-prepend.
export CLOUDSDK_CORE_DISABLE_PROMPTS="${CLOUDSDK_CORE_DISABLE_PROMPTS:-1}"

SCRIPT_NAME="$(basename "$0")"
CLIENT_DISPLAY_NAME_DEFAULT="sedea-rclone-drive"
OAUTH_STORE_DIR_DEFAULT="${HOME}/.config/sedea/documentation-management"
RCLONE_REDIRECT_URI="http://127.0.0.1:53682/"

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} --project-id <id> --credentials-path <sa.json> [options]

Required:
  --project-id <id>
  --credentials-path <path>   Absolute path to Drive-capable SA JSON

Options:
  --rclone-remote <name>         Default: sedea-gdrive
  --client-display-name <name>   Default: ${CLIENT_DISPLAY_NAME_DEFAULT}
  --oauth-store-dir <dir>        Default: ${OAUTH_STORE_DIR_DEFAULT}
  --reuse-existing-oauth         Skip create when oauth-client.json already valid
  --support-email <email>        Default: active gcloud account
  --dry-run                      Plan only (no secrets printed)
  -h, --help
EOF
}

log() { printf '%s\n' "$*" >&2; }
die() { local code="$1"; shift; log "ERROR: $*"; exit "$code"; }

is_windows() {
  case "$(uname -s 2>/dev/null || true)" in
    MINGW*|MSYS*|CYGWIN*|Windows_NT) return 0 ;;
    *) return 1 ;;
  esac
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die 2 "missing required command: $1"
}

# Extract first IAP brand resource name from a brands list/create JSON body.
json_first_brand_name() {
  jq -r '
    (.brands // empty) as $b |
    if ($b | type) == "array" then
      ($b[0].name // empty)
    elif ($b | type) == "object" then
      ($b.name // empty)
    elif .name then
      .name
    else
      empty
    end
  ' 2>/dev/null || true
}

PROJECT_ID=""
CREDENTIALS_PATH=""
RCLONE_REMOTE="sedea-gdrive"
CLIENT_DISPLAY_NAME="${CLIENT_DISPLAY_NAME_DEFAULT}"
OAUTH_STORE_DIR="${OAUTH_STORE_DIR_DEFAULT}"
REUSE_EXISTING=0
SUPPORT_EMAIL=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-id) PROJECT_ID="${2:-}"; shift 2 ;;
    --credentials-path) CREDENTIALS_PATH="${2:-}"; shift 2 ;;
    --rclone-remote) RCLONE_REMOTE="${2:-}"; shift 2 ;;
    --client-display-name) CLIENT_DISPLAY_NAME="${2:-}"; shift 2 ;;
    --oauth-store-dir) OAUTH_STORE_DIR="${2:-}"; shift 2 ;;
    --reuse-existing-oauth) REUSE_EXISTING=1; shift ;;
    --support-email) SUPPORT_EMAIL="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; die 1 "unknown argument: $1" ;;
  esac
done

if is_windows; then
  die 5 "Windows detected — use setup-rclone-drive-client-id.ps1 (follow-up PR)"
fi

[[ -n "$PROJECT_ID" ]] || { usage; die 1 "--project-id is required"; }
[[ -n "$CREDENTIALS_PATH" ]] || { usage; die 1 "--credentials-path is required"; }
[[ -n "$RCLONE_REMOTE" ]] || die 1 "--rclone-remote must be non-empty"

require_cmd gcloud
require_cmd rclone
require_cmd curl
require_cmd jq
require_cmd awk

[[ -f "$CREDENTIALS_PATH" ]] || die 2 "credentials file not found: $CREDENTIALS_PATH"

ACTIVE_ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -n1 || true)"
[[ -n "$ACTIVE_ACCOUNT" ]] || die 2 "no active gcloud account — run gcloud auth login in the user terminal"

if [[ -z "$SUPPORT_EMAIL" ]]; then
  SUPPORT_EMAIL="$ACTIVE_ACCOUNT"
fi

SA_TYPE="$(jq -r '.type // empty' "$CREDENTIALS_PATH")"
[[ "$SA_TYPE" == "service_account" ]] || die 2 "credentials path is not a usable service-account JSON (type must be service_account)"
SA_EMAIL="$(jq -r '.client_email // empty' "$CREDENTIALS_PATH")"
[[ -n "$SA_EMAIL" ]] || die 2 "credentials path is not a usable service-account JSON (missing client_email)"

log "preconditions ok: gcloud=${ACTIVE_ACCOUNT} sa=${SA_EMAIL} project=${PROJECT_ID}"

OAUTH_JSON="${OAUTH_STORE_DIR}/oauth-client.json"
mkdir -p "$OAUTH_STORE_DIR"
chmod 700 "$OAUTH_STORE_DIR" 2>/dev/null || true

if [[ "$DRY_RUN" -eq 1 ]]; then
  log "dry-run: enable drive.googleapis.com + iap.googleapis.com on ${PROJECT_ID}"
  log "dry-run: ensure Internal OAuth brand via iap.googleapis.com (support=${SUPPORT_EMAIL})"
  log "dry-run: create/reuse OAuth client displayName=${CLIENT_DISPLAY_NAME}"
  log "dry-run: write client fields into rclone remote=${RCLONE_REMOTE} (secrets not printed)"
  log "dry-run: oauth store=${OAUTH_JSON}"
  exit 0
fi

gcloud config set project "$PROJECT_ID" >/dev/null
log "enabling drive.googleapis.com and iap.googleapis.com ..."
gcloud services enable drive.googleapis.com iap.googleapis.com --project="$PROJECT_ID"

PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
[[ -n "$PROJECT_NUMBER" ]] || die 3 "could not resolve projectNumber for ${PROJECT_ID}"

ACCESS_TOKEN="$(gcloud auth print-access-token)"
[[ -n "$ACCESS_TOKEN" ]] || die 2 "gcloud auth print-access-token failed"

oauth_store_valid() {
  [[ -f "$OAUTH_JSON" ]] || return 1
  local cid sec
  cid="$(jq -r '.client_id // empty' "$OAUTH_JSON" 2>/dev/null)" || return 1
  sec="$(jq -r '.client_secret // empty' "$OAUTH_JSON" 2>/dev/null)" || return 1
  [[ -n "$cid" && -n "$sec" ]]
}

# Prints client_id then client_secret on two lines (caller must not log).
read_oauth_store() {
  jq -r '.client_id, .client_secret' "$OAUTH_JSON"
}

write_oauth_store() {
  local cid="$1" sec="$2"
  jq -n \
    --arg cid "$cid" \
    --arg sec "$sec" \
    --arg pid "$PROJECT_ID" \
    '{client_id: $cid, client_secret: $sec, project_id: $pid}' > "$OAUTH_JSON"
  chmod 600 "$OAUTH_JSON"
}

# --- Internal OAuth consent brand via IAP Admin REST (clientauthconfig is 404) ---
ensure_internal_brand() {
  local list_json brand_name create_json
  list_json="$(curl -sS \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "x-goog-user-project: ${PROJECT_ID}" \
    "https://iap.googleapis.com/v1/projects/${PROJECT_ID}/brands" || true)"

  brand_name="$(printf '%s' "$list_json" | json_first_brand_name)"

  if [[ -n "$brand_name" ]]; then
    log "oauth brand exists (iap)"
    curl -sS -X PATCH \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      -H "x-goog-user-project: ${PROJECT_ID}" \
      -H "Content-Type: application/json" \
      "https://iap.googleapis.com/v1/${brand_name}?updateMask=orgInternalOnly" \
      -d '{"orgInternalOnly": true}' >/dev/null 2>&1 || true
    printf '%s\n' "$brand_name"
    return 0
  fi

  log "creating OAuth consent brand via iap.googleapis.com (Internal) ..."
  create_json="$(curl -sS -X POST \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "x-goog-user-project: ${PROJECT_ID}" \
    -H "Content-Type: application/json" \
    "https://iap.googleapis.com/v1/projects/${PROJECT_ID}/brands" \
    -d "$(jq -n --arg email "$SUPPORT_EMAIL" '{applicationTitle: "Sedea rclone Drive", supportEmail: $email}')")"

  brand_name="$(printf '%s' "$create_json" | json_first_brand_name)"
  if [[ -z "$brand_name" ]]; then
    brand_name="$(printf '%s' "$create_json" | jq -r '.name // empty' 2>/dev/null || true)"
  fi

  if [[ -z "$brand_name" ]]; then
    list_json="$(curl -sS \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      -H "x-goog-user-project: ${PROJECT_ID}" \
      "https://iap.googleapis.com/v1/projects/${PROJECT_ID}/brands" || true)"
    brand_name="$(printf '%s' "$list_json" | json_first_brand_name)"
    [[ -n "$brand_name" ]] || {
      local err_snip
      err_snip="$(printf '%s' "$create_json" | jq -c '{error, message, status, code, raw: (. | tostring | .[0:200])}' 2>/dev/null || printf '%s' "$create_json" | head -c 200)"
      die 3 "failed to create or locate OAuth consent brand via iap.googleapis.com: ${err_snip}"
    }
  fi

  printf '%s\n' "$brand_name"
}

# --- OAuth client under IAP brand (secret returned once; never log) ---
create_desktop_client() {
  local brand_name resp_file cid sec name err_snip
  brand_name="$1"
  [[ -n "$brand_name" ]] || die 3 "create_desktop_client: missing brand"

  log "creating OAuth client via iap.googleapis.com (displayName=${CLIENT_DISPLAY_NAME}) ..."
  resp_file="$(mktemp)"
  chmod 600 "$resp_file"
  if ! curl -sS -X POST \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "x-goog-user-project: ${PROJECT_ID}" \
    -H "Content-Type: application/json" \
    "https://iap.googleapis.com/v1/${brand_name}/identityAwareProxyClients" \
    -d "$(jq -n --arg n "$CLIENT_DISPLAY_NAME" '{displayName: $n}')" \
    >"$resp_file"
  then
    rm -f "$resp_file"
    die 3 "IAP OAuth client HTTP request failed"
  fi

  cid="$(jq -r '.clientId // .client_id // empty' "$resp_file")"
  name="$(jq -r '.name // empty' "$resp_file")"
  if [[ -z "$cid" && "$name" == *identityAwareProxyClients/* ]]; then
    cid="${name##*/}"
  fi
  sec="$(jq -r '.secret // .clientSecret // .client_secret // empty' "$resp_file")"

  if [[ -z "$cid" || -z "$sec" ]]; then
    err_snip="$(jq -c '{error, message, status, code, details, keys: (keys // [])}' "$resp_file" 2>/dev/null || echo '{}')"
    rm -f "$resp_file"
    die 3 "IAP OAuth client create failed — ${err_snip}. Need iap.identityAwareProxyClients.create (and brands). Do not paste secrets into chat; fix IAM and re-run."
  fi

  write_oauth_store "$cid" "$sec"
  rm -f "$resp_file"
  log "OAuth client stored (client_id length=${#cid}; secret not logged)"
}

# Non-interactive rclone.conf write (avoids macOS hang on interactive rclone config create).
write_rclone_remote() {
  local cid="$1" sec="$2"
  local conf_path conf_dir tmp_path remote
  conf_path="${RCLONE_CONFIG:-$HOME/.config/rclone/rclone.conf}"
  conf_dir="$(dirname "$conf_path")"
  remote="$RCLONE_REMOTE"
  mkdir -p "$conf_dir"
  tmp_path="${conf_path}.tmp.$$"

  if [[ -f "$conf_path" ]] && grep -q "^\[${remote}\]" "$conf_path" 2>/dev/null; then
    awk -v remote="$remote" -v cid="$cid" -v sec="$sec" '
      BEGIN { in_sec=0; done=0 }
      /^\[/ {
        if (in_sec && !done) {
          print "type = drive"
          print "scope = drive"
          print "client_id = " cid
          print "client_secret = " sec
          done=1
        }
        in_sec = ($0 == "[" remote "]")
        print
        next
      }
      in_sec && /^(type|scope|client_id|client_secret) =/ { next }
      { print }
      END {
        if (in_sec && !done) {
          print "type = drive"
          print "scope = drive"
          print "client_id = " cid
          print "client_secret = " sec
        }
      }
    ' "$conf_path" > "$tmp_path" || die 4 "rclone config write failed"
  else
    {
      [[ -f "$conf_path" ]] && cat "$conf_path"
      printf '[%s]\n' "$remote"
      printf 'type = drive\n'
      printf 'scope = drive\n'
      printf 'client_id = %s\n' "$cid"
      printf 'client_secret = %s\n' "$sec"
    } > "$tmp_path" || die 4 "rclone config write failed"
  fi

  mv "$tmp_path" "$conf_path"
  chmod 600 "$conf_path" 2>/dev/null || true
}

verify_rclone_client_id() {
  local cid
  cid="$(rclone config dump 2>/dev/null | jq -r --arg r "$RCLONE_REMOTE" '.[$r].client_id // .[$r + ":"].client_id // empty')" || die 4 "rclone remote missing non-empty client_id after write"
  [[ -n "$cid" ]] || die 4 "rclone remote missing non-empty client_id after write"
}

if [[ "$REUSE_EXISTING" -eq 1 ]]; then
  oauth_store_valid || die 2 "--reuse-existing-oauth set but oauth store missing/invalid: ${OAUTH_JSON}"
  log "reusing existing oauth store"
elif oauth_store_valid; then
  log "oauth store already present — reusing (delete ${OAUTH_JSON} to force recreate)"
else
  BRAND_NAME="$(ensure_internal_brand)"
  [[ -n "$BRAND_NAME" ]] || die 3 "OAuth consent brand unavailable"
  create_desktop_client "$BRAND_NAME"
fi

oauth_store_valid || die 3 "oauth store invalid after provision: ${OAUTH_JSON}"

# bash 3.2-safe (macOS /bin/bash): no mapfile
_OAUTH_LINES="$(read_oauth_store)"
CLIENT_ID="$(printf '%s\n' "$_OAUTH_LINES" | sed -n '1p')"
CLIENT_SECRET="$(printf '%s\n' "$_OAUTH_LINES" | sed -n '2p')"
_OAUTH_LINES=""
[[ -n "$CLIENT_ID" && -n "$CLIENT_SECRET" ]] || die 3 "oauth store incomplete"

log "writing rclone remote ${RCLONE_REMOTE} (non-interactive; secrets not printed) ..."
write_rclone_remote "$CLIENT_ID" "$CLIENT_SECRET"
verify_rclone_client_id

CLIENT_SECRET=""
unset CLIENT_SECRET

log "success: rclone remote ${RCLONE_REMOTE} has client_id; oauth store=${OAUTH_JSON}"
log "next: user runs rclone config reconnect ${RCLONE_REMOTE}: in their terminal (browser OAuth)"
printf 'rcloneClientConfigured=true\n'
printf 'rcloneRemote=%s\n' "$RCLONE_REMOTE"
printf 'oauthStorePath=%s\n' "$OAUTH_JSON"
printf 'projectId=%s\n' "$PROJECT_ID"
printf 'serviceAccountEmail=%s\n' "$SA_EMAIL"
exit 0
