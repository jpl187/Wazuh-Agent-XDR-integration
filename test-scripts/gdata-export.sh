#!/usr/bin/env bash
set -euo pipefail

EXPORT_BASE="/var/log/gdata-export"
LOGROTATE_CONF="/etc/logrotate.d/gdata-export"
CURL_URL="${1:-https://example.com/api/export}"
TS="$(date +%Y%m%d%H%M%S)"
EXPORT_DIR="${EXPORT_BASE}/${TS}-gdata.export"

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
  pkg_install "$pkg" || die "installation of $pkg failed"
  command -v "$bin" &>/dev/null || die "$pkg installed but binary '$bin' still not in PATH"
}

need_root
check_or_install curl
check_or_install logrotate

mkdir -p "$EXPORT_DIR" || die "failed to create export dir $EXPORT_DIR (exit $?)"
chmod 750 "$EXPORT_DIR" || die "chmod failed on $EXPORT_DIR"

echo "[INFO] running curl -> $EXPORT_DIR/data.json"
curl -fsSL --max-time 30 "$CURL_URL" -o "${EXPORT_DIR}/data.json" \
  || die "curl exited $? for url '$CURL_URL'"

if [[ ! -s "${EXPORT_DIR}/data.json" ]]; then
  die "curl succeeded but output file is empty: ${EXPORT_DIR}/data.json"
fi

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

logrotate -d "$LOGROTATE_CONF" &>/dev/null \
  || die "logrotate config validation failed for $LOGROTATE_CONF"

echo "[OK] export written to $EXPORT_DIR/data.json"
echo "[OK] logrotate config -> $LOGROTATE_CONF"
