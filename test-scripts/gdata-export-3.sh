#!/usr/bin/env bash
set -euo pipefail

EXPORT_BASE="/var/log/gdata-export"
LOGROTATE_CONF="/etc/logrotate.d/gdata-export"
TOKEN_FILE="/etc/gdata-export/.token"
TS="$(date +%Y%m%d%H%M%S)"
EXPORT_DIR="${EXPORT_BASE}/${TS}-gdata.export"

# --- configuration ---
AUTH_URL="https://your-auth.example.com/oauth/token"
AUTH_HEADER="Content-Type: application/x-www-form-urlencoded"
GRANT_TYPE="client_credentials"
CLIENT_ID="your-client-id"
CLIENT_SECRET="your-client-secret"

EXPORT_URL="https://your-api.example.com/api/export"
EXPORT_HEADER="Accept: application/json"

die(){ echo "[FATAL] $*" >&2; exit 1; }
need_root(){ [[ $EUID -eq 0 ]] || die "must run as root (euid=$EUID)"; }
pkg_install(){
  local pkg="$1"
  if command -v apt-get &>/dev/null; then
    apt-get install -y "$pkg" &>/dev/null || die "apt-get failed to install $pkg (exit $?)"
  elif command -v dnf &>/dev/null; then
    dnf install -y "$pkg" &>/dev/null || die "dnf failed to install $pkg (exit $?)"
  elif command -v yum &>/dev/null; then
    yum install -y "$pkg" &>/dev/null || die "yum failed to install $pkg (exit $?)"
  else
    die "no supported package manager found (apt-get/dnf/yum)"
  fi
}
check_or_install(){
  local pkg="$1" bin="${2:-$1}"
  command -v "$bin" &>/dev/null && return 0
  echo "[INFO] $pkg not found, installing..."
  pkg_install "$pkg"
  command -v "$bin" &>/dev/null || die "$pkg installed but binary '$bin' still not in PATH"
}

need_root
check_or_install curl
check_or_install logrotate

echo "[INFO] authenticating -> $AUTH_URL"
mkdir -p "$(dirname "$TOKEN_FILE")" || die "failed to create token dir $(dirname "$TOKEN_FILE")"
chmod 700 "$(dirname "$TOKEN_FILE")"

AUTH_RESPONSE="$(curl --request POST "$AUTH_URL" \
  --header "$AUTH_HEADER" \
  --data "grant_type=${GRANT_TYPE}" \
  --data "client_id=${CLIENT_ID}" \
  --data "client_secret=${CLIENT_SECRET}" \
  --fail --silent --show-error --max-time 30
  )" || die "auth POST failed (curl exit $?) for $AUTH_URL"

[[ -z "$AUTH_RESPONSE" ]] && die "auth POST returned empty response from $AUTH_URL"

TOKEN="$(echo "$AUTH_RESPONSE" | grep -oP '(?<="access_token"\s*:\s*")[^"]+')" \
  || die "failed to parse access_token from auth response: ${AUTH_RESPONSE:0:200}"

[[ -z "$TOKEN" ]] && die "parsed token is empty — check AUTH_URL or response format. response: ${AUTH_RESPONSE:0:200}"

TMP_TOKEN="$(mktemp "$(dirname "$TOKEN_FILE")/.token.XXXXXX")"
echo "$TOKEN" > "$TMP_TOKEN"
chmod 600 "$TMP_TOKEN"
mv -f "$TMP_TOKEN" "$TOKEN_FILE" || die "failed to write token to $TOKEN_FILE"
echo "[INFO] token saved -> $TOKEN_FILE"

mkdir -p "$EXPORT_DIR" || die "failed to create export dir $EXPORT_DIR"
chmod 750 "$EXPORT_DIR"

echo "[INFO] fetching export -> $EXPORT_DIR/data.json"
curl --request GET "$EXPORT_URL" \
  --header "$EXPORT_HEADER" \
  --header "Authorization: Bearer ${TOKEN}" \
  --fail --silent --show-error --max-time 60 \
  --output "${EXPORT_DIR}/data.json" \
  || die "export GET failed (curl exit $?) for $EXPORT_URL"

[[ -s "${EXPORT_DIR}/data.json" ]] || die "export GET succeeded but output is empty: ${EXPORT_DIR}/data.json"

cat >"$LOGROTATE_CONF" <<EOF
${EXPORT_BASE}/*/*.json {
    daily
    rotate 30
    missingok
    notifempty
    compress
    delaycompress
    maxage 30
    dateext
    dateformat -%Y%m%d
    olddir ${EXPORT_BASE}/archived
    createolddir 750 root root
    sharedscripts
    postrotate
        find ${EXPORT_BASE} -maxdepth 1 -type d -name '*-gdata.export' \
             -mtime +30 -exec rm -rf {} + 2>/dev/null || true
    endscript
}
EOF
chmod 644 "$LOGROTATE_CONF" || die "chmod failed on $LOGROTATE_CONF"
logrotate -d "$LOGROTATE_CONF" &>/dev/null || die "logrotate config validation failed for $LOGROTATE_CONF"

echo "[OK] export written -> $EXPORT_DIR/data.json"
echo "[OK] token stored   -> $TOKEN_FILE"
echo "[OK] logrotate      -> $LOGROTATE_CONF"
