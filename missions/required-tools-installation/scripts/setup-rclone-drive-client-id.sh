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

# Agent / non-interactive shells: never hang on gcloud "enable API? (y/N)"
export CLOUDSDK_CORE_DISABLE_PROMPTS="${CLOUDSDK_CORE_DISABLE_PROMPTS:-1}"

# Prefer registry install paths when bare gcloud/rclone are missing from PATH
if ! command -v gcloud >/dev/null 2>&1 && [[ -x "${HOME}/google-cloud-sdk/bin/gcloud" ]]; then
  export PATH="${HOME}/google-cloud-sdk/bin:${PATH}"
fi
if ! command -v rclone >/dev/null 2>&1 && [[ -x "${HOME}/bin/rclone" ]]; then
  export PATH="${HOME}/bin:${PATH}"
fi

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
require_cmd python3

[[ -f "$CREDENTIALS_PATH" ]] || die 2 "credentials file not found: $CREDENTIALS_PATH"

ACTIVE_ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -n1 || true)"
[[ -n "$ACTIVE_ACCOUNT" ]] || die 2 "no active gcloud account — run gcloud auth login in the user terminal"

if [[ -z "$SUPPORT_EMAIL" ]]; then
  SUPPORT_EMAIL="$ACTIVE_ACCOUNT"
fi

SA_EMAIL="$(python3 - "$CREDENTIALS_PATH" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
if data.get("type") != "service_account":
    raise SystemExit("type must be service_account")
email = data.get("client_email") or ""
if not email:
    raise SystemExit("missing client_email")
print(email)
PY
)" || die 2 "credentials path is not a usable service-account JSON"

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
  python3 - "$OAUTH_JSON" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
cid = data.get("client_id") or ""
sec = data.get("client_secret") or ""
raise SystemExit(0 if cid and sec else 1)
PY
}

# Prints client_id then client_secret on two lines (caller must not log).
read_oauth_store() {
  python3 - "$OAUTH_JSON" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
print(data["client_id"])
print(data["client_secret"])
PY
}

write_oauth_store() {
  local cid="$1" sec="$2"
  python3 - "$OAUTH_JSON" "$cid" "$sec" "$PROJECT_ID" <<'PY'
import json, os, sys
path, cid, sec, project_id = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open(path, "w", encoding="utf-8") as f:
    json.dump({"client_id": cid, "client_secret": sec, "project_id": project_id}, f)
os.chmod(path, 0o600)
PY
}

# --- Internal OAuth consent brand via IAP Admin REST (clientauthconfig is 404) ---
ensure_internal_brand() {
  local list_json brand_name create_json http_body
  list_json="$(curl -sS \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "x-goog-user-project: ${PROJECT_ID}" \
    "https://iap.googleapis.com/v1/projects/${PROJECT_ID}/brands" || true)"

  brand_name="$(python3 -c '
import json,sys
raw=sys.stdin.read().strip()
try:
    data=json.loads(raw) if raw else {}
except Exception:
    data={}
brands=data.get("brands") or []
if isinstance(brands, dict):
    brands=[brands]
# empty {} means no brands
if not brands and isinstance(data, dict) and data.get("name"):
    brands=[data]
for b in brands:
    name=b.get("name") or ""
    if name:
        print(name)
        break
' <<<"$list_json")"

  if [[ -n "$brand_name" ]]; then
    log "oauth brand exists (iap)"
    # Best-effort Internal flag (IAP brands are typically orgInternalOnly already)
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
    -d "$(python3 -c 'import json,sys; print(json.dumps({"applicationTitle":"Sedea rclone Drive","supportEmail":sys.argv[1]}))' "$SUPPORT_EMAIL")")"

  brand_name="$(python3 -c '
import json,sys
raw=sys.stdin.read()
try:
    data=json.loads(raw) if raw else {}
except Exception:
    data={}
name=data.get("name") or ""
if not name:
    err={k:data.get(k) for k in ("error","message","status","code") if k in data}
    # ALREADY_EXISTS may still need a list retry — surface briefly
    raise SystemExit("brand create failed: "+json.dumps(err or {"raw": raw[:200]})[:400])
print(name)
' <<<"$create_json")" || {
    # Race / already exists: re-list
    list_json="$(curl -sS \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      -H "x-goog-user-project: ${PROJECT_ID}" \
      "https://iap.googleapis.com/v1/projects/${PROJECT_ID}/brands" || true)"
    brand_name="$(python3 -c '
import json,sys
raw=sys.stdin.read().strip()
try:
    data=json.loads(raw) if raw else {}
except Exception:
    data={}
brands=data.get("brands") or []
if isinstance(brands, dict):
    brands=[brands]
if not brands and isinstance(data, dict) and data.get("name"):
    brands=[data]
for b in brands:
    name=b.get("name") or ""
    if name:
        print(name)
        break
' <<<"$list_json")"
    [[ -n "$brand_name" ]] || die 3 "failed to create or locate OAuth consent brand via iap.googleapis.com"
  }

  printf '%s\n' "$brand_name"
}

# --- OAuth client under IAP brand (secret returned once; never log) ---
create_desktop_client() {
  local brand_name resp_file
  brand_name="$1"
  [[ -n "$brand_name" ]] || die 3 "create_desktop_client: missing brand"

  log "creating OAuth client via iap.googleapis.com (displayName=${CLIENT_DISPLAY_NAME}) ..."
  # Capture body to a mode-600 temp file; never echo. Secret stays in python → oauth store.
  resp_file="$(mktemp)"
  chmod 600 "$resp_file"
  if ! curl -sS -X POST \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "x-goog-user-project: ${PROJECT_ID}" \
    -H "Content-Type: application/json" \
    "https://iap.googleapis.com/v1/${brand_name}/identityAwareProxyClients" \
    -d "$(python3 -c 'import json,sys; print(json.dumps({"displayName": sys.argv[1]}))' "$CLIENT_DISPLAY_NAME")" \
    >"$resp_file"
  then
    rm -f "$resp_file"
    die 3 "IAP OAuth client HTTP request failed"
  fi

  if ! python3 - "$OAUTH_JSON" "$PROJECT_ID" "$resp_file" <<'PY'
import json, os, sys
from pathlib import Path

oauth_path, project_id, resp_path = sys.argv[1], sys.argv[2], Path(sys.argv[3])
raw = resp_path.read_text(encoding="utf-8", errors="replace")
try:
    data = json.loads(raw) if raw else {}
except Exception:
    data = {}

# name: projects/{n}/brands/{n}/identityAwareProxyClients/{clientId}
name = data.get("name") or ""
cid = data.get("clientId") or data.get("client_id") or ""
if not cid and "/identityAwareProxyClients/" in name:
    cid = name.rsplit("/", 1)[-1]
sec = data.get("secret") or data.get("clientSecret") or data.get("client_secret") or ""

# Wipe response file before any failure path that might leave secrets on disk
try:
    resp_path.write_text("")
    resp_path.unlink()
except Exception:
    pass

if not cid or not sec:
    err = {k: data.get(k) for k in ("error", "message", "status", "code", "details") if k in data}
    # Never print raw body (may contain secret on partial parse)
    print(
        "iap client create failed: " + json.dumps(err or {"keys": list(data.keys())})[:500],
        file=sys.stderr,
    )
    raise SystemExit(1)

with open(oauth_path, "w", encoding="utf-8") as f:
    json.dump({"client_id": cid, "client_secret": sec, "project_id": project_id}, f)
os.chmod(oauth_path, 0o600)
print(f"OAuth client stored (client_id length={len(cid)}; secret not logged)", file=sys.stderr)
PY
  then
    rm -f "$resp_file"
    die 3 "IAP OAuth client create failed — need iap.identityAwareProxyClients.create (and brands). Do not paste secrets into chat; fix IAM and re-run."
  fi
  rm -f "$resp_file"
}

# Write rclone remote non-interactively (rclone config create can hang on macOS).
write_rclone_remote() {
  local cid="$1" sec="$2"
  python3 - "$RCLONE_REMOTE" "$cid" "$sec" <<'PY' || die 4 "rclone config write failed"
import configparser, os, sys
from pathlib import Path

remote, cid, sec = sys.argv[1], sys.argv[2], sys.argv[3]
conf_path = Path(os.environ.get("RCLONE_CONFIG") or Path.home() / ".config" / "rclone" / "rclone.conf")
conf_path.parent.mkdir(parents=True, exist_ok=True)

parser = configparser.RawConfigParser()
if conf_path.exists():
    parser.read(conf_path)

if not parser.has_section(remote):
    parser.add_section(remote)

parser.set(remote, "type", "drive")
parser.set(remote, "scope", "drive")
parser.set(remote, "client_id", cid)
parser.set(remote, "client_secret", sec)

with conf_path.open("w", encoding="utf-8") as f:
    parser.write(f)
os.chmod(conf_path, 0o600)
PY
}

verify_rclone_client_id() {
  # Do not pipe into `python3 -` with a heredoc — stdin cannot be both script and dump.
  python3 - "$RCLONE_REMOTE" <<'PY' || die 4 "rclone remote missing non-empty client_id after write"
import json, subprocess, sys
remote = sys.argv[1]
raw = subprocess.check_output(["rclone", "config", "dump"], text=True)
try:
    data = json.loads(raw)
except Exception:
    raise SystemExit(1)
section = data.get(remote) or data.get(remote + ":") or {}
cid = section.get("client_id") or ""
raise SystemExit(0 if cid else 1)
PY
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

# Clear secret from shell memory best-effort
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
