#!/usr/bin/env python3
"""gdata-export – authenticate, fetch export, configure logrotate."""

from __future__ import annotations

import os
import sys
import stat
import shutil
import subprocess
import tempfile
import json
from datetime import datetime
from pathlib import Path

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
EXPORT_BASE      = Path("/var/log/gdata-export")
LOGROTATE_CONF   = Path("/etc/logrotate.d/gdata-export")
TOKEN_FILE       = Path("/etc/gdata-export/.token")

TS               = datetime.now().strftime("%Y%m%d%H%M%S")
EXPORT_DIR       = EXPORT_BASE / f"{TS}-gdata.export"

AUTH_URL         = "https://your-auth.example.com/oauth/token"
GRANT_TYPE       = "client_credentials"
CLIENT_ID        = "your-client-id"
CLIENT_SECRET    = "your-client-secret"

EXPORT_URL       = "https://your-api.example.com/api/export"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def die(msg: str) -> None:
    print(f"[FATAL] {msg}", file=sys.stderr)
    sys.exit(1)


def need_root() -> None:
    if os.geteuid() != 0:
        die(f"must run as root (euid={os.geteuid()})")


def pkg_install(pkg: str) -> None:
    for mgr in ("apt-get", "dnf", "yum"):
        if shutil.which(mgr):
            result = subprocess.run(
                [mgr, "install", "-y", pkg],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            if result.returncode != 0:
                die(f"{mgr} failed to install {pkg} (exit {result.returncode})")
            return
    die("no supported package manager found (apt-get/dnf/yum)")


def check_or_install(pkg: str, binary: str | None = None) -> None:
    binary = binary or pkg
    if shutil.which(binary):
        return
    print(f"[INFO] {pkg} not found, installing...")
    pkg_install(pkg)
    if not shutil.which(binary):
        die(f"{pkg} installed but binary '{binary}' still not in PATH")


# ---------------------------------------------------------------------------
# Step 0 – pre-flight
# ---------------------------------------------------------------------------
need_root()
check_or_install("curl")
check_or_install("logrotate")

# ---------------------------------------------------------------------------
# Step 1 – authenticate and obtain token
# ---------------------------------------------------------------------------
print(f"[INFO] authenticating -> {AUTH_URL}")

token_dir = TOKEN_FILE.parent
token_dir.mkdir(parents=True, exist_ok=True)
token_dir.chmod(0o700)

try:
    import urllib.request
    import urllib.parse
    import urllib.error

    auth_payload = urllib.parse.urlencode({
        "grant_type":    GRANT_TYPE,
        "client_id":     CLIENT_ID,
        "client_secret": CLIENT_SECRET,
    }).encode()

    auth_req = urllib.request.Request(
        AUTH_URL,
        data=auth_payload,
        method="POST",
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )

    with urllib.request.urlopen(auth_req, timeout=30) as resp:
        auth_body = resp.read().decode()

except urllib.error.URLError as exc:
    die(f"auth POST failed for {AUTH_URL}: {exc}")

if not auth_body:
    die(f"auth POST returned empty response from {AUTH_URL}")

try:
    auth_json = json.loads(auth_body)
    TOKEN: str = auth_json["access_token"]
except (json.JSONDecodeError, KeyError):
    die(
        f"failed to parse access_token from auth response: "
        f"{auth_body[:200]}"
    )

if not TOKEN:
    die(
        f"parsed token is empty — check AUTH_URL or response format. "
        f"response: {auth_body[:200]}"
    )

# Write token atomically with restricted permissions
tmp_fd, tmp_path_str = tempfile.mkstemp(dir=token_dir, prefix=".token.")
tmp_path = Path(tmp_path_str)
try:
    os.write(tmp_fd, TOKEN.encode())
finally:
    os.close(tmp_fd)

tmp_path.chmod(0o600)
tmp_path.replace(TOKEN_FILE)
print(f"[INFO] token saved -> {TOKEN_FILE}")

# ---------------------------------------------------------------------------
# Step 2 – create export directory and fetch data
# ---------------------------------------------------------------------------
EXPORT_DIR.mkdir(parents=True, exist_ok=True)
EXPORT_DIR.chmod(0o750)

output_file = EXPORT_DIR / "data.json"
print(f"[INFO] fetching export -> {output_file}")

export_req = urllib.request.Request(
    EXPORT_URL,
    method="GET",
    headers={
        "Accept":        "application/json",
        "Authorization": f"Bearer {TOKEN}",
    },
)

try:
    with urllib.request.urlopen(export_req, timeout=60) as resp:
        export_body = resp.read()
except urllib.error.URLError as exc:
    die(f"export GET failed for {EXPORT_URL}: {exc}")

if not export_body:
    die(f"export GET succeeded but output is empty: {output_file}")

output_file.write_bytes(export_body)

# ---------------------------------------------------------------------------
# Step 3 – write and validate logrotate configuration
# ---------------------------------------------------------------------------
logrotate_content = f"""{EXPORT_BASE}/*/*.json {{
    daily
    rotate 30
    missingok
    notifempty
    compress
    delaycompress
    maxage 30
    dateext
    dateformat -%Y%m%d
    olddir {EXPORT_BASE}/archived
    createolddir 750 root root
    sharedscripts
    postrotate
        find {EXPORT_BASE} -maxdepth 1 -type d -name '*-gdata.export' \\
             -mtime +30 -exec rm -rf {{}} + 2>/dev/null || true
    endscript
}}
"""

LOGROTATE_CONF.write_text(logrotate_content)
LOGROTATE_CONF.chmod(0o644)

result = subprocess.run(
    ["logrotate", "-d", str(LOGROTATE_CONF)],
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
)
if result.returncode != 0:
    die(f"logrotate config validation failed for {LOGROTATE_CONF}")

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
print(f"[OK] export written -> {output_file}")
print(f"[OK] token stored   -> {TOKEN_FILE}")
print(f"[OK] logrotate      -> {LOGROTATE_CONF}")
