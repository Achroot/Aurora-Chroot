chroot_service_builtin_pcbridge_script_content() {
  cat <<'EOF_PCBRIDGE'
#!/bin/sh
set -eu

RUNDIR="/run/aurora-pcbridge"
STORE_DIR="/etc/aurora-pcbridge"
STATE_JSON="$STORE_DIR/state.json"
TOKEN_FILE="$STORE_DIR/token"
KEYS_FILE="$STORE_DIR/authorized_keys"
SSHD_LOG="$STORE_DIR/sshd.log"
HTTP_LOG="$STORE_DIR/http.log"
WARN_LOG="$STORE_DIR/warnings.log"
TOKEN_EVENT_FILE="$STORE_DIR/token_event"
TOKEN_CONTROL_FILE="$STORE_DIR/token_control"
HOSTKEY_DIR="$STORE_DIR/hostkeys"
HOSTKEY_ED25519="$HOSTKEY_DIR/ssh_host_ed25519_key"
HOSTKEY_RSA="$HOSTKEY_DIR/ssh_host_rsa_key"
SSH_PORT="${AURORA_PCBRIDGE_SSH_PORT:-2223}"
HTTP_PORT="${AURORA_PCBRIDGE_HTTP_PORT:-47077}"
TOKEN_TTL="${AURORA_PCBRIDGE_TOKEN_TTL_SEC:-900}"
PAIRING_FLAG="${AURORA_PCBRIDGE_PAIRING:-0}"
PAIRING_ENABLED=0
HTTP_CHILD=""

is_uint() {
  case "${1:-}" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

validate_u16_port() {
  local label="$1"
  local value="$2"
  if ! is_uint "$value" || [ "$value" -lt 1 ] || [ "$value" -gt 65535 ]; then
    echo "pcbridge: invalid $label '$value' (expected 1..65535)." >&2
    exit 1
  fi
}

validate_token_ttl() {
  local value="$1"
  if ! is_uint "$value" || [ "$value" -lt 1 ] || [ "$value" -gt 86400 ]; then
    echo "pcbridge: invalid AURORA_PCBRIDGE_TOKEN_TTL_SEC '$value' (expected 1..86400)." >&2
    exit 1
  fi
}

generate_secure_token() {
  local token="" py_bin=""
  if command -v openssl >/dev/null 2>&1; then
    token="$(openssl rand -hex 16 2>/dev/null || true)"
    case "$token" in
      ''|*[!0-9a-fA-F]*) ;;
      *)
        if [ "${#token}" -eq 32 ]; then
          printf '%s\n' "$(printf '%s' "$token" | tr 'A-F' 'a-f')"
          return 0
        fi
        ;;
    esac
  fi

  py_bin="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)"
  if [ -n "$py_bin" ]; then
    token="$("$py_bin" - <<'PY_TOKEN' 2>/dev/null || true
import secrets
print(secrets.token_hex(16))
PY_TOKEN
)"
    case "$token" in
      ''|*[!0-9a-fA-F]*) ;;
      *)
        if [ "${#token}" -eq 32 ]; then
          printf '%s\n' "$(printf '%s' "$token" | tr 'A-F' 'a-f')"
          return 0
        fi
        ;;
    esac
  fi

  if command -v od >/dev/null 2>&1; then
    token="$(dd if=/dev/urandom bs=16 count=1 2>/dev/null | od -An -tx1 -v 2>/dev/null | tr -d ' \n' || true)"
    case "$token" in
      ''|*[!0-9a-fA-F]*) ;;
      *)
        if [ "${#token}" -ge 32 ]; then
          printf '%s\n' "$(printf '%s' "$token" | cut -c1-32 | tr 'A-F' 'a-f')"
          return 0
        fi
        ;;
    esac
  fi

  return 1
}

case "$PAIRING_FLAG" in
  1|true|TRUE|yes|YES|on|ON)
    PAIRING_ENABLED=1
    ;;
esac

validate_u16_port "AURORA_PCBRIDGE_SSH_PORT" "$SSH_PORT"
validate_u16_port "AURORA_PCBRIDGE_HTTP_PORT" "$HTTP_PORT"
validate_token_ttl "$TOKEN_TTL"
if [ "$PAIRING_ENABLED" = "1" ] && [ "$SSH_PORT" -eq "$HTTP_PORT" ]; then
  echo "pcbridge: SSH and HTTP ports must differ in pairing mode." >&2
  exit 1
fi

umask 077
mkdir -p "$RUNDIR" "$STORE_DIR" "$HOSTKEY_DIR"
chmod 700 "$RUNDIR" "$STORE_DIR" "$HOSTKEY_DIR"
touch "$KEYS_FILE"
chmod 600 "$KEYS_FILE"
rm -f -- "$TOKEN_FILE" "$TOKEN_EVENT_FILE" "$TOKEN_CONTROL_FILE" 2>/dev/null || true

log_warn() {
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)"
  printf '%s %s\n' "$ts" "$1" >>"$WARN_LOG"
  chmod 600 "$WARN_LOG" >/dev/null 2>&1 || true
}

TOKEN=""
if [ "$PAIRING_ENABLED" = "1" ]; then
  TOKEN="$(generate_secure_token || true)"
  if [ -z "$TOKEN" ]; then
    echo "pcbridge: failed to generate secure pairing token." >&2
    exit 1
  fi
  printf '%s\n' "$TOKEN" >"$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
fi

SYSTEM_HOSTKEYS_MISSING=false
if ! ls /etc/ssh/ssh_host_*_key >/dev/null 2>&1; then
  SYSTEM_HOSTKEYS_MISSING=true
  log_warn "pcbridge: system ssh host keys missing at /etc/ssh/ssh_host_*_key; using dedicated pcbridge keys only."
fi

if ! command -v ssh-keygen >/dev/null 2>&1; then
  echo "pcbridge: ssh-keygen not found inside distro." >&2
  exit 1
fi

if [ ! -s "$HOSTKEY_ED25519" ]; then
  rm -f -- "$HOSTKEY_ED25519" "$HOSTKEY_ED25519.pub" 2>/dev/null || true
  if ! ssh-keygen -q -t ed25519 -N "" -f "$HOSTKEY_ED25519" >/dev/null 2>&1; then
    echo "pcbridge: failed to generate dedicated ed25519 host key." >&2
    exit 1
  fi
fi

if [ ! -s "$HOSTKEY_RSA" ]; then
  rm -f -- "$HOSTKEY_RSA" "$HOSTKEY_RSA.pub" 2>/dev/null || true
  if ! ssh-keygen -q -t rsa -b 3072 -N "" -f "$HOSTKEY_RSA" >/dev/null 2>&1; then
    echo "pcbridge: failed to generate dedicated rsa host key." >&2
    exit 1
  fi
fi
chmod 600 "$HOSTKEY_ED25519" "$HOSTKEY_RSA"
chmod 644 "$HOSTKEY_ED25519.pub" "$HOSTKEY_RSA.pub" 2>/dev/null || true
HOSTKEY_ED25519_PUB="$(awk 'NF && $1=="ssh-ed25519" {print $2; exit}' "$HOSTKEY_ED25519.pub" 2>/dev/null || true)"
HOSTKEY_RSA_PUB="$(awk 'NF && $1=="ssh-rsa" {print $2; exit}' "$HOSTKEY_RSA.pub" 2>/dev/null || true)"
if [ -z "$HOSTKEY_ED25519_PUB" ] && [ -z "$HOSTKEY_RSA_PUB" ]; then
  echo "pcbridge: failed reading dedicated host public keys." >&2
  exit 1
fi

SSHD_BIN="$(command -v sshd 2>/dev/null || true)"
if [ -z "$SSHD_BIN" ]; then
  echo "pcbridge: sshd not found inside distro. Install openssh first." >&2
  exit 1
fi

SSHD_CFG="$RUNDIR/sshd_config"
cat >"$SSHD_CFG" <<EOF_CFG
Port $SSH_PORT
ListenAddress 0.0.0.0
HostKey $HOSTKEY_ED25519
HostKey $HOSTKEY_RSA
PermitRootLogin prohibit-password
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile $KEYS_FILE
PidFile $RUNDIR/sshd.pid
UsePAM no
Subsystem sftp internal-sftp
AllowTcpForwarding no
X11Forwarding no
PrintMotd no
ClientAliveInterval 30
ClientAliveCountMax 3
EOF_CFG

if [ "$PAIRING_ENABLED" != "1" ]; then
  if ! awk '
    /^[[:space:]]*$/ {next}
    /^[[:space:]]*ssh-(ed25519|rsa)[[:space:]]+[A-Za-z0-9+\/=]+([[:space:]].*)?$/ {ok=1; exit}
    END {exit ok ? 0 : 1}
  ' "$KEYS_FILE" >/dev/null 2>&1; then
    echo "pcbridge: no paired PC key found in $KEYS_FILE." >&2
    echo "pcbridge: start or restart pcbridge and choose [f] first-run setup to pair a PC first." >&2
    exit 1
  fi
fi

"$SSHD_BIN" -D -e -f "$SSHD_CFG" >"$SSHD_LOG" 2>&1 &
SSHD_CHILD="$!"

if [ "$PAIRING_ENABLED" = "1" ]; then
  PYTHON_BIN="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)"
  if [ -z "$PYTHON_BIN" ]; then
    echo "pcbridge: python3 not found inside distro." >&2
    kill "$SSHD_CHILD" >/dev/null 2>&1 || true
    exit 1
  fi

  "$PYTHON_BIN" - "$TOKEN" "$HTTP_PORT" "$TOKEN_TTL" "$SSH_PORT" "$KEYS_FILE" "$TOKEN_EVENT_FILE" "$TOKEN_CONTROL_FILE" "$HOSTKEY_ED25519_PUB" "$HOSTKEY_RSA_PUB" <<'PY_SERVER' >"$HTTP_LOG" 2>&1 &
import http.server
import json
import os
import posixpath
import re
import stat
import threading
import time
import urllib.parse
import sys

token, http_port, token_ttl, ssh_port, keys_file, token_event_file, token_control_file, hostkey_ed25519_pub, hostkey_rsa_pub = sys.argv[1:10]
http_port = int(http_port)
token_ttl = int(token_ttl)
ssh_port = int(ssh_port)
started_at = time.time()
started_at_iso = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(started_at))
token_paired = False
bootstrap_command_consumed = False
cleanup_command_consumed = False
lock = threading.Lock()
MAX_PAIR_KEY_BYTES = 16384

CLIENT_PY = r'''#!/usr/bin/env python3
import argparse
import curses
import json
import os
import posixpath
import shutil
import stat
import subprocess
import tempfile
import time
import threading
from pathlib import Path

import paramiko


def human_size(num):
    units = ["B", "KB", "MB", "GB", "TB"]
    value = float(num)
    for unit in units:
        if value < 1024 or unit == units[-1]:
            return f"{value:.1f}{unit}" if unit != "B" else f"{int(value)}B"
        value /= 1024.0
    return f"{int(num)}B"


def load_config(path):
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    if not isinstance(data, dict):
        raise ValueError("invalid config format")
    return data


def truncate_middle(text, max_len):
    text = str(text)
    if max_len <= 0:
        return ""
    if len(text) <= max_len:
        return text
    if max_len <= 4:
        return text[:max_len]
    half = (max_len - 3) // 2
    return text[:half] + "..." + text[-(max_len - 3 - half):]


def remote_join(base, name):
    base = base or "/"
    if base == "/":
        return "/" + name
    return posixpath.join(base, name)


def detect_wsl_desktop():
    if not os.environ.get("WSL_DISTRO_NAME"):
        return None
    users_root = Path("/mnt/c/Users")
    if not users_root.is_dir():
        return None

    wanted = (os.environ.get("USERNAME") or os.environ.get("USER") or "").strip()
    if wanted:
        direct = users_root / wanted / "Desktop"
        if direct.is_dir():
            return str(direct)
        for entry in users_root.iterdir():
            if entry.name.lower() == wanted.lower():
                cand = entry / "Desktop"
                if cand.is_dir():
                    return str(cand)

    skip = {"public", "default", "default user", "all users"}
    for entry in users_root.iterdir():
        if entry.name.lower() in skip:
            continue
        cand = entry / "Desktop"
        if cand.is_dir():
            return str(cand)
    return None


class BridgeUI:
    def __init__(self, stdscr, sftp, cfg):
        self.stdscr = stdscr
        self.sftp = sftp
        self.cfg = cfg
        configured_local = str(cfg.get("local_root", "") or "").strip()
        wsl_desktop = detect_wsl_desktop()
        if configured_local:
            self.local_cwd = Path(configured_local).expanduser()
        else:
            self.local_cwd = Path(wsl_desktop) if wsl_desktop else Path.home()
        if wsl_desktop and str(self.local_cwd) == str(Path.home()):
            self.local_cwd = Path(wsl_desktop)
        if not self.local_cwd.exists():
            self.local_cwd = Path(wsl_desktop) if wsl_desktop and Path(wsl_desktop).exists() else Path.home()
        self.remote_cwd = str(cfg.get("remote_root", "/storage")).strip() or "/storage"
        self.active = "remote"

        self.local_entries = []
        self.remote_entries = []
        self.local_index = 0
        self.remote_index = 0
        self.local_scroll = 0
        self.remote_scroll = 0

        self.status = "Ready"
        self.status_kind = "info"
        self.delete_armed = None
        self.clipboard = None
        self.open_cache_dir = Path(tempfile.gettempdir()) / "aurorafs-open"
        self.open_cache_dir.mkdir(parents=True, exist_ok=True)
        self.selected_local = {}
        self.selected_remote = {}

        self.local_box = None
        self.remote_box = None
        self.local_row_map = {}
        self.remote_row_map = {}

        self.menu = None
        self.operation_thread = None
        self.operation_result = None
        self.operation_label = ""
        self.operation_started_at = 0.0

        curses.curs_set(0)
        curses.noecho()
        curses.cbreak()
        self.stdscr.keypad(True)
        try:
            curses.mousemask(curses.ALL_MOUSE_EVENTS | curses.REPORT_MOUSE_POSITION)
            curses.mouseinterval(0)
        except Exception:
            pass
        if curses.has_colors():
            curses.start_color()
            curses.use_default_colors()
            curses.init_pair(1, curses.COLOR_CYAN, -1)
            curses.init_pair(2, curses.COLOR_BLACK, curses.COLOR_WHITE)
            curses.init_pair(3, curses.COLOR_YELLOW, -1)
            curses.init_pair(4, curses.COLOR_GREEN, -1)
            curses.init_pair(5, curses.COLOR_RED, -1)
            curses.init_pair(6, curses.COLOR_MAGENTA, -1)

        self.refresh_all()

    def color(self, pair, fallback=0):
        if curses.has_colors():
            return curses.color_pair(pair) | fallback
        return fallback

    def set_status(self, text, kind="info"):
        self.status = str(text).strip()[:300]
        self.status_kind = kind

    def operation_active(self):
        return self.operation_thread is not None

    def operation_progress(self, ctx, current="", files_inc=0, bytes_inc=0, item_done=False, force=False):
        if files_inc:
            ctx["files"] += int(files_inc)
        if bytes_inc > 0:
            ctx["bytes"] += int(bytes_inc)
        if item_done:
            ctx["done"] += 1
        if current:
            ctx["current"] = str(current)
        now = time.time()
        if not force and (now - ctx["last_emit"]) < 0.12:
            return
        ctx["last_emit"] = now
        msg = f"{ctx['label']}: items {ctx['done']}/{ctx['total']} files {ctx['files']} bytes {human_size(ctx['bytes'])}"
        cur = str(ctx.get("current", "") or "")
        if cur:
            msg = f"{msg} | {truncate_middle(cur, 70)}"
        self.set_status(msg, "warn")

    def start_background_operation(self, label, worker):
        if self.operation_active():
            self.set_status("Another operation is still running.", "warn")
            return False
        self.operation_label = str(label)
        self.operation_started_at = time.time()
        self.operation_result = None
        self.set_status(f"{self.operation_label}: starting...", "warn")

        def runner():
            try:
                payload = worker()
                self.operation_result = {"ok": True, "payload": payload}
            except Exception as exc:
                self.operation_result = {"ok": False, "error": str(exc)}

        self.operation_thread = threading.Thread(target=runner, daemon=True)
        self.operation_thread.start()
        return True

    def poll_background_operation(self):
        thread = self.operation_thread
        if not thread:
            return
        if thread.is_alive():
            return
        self.operation_thread = None
        result = self.operation_result or {"ok": False, "error": "operation ended without result"}
        self.operation_result = None
        if not result.get("ok"):
            self.delete_armed = None
            self.set_status(f"{self.operation_label} failed: {result.get('error', 'unknown error')}", "error")
            return

        payload = result.get("payload") or {}
        kind = payload.get("kind", "")
        if kind == "paste":
            if payload.get("clear_clipboard"):
                self.clipboard = None
                src_side = payload.get("src_side")
                if src_side in ("local", "remote"):
                    self.clear_selection(src_side)
            self.refresh_all()
            self.set_status(
                f"{payload.get('mode', 'copy').title()} complete: {int(payload.get('done', 0))} item(s) "
                f"{payload.get('src_side', '?')} -> {payload.get('dst_side', '?')}",
                "ok",
            )
            return
        if kind == "delete":
            self.delete_armed = None
            side = payload.get("side")
            if side in ("local", "remote"):
                self.clear_selection(side)
            self.refresh_all()
            self.set_status(f"Deleted {int(payload.get('count', 0))} item(s).", "ok")
            return
        if kind == "open":
            target = payload.get("target", "")
            if payload.get("opened"):
                self.set_status(f"Opened: {target}", "ok")
            else:
                self.set_status("Could not open file with default app.", "error")
            return
        self.set_status(f"{self.operation_label} complete.", "ok")

    def safe_add(self, y, x, text, attr=0):
        h, w = self.stdscr.getmaxyx()
        if y < 0 or y >= h or x >= w:
            return
        max_len = max(0, w - x - 1)
        if max_len <= 0:
            return
        self.stdscr.addnstr(y, x, text, max_len, attr)

    def draw_frame(self, x, y, w, h, title, active=False):
        if w < 4 or h < 4:
            return
        attr = self.color(1, curses.A_BOLD) if active else self.color(6)
        self.safe_add(y, x, "+" + "-" * (w - 2) + "+", attr)
        for row in range(y + 1, y + h - 1):
            self.safe_add(row, x, "|", attr)
            self.safe_add(row, x + w - 1, "|", attr)
        self.safe_add(y + h - 1, x, "+" + "-" * (w - 2) + "+", attr)
        label = f" {title} "
        self.safe_add(y, x + 2, truncate_middle(label, w - 4), attr)

    def local_parent(self):
        parent = self.local_cwd.parent
        return parent if parent != self.local_cwd else self.local_cwd

    def remote_parent(self):
        cur = self.remote_cwd.rstrip("/") or "/"
        if cur == "/":
            return "/"
        return posixpath.dirname(cur) or "/"

    def list_local(self):
        rows = []
        if self.local_cwd != self.local_parent():
            rows.append({"name": "..", "path": str(self.local_parent()), "is_dir": True, "size": 0, "special": True})
        items = []
        for entry in self.local_cwd.iterdir():
            try:
                st = entry.stat()
                is_dir = entry.is_dir()
                items.append((not is_dir, entry.name.lower(), {"name": entry.name, "path": str(entry), "is_dir": is_dir, "size": st.st_size, "special": False}))
            except Exception:
                continue
        for _, _, row in sorted(items, key=lambda x: (x[0], x[1])):
            rows.append(row)
        self.local_entries = rows
        self.local_index = min(max(self.local_index, 0), max(0, len(rows) - 1))

    def list_remote(self):
        rows = []
        if self.remote_cwd.rstrip("/") != "":
            if self.remote_cwd != "/":
                rows.append({"name": "..", "path": self.remote_parent(), "is_dir": True, "size": 0, "special": True})
        items = []
        try:
            listing = self.sftp.listdir_attr(self.remote_cwd)
        except Exception:
            if self.remote_cwd != "/storage":
                self.remote_cwd = "/storage"
                listing = self.sftp.listdir_attr(self.remote_cwd)
            else:
                listing = []
        for attr in listing:
            name = attr.filename
            is_dir = stat.S_ISDIR(attr.st_mode)
            path = remote_join(self.remote_cwd, name)
            items.append((not is_dir, name.lower(), {"name": name, "path": path, "is_dir": is_dir, "size": int(getattr(attr, "st_size", 0)), "special": False}))
        for _, _, row in sorted(items, key=lambda x: (x[0], x[1])):
            rows.append(row)
        self.remote_entries = rows
        self.remote_index = min(max(self.remote_index, 0), max(0, len(rows) - 1))

    def refresh_all(self):
        try:
            self.list_local()
        except Exception as exc:
            self.set_status(f"Local refresh failed: {exc}", "error")
        try:
            self.list_remote()
        except Exception as exc:
            self.set_status(f"Remote refresh failed: {exc}", "error")

    def entries_of(self, side):
        return self.local_entries if side == "local" else self.remote_entries

    def index_of(self, side):
        return self.local_index if side == "local" else self.remote_index

    def set_index(self, side, idx):
        if side == "local":
            self.local_index = idx
        else:
            self.remote_index = idx
        self.delete_armed = None

    def scroll_of(self, side):
        return self.local_scroll if side == "local" else self.remote_scroll

    def set_scroll(self, side, value):
        if side == "local":
            self.local_scroll = max(0, int(value))
        else:
            self.remote_scroll = max(0, int(value))

    def selected_of(self, side):
        entries = self.entries_of(side)
        idx = self.index_of(side)
        if not entries:
            return None
        if idx < 0 or idx >= len(entries):
            return None
        return entries[idx]

    def selected(self):
        return self.selected_of(self.active)

    def selected_map(self, side):
        return self.selected_local if side == "local" else self.selected_remote

    def clear_selection(self, side=None):
        if side is None:
            self.selected_local = {}
            self.selected_remote = {}
            return
        if side == "local":
            self.selected_local = {}
        else:
            self.selected_remote = {}

    def normalize_pick(self, row):
        return {
            "path": str(row.get("path", "")),
            "name": str(row.get("name", "")),
            "is_dir": bool(row.get("is_dir", False)),
        }

    def norm_path(self, side, path):
        p = str(path or "")
        if side == "remote":
            p = p.rstrip("/")
            return p or "/"
        p = p.rstrip("/\\")
        return p or p

    def is_row_selected(self, side, row):
        row_path = self.norm_path(side, row.get("path", ""))
        return row_path in self.selected_map(side)

    def toggle_select_row(self, side, row):
        if not row:
            return
        if row.get("name") == "..":
            return
        picks = self.selected_map(side)
        key = self.norm_path(side, row.get("path", ""))
        if key in picks:
            del picks[key]
            self.set_status(f"Unselected: {row.get('name', '')}", "ok")
        else:
            picks[key] = self.normalize_pick(row)
            self.set_status(f"Selected: {row.get('name', '')}", "ok")
        self.delete_armed = None

    def toggle_select_current(self):
        row = self.selected()
        if not row:
            return
        self.toggle_select_row(self.active, row)

    def collapse_items(self, side, items):
        out = []
        seen = set()
        for row in items:
            if row.get("name") == "..":
                continue
            key = self.norm_path(side, row.get("path", ""))
            if not key or key in seen:
                continue
            seen.add(key)
            out.append(self.normalize_pick(row))

        out.sort(key=lambda r: len(self.norm_path(side, r.get("path", ""))))
        kept = []
        for row in out:
            p = self.norm_path(side, row.get("path", ""))
            nested = False
            for k in kept:
                kp = self.norm_path(side, k.get("path", ""))
                if side == "remote":
                    if p == kp or (kp != "/" and p.startswith(kp + "/")):
                        nested = True
                        break
                else:
                    if p == kp or p.startswith(kp.rstrip("/") + "/"):
                        nested = True
                        break
            if not nested:
                kept.append(row)
        return kept

    def selected_or_current_items(self, side):
        picks = list(self.selected_map(side).values())
        if picks:
            return self.collapse_items(side, picks)
        row = self.selected_of(side)
        if not row or row.get("name") == "..":
            return []
        return self.collapse_items(side, [row])

    def ensure_visible(self, side, rows_cap):
        rows_cap = max(1, rows_cap)
        idx = self.index_of(side)
        scroll = self.scroll_of(side)
        if idx < scroll:
            scroll = idx
        if idx >= scroll + rows_cap:
            scroll = idx - rows_cap + 1
        self.set_scroll(side, scroll)

    def draw_pane(self, side, x, y, w, h):
        if w < 25 or h < 8:
            return

        entries = self.entries_of(side)
        idx = self.index_of(side)
        active = side == self.active
        cwd = str(self.local_cwd) if side == "local" else self.remote_cwd
        title = "LOCAL" if side == "local" else "PHONE"
        self.draw_frame(x, y, w, h, title, active=active)

        path_line = truncate_middle(cwd, w - 4)
        self.safe_add(y + 1, x + 2, path_line, self.color(3))

        first_row = y + 2
        last_row = y + h - 2
        rows_cap = max(1, last_row - first_row + 1)
        self.ensure_visible(side, rows_cap)
        scroll = self.scroll_of(side)
        visible = entries[scroll:scroll + rows_cap]

        row_map = {}
        for i, row in enumerate(visible):
            row_y = first_row + i
            real_idx = scroll + i
            row_map[row_y] = real_idx

            icon = "DIR" if row["is_dir"] else "FILE"
            if row["name"] == "..":
                icon = "UP"
            selected_flag = self.is_row_selected(side, row)
            marker = ">" if real_idx == idx else ("*" if selected_flag else " ")
            size = "-" if row["is_dir"] else human_size(row["size"])
            name = row["name"] + ("/" if row["is_dir"] and row["name"] != ".." else "")
            line = f"{marker} {icon:<4} {size:>9}  {name}"
            attr = 0
            if real_idx == idx:
                attr = self.color(2, curses.A_BOLD if active else 0)
            elif row["is_dir"]:
                attr = self.color(4)
            if selected_flag:
                attr |= self.color(3, curses.A_BOLD)
            if self.clipboard:
                for item in self.clipboard.get("items", []):
                    if self.norm_path(side, item.get("path", "")) == self.norm_path(side, row.get("path", "")):
                        attr |= curses.A_UNDERLINE
                        break
            self.safe_add(row_y, x + 1, " " * (w - 2), 0)
            self.safe_add(row_y, x + 1, truncate_middle(line, w - 3), attr)

        if side == "local":
            self.local_row_map = row_map
            self.local_box = (x, y, w, h)
        else:
            self.remote_row_map = row_map
            self.remote_box = (x, y, w, h)

    def draw_status_lines(self, h, w):
        clip = "clipboard: <empty>"
        if self.clipboard:
            mode = self.clipboard.get("mode", "copy")
            side = self.clipboard.get("side", "?").upper()
            count = len(self.clipboard.get("items", []))
            clip = f"clipboard: {mode} {side} items={count}"
        selected = f"selected local={len(self.selected_local)} remote={len(self.selected_remote)}"
        self.safe_add(h - 3, 0, " " * max(0, w - 1), self.color(6))
        self.safe_add(h - 3, 1, truncate_middle(f"{clip} | {selected}", w - 3), self.color(6))

        status_attr = self.color(1)
        if self.status_kind == "error":
            status_attr = self.color(5, curses.A_BOLD)
        elif self.status_kind == "warn":
            status_attr = self.color(3, curses.A_BOLD)
        elif self.status_kind == "ok":
            status_attr = self.color(4, curses.A_BOLD)
        self.safe_add(h - 2, 0, " " * max(0, w - 1), status_attr)
        self.safe_add(h - 2, 1, truncate_middle(self.status, w - 3), status_attr)

        help_text = "Tab switch | Arrows move | Enter open | Space select | Ctrl+click select | c copy | m move | p paste | d delete | r refresh | q quit"
        self.safe_add(h - 1, 0, " " * max(0, w - 1), self.color(3))
        self.safe_add(h - 1, 1, truncate_middle(help_text, w - 3), self.color(3))

    def draw_menu(self):
        if not self.menu or not self.menu.get("visible"):
            return
        items = self.menu.get("items", [])
        if not items:
            return

        h, w = self.stdscr.getmaxyx()
        mw = max(len(label) for _, label in items) + 4
        mh = len(items) + 2
        mx = int(self.menu.get("x", 2))
        my = int(self.menu.get("y", 2))
        if mx + mw >= w:
            mx = max(1, w - mw - 1)
        if my + mh >= h:
            my = max(1, h - mh - 2)
        self.menu["x"] = mx
        self.menu["y"] = my
        self.menu["w"] = mw
        self.menu["h"] = mh

        self.draw_frame(mx, my, mw, mh, "ACTIONS", active=True)
        sel = int(self.menu.get("selected", 0))
        for i, (_, label) in enumerate(items):
            attr = self.color(2, curses.A_BOLD) if i == sel else self.color(1)
            self.safe_add(my + 1 + i, mx + 1, " " * (mw - 2), 0)
            self.safe_add(my + 1 + i, mx + 2, truncate_middle(label, mw - 4), attr)

    def draw(self):
        self.stdscr.erase()
        h, w = self.stdscr.getmaxyx()
        if h < 16 or w < 90:
            self.safe_add(1, 2, "aurorafs", self.color(1, curses.A_BOLD))
            self.safe_add(3, 2, "Terminal too small for UI.", self.color(5, curses.A_BOLD))
            self.safe_add(4, 2, "Resize and try again.")
            self.stdscr.refresh()
            return

        host = self.cfg.get("host", "<host>")
        port = self.cfg.get("ssh_port", 0)
        hdr = f"AURORAFS  host={host}:{port}  active={self.active.upper()}"
        self.safe_add(0, 0, " " * (w - 1), self.color(1))
        self.safe_add(0, 1, truncate_middle(hdr, w - 3), self.color(1, curses.A_BOLD))
        self.safe_add(1, 0, " " * (w - 1), self.color(6))
        self.safe_add(1, 1, "Mouse: left=open | right=actions | Ctrl+left=multi-select", self.color(6))

        pane_top = 2
        pane_h = h - 5
        split = w // 2
        local_w = split
        remote_w = w - split
        self.draw_pane("local", 0, pane_top, local_w, pane_h)
        self.draw_pane("remote", split, pane_top, remote_w, pane_h)

        self.draw_status_lines(h, w)
        self.draw_menu()
        self.stdscr.refresh()

    def remote_exists(self, path, follow_symlinks=True):
        try:
            if follow_symlinks:
                self.sftp.stat(path)
            else:
                self.sftp.lstat(path)
            return True
        except Exception:
            return False

    def remote_lstat(self, path):
        return self.sftp.lstat(path)

    def remote_is_symlink(self, path):
        try:
            return stat.S_ISLNK(self.remote_lstat(path).st_mode)
        except Exception:
            return False

    def remote_is_dir(self, path, follow_symlinks=False):
        st = self.sftp.stat(path) if follow_symlinks else self.remote_lstat(path)
        return stat.S_ISDIR(st.st_mode)

    def remote_mkdir_p(self, path, cache=None):
        path = path.rstrip("/") or "/"
        if path == "/":
            return
        if cache is not None:
            cache.add("/")
        parts = [p for p in path.split("/") if p]
        cur = ""
        for part in parts:
            cur = f"{cur}/{part}" if cur else f"/{part}"
            if cache is not None and cur in cache:
                continue
            try:
                self.sftp.stat(cur)
                if cache is not None:
                    cache.add(cur)
            except FileNotFoundError:
                self.sftp.mkdir(cur)
                if cache is not None:
                    cache.add(cur)
            except IOError:
                try:
                    self.sftp.mkdir(cur)
                    if cache is not None:
                        cache.add(cur)
                except Exception:
                    pass

    def local_unique_target(self, base_dir, name, avoid_path=None):
        base = Path(base_dir) / name
        try:
            if avoid_path and Path(avoid_path).resolve() == base.resolve():
                pass
            elif not base.exists():
                return base
        except Exception:
            if not base.exists():
                return base
        stem = Path(name).stem
        suffix = Path(name).suffix
        for i in range(2, 1000):
            cand = Path(base_dir) / f"{stem} ({i}){suffix}"
            if not cand.exists():
                return cand
        return base

    def remote_unique_target(self, base_dir, name, avoid_path=None):
        base = remote_join(base_dir, name)
        if not self.remote_exists(base) or (avoid_path and base == avoid_path):
            return base
        stem, suffix = os.path.splitext(name)
        for i in range(2, 1000):
            cand = remote_join(base_dir, f"{stem} ({i}){suffix}")
            if not self.remote_exists(cand):
                return cand
        return base

    def copy_local_to_remote(self, src, dst, mkdir_cache=None, progress=None):
        src_p = Path(src)
        if src_p.is_dir():
            self.remote_mkdir_p(dst, cache=mkdir_cache)
            for item in src_p.iterdir():
                child_dst = posixpath.join(dst, item.name)
                self.copy_local_to_remote(str(item), child_dst, mkdir_cache=mkdir_cache, progress=progress)
            return
        self.remote_mkdir_p(posixpath.dirname(dst) or "/", cache=mkdir_cache)
        size = 0
        try:
            size = int(src_p.stat().st_size)
        except Exception:
            size = 0
        self.sftp.put(str(src_p), dst)
        if progress:
            progress(str(src_p), size)

    def copy_remote_to_local(self, src, dst, st=None, progress=None):
        if st is None:
            st = self.remote_lstat(src)
        mode = int(getattr(st, "st_mode", 0))
        if stat.S_ISLNK(mode):
            raise RuntimeError(f"Refusing to copy symlink from phone: {src}")
        if stat.S_ISDIR(mode):
            os.makedirs(dst, exist_ok=True)
            for item in self.sftp.listdir_attr(src):
                child_src = posixpath.join(src, item.filename) if src != "/" else "/" + item.filename
                child_dst = os.path.join(dst, item.filename)
                self.copy_remote_to_local(child_src, child_dst, st=item, progress=progress)
            return
        parent = os.path.dirname(dst)
        if parent:
            os.makedirs(parent, exist_ok=True)
        self.sftp.get(src, dst)
        if progress:
            progress(src, int(getattr(st, "st_size", 0)))

    def remote_delete(self, path, st=None, progress=None):
        if st is None:
            st = self.remote_lstat(path)
        mode = int(getattr(st, "st_mode", 0))
        if stat.S_ISLNK(mode):
            self.sftp.remove(path)
            if progress:
                progress(path, int(getattr(st, "st_size", 0)))
            return
        if stat.S_ISDIR(mode):
            for item in self.sftp.listdir_attr(path):
                child = posixpath.join(path, item.filename) if path != "/" else "/" + item.filename
                self.remote_delete(child, st=item, progress=progress)
            self.sftp.rmdir(path)
            return
        self.sftp.remove(path)
        if progress:
            progress(path, int(getattr(st, "st_size", 0)))

    def local_delete(self, path):
        p = Path(path)
        if p.is_dir():
            shutil.rmtree(p)
        else:
            p.unlink(missing_ok=True)

    def open_with_default_app(self, path):
        target = str(path)
        is_wsl = bool(os.environ.get("WSL_DISTRO_NAME"))
        try:
            with open(os.devnull, "wb") as devnull:
                if is_wsl:
                    if shutil.which("wslview"):
                        subprocess.Popen(["wslview", target], stdout=devnull, stderr=devnull, start_new_session=True)
                        return True
                    win_path = target
                    if shutil.which("wslpath"):
                        out = subprocess.run(["wslpath", "-w", target], capture_output=True, text=True, check=False)
                        if out.returncode == 0 and out.stdout.strip():
                            win_path = out.stdout.strip()
                    if shutil.which("cmd.exe"):
                        subprocess.Popen(["cmd.exe", "/c", "start", "", win_path], stdout=devnull, stderr=devnull, start_new_session=True)
                        return True
                    if shutil.which("powershell.exe"):
                        esc = win_path.replace("'", "''")
                        subprocess.Popen(["powershell.exe", "-NoProfile", "-Command", f"Start-Process -FilePath '{esc}'"], stdout=devnull, stderr=devnull, start_new_session=True)
                        return True
                if shutil.which("xdg-open"):
                    subprocess.Popen(["xdg-open", target], stdout=devnull, stderr=devnull, start_new_session=True)
                    return True
                if shutil.which("open"):
                    subprocess.Popen(["open", target], stdout=devnull, stderr=devnull, start_new_session=True)
                    return True
        except Exception:
            return False
        return False

    def open_selected_file(self):
        if self.operation_active():
            self.set_status("An operation is in progress. Please wait.", "warn")
            return
        row = self.selected()
        if not row or row.get("is_dir"):
            self.set_status("Select a file to open.", "warn")
            return

        try:
            if self.active == "local":
                target = Path(row["path"])
                if self.open_with_default_app(str(target)):
                    self.set_status(f"Opened: {target}", "ok")
                else:
                    self.set_status("Could not open file with default app.", "error")
                return
            safe_name = row["name"].replace("/", "_")
            target = self.open_cache_dir / f"{int(time.time())}-{safe_name}"
            src_path = str(row["path"])
            dst_path = str(target)
            ctx = {
                "label": "Open file",
                "total": 1,
                "done": 0,
                "files": 0,
                "bytes": 0,
                "current": src_path,
                "last_emit": 0.0,
            }

            def progress_cb(path, size):
                self.operation_progress(ctx, current=path, files_inc=1, bytes_inc=size, force=True)

            def worker():
                self.copy_remote_to_local(src_path, dst_path, progress=progress_cb)
                opened = self.open_with_default_app(dst_path)
                self.operation_progress(ctx, current=src_path, item_done=True, force=True)
                return {
                    "kind": "open",
                    "opened": bool(opened),
                    "target": dst_path,
                }

            self.start_background_operation("Open file", worker)
        except Exception as exc:
            self.set_status(f"Open failed: {exc}", "error")

    def action_open(self):
        row = self.selected()
        if not row:
            return
        if row["is_dir"]:
            try:
                if self.active == "local":
                    self.local_cwd = Path(row["path"])
                    self.local_index = 0
                    self.local_scroll = 0
                    self.clear_selection("local")
                    self.list_local()
                    self.set_status(f"Local: {self.local_cwd}", "ok")
                else:
                    self.remote_cwd = row["path"]
                    self.remote_index = 0
                    self.remote_scroll = 0
                    self.clear_selection("remote")
                    self.list_remote()
                    self.set_status(f"Phone: {self.remote_cwd}", "ok")
            except Exception as exc:
                self.set_status(f"Open directory failed: {exc}", "error")
        else:
            self.open_selected_file()

    def action_up(self):
        try:
            if self.active == "local":
                self.local_cwd = self.local_parent()
                self.local_index = 0
                self.local_scroll = 0
                self.clear_selection("local")
                self.list_local()
                self.set_status(f"Local: {self.local_cwd}", "ok")
            else:
                self.remote_cwd = self.remote_parent()
                self.remote_index = 0
                self.remote_scroll = 0
                self.clear_selection("remote")
                self.list_remote()
                self.set_status(f"Phone: {self.remote_cwd}", "ok")
        except Exception as exc:
            self.set_status(f"Up failed: {exc}", "error")

    def mark_clipboard(self, mode):
        items = self.selected_or_current_items(self.active)
        if not items:
            self.set_status("Select one or more files/dirs first.", "warn")
            return
        self.clipboard = {
            "mode": mode,
            "side": self.active,
            "items": items,
            "time": time.time(),
        }
        self.delete_armed = None
        self.set_status(f"{mode.title()} ready: {len(items)} item(s) from {self.active}. Use paste in target pane.", "ok")

    def action_copy(self):
        self.mark_clipboard("copy")

    def action_move(self):
        self.mark_clipboard("move")

    def action_paste(self):
        if self.operation_active():
            self.set_status("An operation is in progress. Please wait.", "warn")
            return
        if not self.clipboard:
            self.set_status("Clipboard is empty.", "warn")
            return

        mode = self.clipboard.get("mode", "copy")
        src_side = self.clipboard.get("side")
        items = list(self.clipboard.get("items", []))
        dst_side = self.active

        if not items:
            self.set_status("Clipboard has no items.", "warn")
            return
        if src_side == "remote" and dst_side == "remote":
            self.set_status("Remote-to-remote paste is not supported yet.", "warn")
            return

        src_side = str(src_side)
        dst_side = str(dst_side)
        mode = str(mode)
        items = [dict(item) for item in items]
        remote_cwd = str(self.remote_cwd)
        local_cwd = Path(self.local_cwd)
        ctx = {
            "label": f"{mode.title()} {src_side}->{dst_side}",
            "total": len(items),
            "done": 0,
            "files": 0,
            "bytes": 0,
            "current": "",
            "last_emit": 0.0,
        }

        def transfer_progress(path, size):
            self.operation_progress(ctx, current=path, files_inc=1, bytes_inc=size)

        def worker():
            done = 0
            mkdir_cache = {"/"}
            for item in items:
                src_path = item.get("path")
                name = item.get("name", "item")
                if src_side == "local" and dst_side == "remote":
                    target = self.remote_unique_target(remote_cwd, name, avoid_path=src_path if src_side == dst_side else None)
                    self.copy_local_to_remote(src_path, target, mkdir_cache=mkdir_cache, progress=transfer_progress)
                    if mode == "move":
                        self.local_delete(src_path)
                elif src_side == "remote" and dst_side == "local":
                    target = self.local_unique_target(local_cwd, name, avoid_path=src_path if src_side == dst_side else None)
                    self.copy_remote_to_local(src_path, str(target), progress=transfer_progress)
                    if mode == "move":
                        self.remote_delete(src_path, progress=transfer_progress)
                elif src_side == "local" and dst_side == "local":
                    src = Path(src_path)
                    target = self.local_unique_target(local_cwd, name, avoid_path=src_path)
                    if mode == "copy":
                        if src.is_dir():
                            shutil.copytree(src_path, str(target))
                        else:
                            shutil.copy2(src_path, str(target))
                    else:
                        shutil.move(src_path, str(target))
                else:
                    raise RuntimeError("Unsupported paste direction.")
                done += 1
                self.operation_progress(ctx, current=name, item_done=True, force=True)

            return {
                "kind": "paste",
                "mode": mode,
                "done": done,
                "src_side": src_side,
                "dst_side": dst_side,
                "clear_clipboard": mode == "move",
            }

        self.start_background_operation(f"{mode.title()} {src_side}->{dst_side}", worker)

    def action_delete(self, force=False):
        if self.operation_active():
            self.set_status("An operation is in progress. Please wait.", "warn")
            return
        targets = self.selected_or_current_items(self.active)
        if not targets:
            self.set_status("Nothing to delete.", "warn")
            return

        marker = f"{self.active}:{'|'.join(sorted(self.norm_path(self.active, r.get('path', '')) for r in targets))}"
        if not force and self.delete_armed != marker:
            self.delete_armed = marker
            self.set_status("Press d again (or click Delete again) to confirm.", "warn")
            return

        active_side = str(self.active)
        targets = [dict(row) for row in targets]
        ordered = sorted(targets, key=lambda r: len(self.norm_path(active_side, r.get("path", ""))), reverse=True)
        ctx = {
            "label": f"Delete {active_side}",
            "total": len(ordered),
            "done": 0,
            "files": 0,
            "bytes": 0,
            "current": "",
            "last_emit": 0.0,
        }

        def delete_progress(path, size):
            self.operation_progress(ctx, current=path, files_inc=1, bytes_inc=size)

        def worker():
            done = 0
            for row in ordered:
                path = row.get("path", "")
                if active_side == "local":
                    self.local_delete(path)
                else:
                    self.remote_delete(path, progress=delete_progress)
                done += 1
                self.operation_progress(ctx, current=path, item_done=True, force=True)
            return {
                "kind": "delete",
                "count": done,
                "side": active_side,
            }

        self.delete_armed = None
        self.start_background_operation(f"Delete {active_side}", worker)

    def select_row(self, side, idx):
        entries = self.entries_of(side)
        if not entries:
            return
        idx = max(0, min(idx, len(entries) - 1))
        self.set_index(side, idx)
        self.active = side

    def scroll_active(self, delta):
        side = self.active
        entries = self.entries_of(side)
        if not entries:
            return
        idx = self.index_of(side) + delta
        self.select_row(side, idx)

    def pane_for_xy(self, mx, my):
        for side, box in (("local", self.local_box), ("remote", self.remote_box)):
            if not box:
                continue
            x, y, w, h = box
            if x <= mx < x + w and y <= my < y + h:
                return side
        return None

    def row_index_for_xy(self, side, my):
        row_map = self.local_row_map if side == "local" else self.remote_row_map
        return row_map.get(my)

    def show_context_menu(self, side, idx, mx, my):
        entries = self.entries_of(side)
        if idx < 0 or idx >= len(entries):
            return
        items = [("copy", "Copy"), ("move", "Move"), ("paste", "Paste"), ("delete", "Delete")]
        self.menu = {
            "visible": True,
            "x": mx,
            "y": my,
            "side": side,
            "index": idx,
            "items": items,
            "selected": 0,
        }

    def close_menu(self):
        self.menu = None

    def execute_menu_action(self, action):
        if not self.menu:
            return
        if self.operation_active():
            self.close_menu()
            self.set_status("An operation is in progress. Please wait.", "warn")
            return
        side = self.menu.get("side")
        idx = int(self.menu.get("index", -1))
        if side in ("local", "remote") and idx >= 0:
            self.select_row(side, idx)
        self.close_menu()
        if action == "copy":
            self.action_copy()
        elif action == "move":
            self.action_move()
        elif action == "paste":
            self.action_paste()
        elif action == "delete":
            self.action_delete(force=True)

    def handle_menu_mouse(self, mx, my):
        if not self.menu or not self.menu.get("visible"):
            return False
        x = self.menu.get("x", 0)
        y = self.menu.get("y", 0)
        w = self.menu.get("w", 0)
        h = self.menu.get("h", 0)
        if x <= mx < x + w and y <= my < y + h:
            if y + 1 <= my < y + h - 1:
                idx = my - (y + 1)
                if 0 <= idx < len(self.menu.get("items", [])):
                    self.menu["selected"] = idx
                    action = self.menu["items"][idx][0]
                    self.execute_menu_action(action)
                    return True
            return True
        self.close_menu()
        return False

    def handle_mouse(self):
        if self.operation_active():
            return
        try:
            _, mx, my, _, bstate = curses.getmouse()
        except Exception:
            return

        b1_click = getattr(curses, "BUTTON1_CLICKED", 0)
        b1_press = getattr(curses, "BUTTON1_PRESSED", 0)
        b1_double = getattr(curses, "BUTTON1_DOUBLE_CLICKED", 0)
        b3_click = getattr(curses, "BUTTON3_CLICKED", 0)
        b3_press = getattr(curses, "BUTTON3_PRESSED", 0)
        btn_ctrl = getattr(curses, "BUTTON_CTRL", 0)
        wheel_up = getattr(curses, "BUTTON4_PRESSED", 0)
        wheel_down = getattr(curses, "BUTTON5_PRESSED", 0)

        if bstate & wheel_up:
            self.scroll_active(-3)
            return
        if bstate & wheel_down:
            self.scroll_active(3)
            return

        if self.menu and self.menu.get("visible"):
            if self.handle_menu_mouse(mx, my):
                return

        side = self.pane_for_xy(mx, my)
        if side is None:
            return
        self.active = side

        idx = self.row_index_for_xy(side, my)
        if idx is None:
            return

        self.select_row(side, idx)
        row = self.selected()
        ctrl_down = bool(btn_ctrl and (bstate & btn_ctrl))

        if bstate & (b3_click | b3_press):
            if ctrl_down and row is not None:
                self.toggle_select_row(side, row)
                return
            self.show_context_menu(side, idx, mx, my)
            return

        if bstate & (b1_click | b1_press | b1_double):
            if ctrl_down and row is not None:
                self.toggle_select_row(side, row)
                return
            self.clear_selection(side)
            self.action_open()

    def handle_menu_keys(self, key):
        if self.operation_active():
            return False
        if not self.menu or not self.menu.get("visible"):
            return False
        items = self.menu.get("items", [])
        if not items:
            self.close_menu()
            return True
        if key in (27,):
            self.close_menu()
            return True
        if key in (curses.KEY_UP, ord("k")):
            self.menu["selected"] = (int(self.menu.get("selected", 0)) - 1) % len(items)
            return True
        if key in (curses.KEY_DOWN, ord("j")):
            self.menu["selected"] = (int(self.menu.get("selected", 0)) + 1) % len(items)
            return True
        if key in (10, 13, curses.KEY_ENTER):
            idx = int(self.menu.get("selected", 0))
            action = items[idx][0]
            self.execute_menu_action(action)
            return True
        return False

    def run(self):
        while True:
            self.poll_background_operation()
            self.draw()
            self.stdscr.timeout(100 if self.operation_active() else -1)
            key = self.stdscr.getch()
            self.poll_background_operation()

            if key == -1:
                continue

            if self.operation_active():
                if key in (ord("q"), ord("Q")):
                    self.set_status("Operation in progress. Wait for completion.", "warn")
                continue

            if key == curses.KEY_RESIZE:
                self.set_status("Layout updated after resize.", "ok")
                continue

            if key == curses.KEY_MOUSE:
                self.handle_mouse()
                continue

            if self.handle_menu_keys(key):
                continue

            if key in (ord("q"), ord("Q")):
                return
            if key == 9:
                self.active = "remote" if self.active == "local" else "local"
                self.delete_armed = None
                self.set_status(f"Active pane: {self.active}", "ok")
                continue
            if key in (curses.KEY_UP, ord("k")):
                self.scroll_active(-1)
                continue
            if key in (curses.KEY_DOWN, ord("j")):
                self.scroll_active(1)
                continue
            if key in (ord(" "),):
                self.toggle_select_current()
                continue
            if key in (10, 13, curses.KEY_RIGHT):
                self.clear_selection(self.active)
                self.action_open()
                continue
            if key in (curses.KEY_BACKSPACE, 127, 8, curses.KEY_LEFT):
                self.action_up()
                continue
            if key in (ord("c"), ord("C")):
                self.action_copy()
                continue
            if key in (ord("m"), ord("M")):
                self.action_move()
                continue
            if key in (ord("p"), ord("P")):
                self.action_paste()
                continue
            if key in (ord("d"), ord("D"), curses.KEY_DC):
                self.action_delete()
                continue
            if key in (ord("o"), ord("O")):
                self.open_selected_file()
                continue
            if key in (ord("r"), ord("R")):
                self.refresh_all()
                self.set_status("Refreshed.", "ok")
                continue
            self.set_status("Unknown key.", "warn")


def main():
    parser = argparse.ArgumentParser(description="aurorafs TUI client")
    parser.add_argument("--config", default=os.path.expanduser("~/.config/aurorafs/config.json"))
    parser.add_argument("--local-root", default="", help="Override initial local pane path")
    args, extras = parser.parse_known_args()

    cfg = load_config(os.path.expanduser(args.config))
    local_override = str(getattr(args, "local_root", "") or "").strip()
    if local_override:
        cfg["local_root"] = os.path.expanduser(local_override)
    elif extras:
        # Tolerate unexpected trailing args from shell aliases/functions.
        first = os.path.expanduser(str(extras[0]))
        if os.path.isdir(first):
            cfg["local_root"] = first
        elif os.path.exists(first):
            cfg["local_root"] = str(Path(first).parent)

    host = str(cfg.get("host", "")).strip()
    if not host:
        raise SystemExit("Missing host in config")
    port = int(cfg.get("ssh_port", 2223))
    username = str(cfg.get("username", "root")).strip() or "root"
    key_path = os.path.expanduser(str(cfg.get("key_path", "~/.config/aurorafs/id_ed25519")))
    known_hosts_path = os.path.expanduser(str(cfg.get("known_hosts_path", "~/.config/aurorafs/known_hosts")))
    if not os.path.isfile(known_hosts_path):
        raise SystemExit(f"Missing known_hosts file: {known_hosts_path}. Re-run pcbridge setup.")

    ssh = paramiko.SSHClient()
    ssh.load_host_keys(known_hosts_path)
    ssh.set_missing_host_key_policy(paramiko.RejectPolicy())
    ssh.connect(
        hostname=host,
        port=port,
        username=username,
        key_filename=key_path,
        look_for_keys=False,
        allow_agent=False,
        timeout=12,
        banner_timeout=12,
        auth_timeout=12,
    )
    sftp = ssh.open_sftp()
    try:
        curses.wrapper(lambda stdscr: BridgeUI(stdscr, sftp, cfg).run())
    finally:
        try:
            sftp.close()
        finally:
            ssh.close()


if __name__ == "__main__":
    main()
'''

BOOTSTRAP_TEMPLATE = r'''#!/usr/bin/env bash
set -euo pipefail

AURORA_BASE_URL="__BASE_URL__"
AURORA_TOKEN="__TOKEN__"
AURORA_SSH_PORT="__SSH_PORT__"
AURORA_HOSTKEY_ED25519="__HOSTKEY_ED25519__"
AURORA_HOSTKEY_RSA="__HOSTKEY_RSA__"

AURORA_STEP=0

step() {
  AURORA_STEP=$((AURORA_STEP + 1))
  printf '[%02d] %s\n' "$AURORA_STEP" "$1"
}

ok() {
  printf '     [ok] %s\n' "$1"
}

note() {
  printf '     [..] %s\n' "$1"
}

pick_sudo() {
  if [[ "$(id -u)" -eq 0 ]]; then
    printf ''
    return
  fi
  if command -v sudo >/dev/null 2>&1; then
    printf 'sudo'
    return
  fi
  printf ''
}

SUDO="$(pick_sudo)"
AURORA_APT_UPDATED=0

step "Starting aurorafs first-time setup"
ok "bootstrap endpoint reachable at $AURORA_BASE_URL"

run_pkg_install() {
  local pkg="$1"
  if command -v apt-get >/dev/null 2>&1; then
    if [[ "$AURORA_APT_UPDATED" != "1" ]]; then
      ${SUDO:+$SUDO }apt-get update -y >/dev/null 2>&1 || true
      AURORA_APT_UPDATED=1
    fi
    ${SUDO:+$SUDO }apt-get install -y "$pkg" >/dev/null 2>&1 && return 0
  fi
  if command -v pacman >/dev/null 2>&1; then
    ${SUDO:+$SUDO }pacman -Sy --noconfirm "$pkg" >/dev/null 2>&1 && return 0
  fi
  if command -v dnf >/dev/null 2>&1; then
    ${SUDO:+$SUDO }dnf install -y "$pkg" >/dev/null 2>&1 && return 0
  fi
  if command -v apk >/dev/null 2>&1; then
    ${SUDO:+$SUDO }apk add --no-cache "$pkg" >/dev/null 2>&1 && return 0
  fi
  return 1
}

ensure_cmd() {
  local cmd="$1"
  shift
  if command -v "$cmd" >/dev/null 2>&1; then
    return 0
  fi
  local pkg
  for pkg in "$@"; do
    if run_pkg_install "$pkg" && command -v "$cmd" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

step "Checking required tools on PC (curl, ssh-keygen, python3)"
ensure_cmd curl curl || { echo "pcbridge bootstrap: failed to install curl" >&2; exit 1; }
ensure_cmd ssh-keygen openssh-client openssh || { echo "pcbridge bootstrap: failed to install openssh client" >&2; exit 1; }
ensure_cmd python3 python3 python || { echo "pcbridge bootstrap: failed to install python3" >&2; exit 1; }
ok "required tools are available"

CONF_DIR="$HOME/.config/aurorafs"
APP_DIR="$HOME/.local/share/aurorafs"
BIN_DIR="$HOME/.local/bin"
step "Preparing local directories"
mkdir -p "$CONF_DIR" "$APP_DIR" "$BIN_DIR"
ok "created/verified: $CONF_DIR, $APP_DIR, $BIN_DIR"

python_has_module() {
  local py="$1"
  local module="$2"
  "$py" - "$module" <<'PY_MOD' >/dev/null 2>&1
import importlib.util
import sys
name = sys.argv[1]
sys.exit(0 if importlib.util.find_spec(name) is not None else 1)
PY_MOD
}

CLIENT_PYTHON="python3"

step "Resolving Python runtime for aurorafs client"
if ! python_has_module "python3" "paramiko"; then
  note "paramiko not found in system python; trying distro packages"
  if run_pkg_install python3-paramiko || run_pkg_install python-paramiko || run_pkg_install py3-paramiko; then
    ok "installed paramiko via package manager"
  fi
fi

if ! python_has_module "python3" "paramiko"; then
  note "system package path unavailable; creating isolated virtualenv"
  VENV_DIR="$APP_DIR/.venv"
  if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    if ! python3 -m venv "$VENV_DIR" >/dev/null 2>&1; then
      run_pkg_install python3-venv >/dev/null 2>&1 || run_pkg_install py3-virtualenv >/dev/null 2>&1 || run_pkg_install python-virtualenv >/dev/null 2>&1 || true
      python3 -m venv "$VENV_DIR" >/dev/null 2>&1 || {
        echo "pcbridge bootstrap: failed to create Python virtualenv." >&2
        exit 1
      }
    fi
    ok "virtualenv created at $VENV_DIR"
  fi

  CLIENT_PYTHON="$VENV_DIR/bin/python"
  if ! "$CLIENT_PYTHON" -m pip --version >/dev/null 2>&1; then
    "$CLIENT_PYTHON" -m ensurepip --upgrade >/dev/null 2>&1 || true
  fi
  if ! "$CLIENT_PYTHON" -m pip --version >/dev/null 2>&1; then
    echo "pcbridge bootstrap: pip is unavailable in virtualenv." >&2
    exit 1
  fi

  "$CLIENT_PYTHON" -m pip install --upgrade pip >/dev/null 2>&1 || true
  "$CLIENT_PYTHON" -m pip install --upgrade paramiko >/dev/null 2>&1 || "$CLIENT_PYTHON" -m pip install --upgrade paramiko
  ok "installed paramiko in virtualenv"
fi

if ! python_has_module "$CLIENT_PYTHON" "paramiko"; then
  echo "pcbridge bootstrap: paramiko is required but could not be installed." >&2
  exit 1
fi
ok "python runtime ready: $CLIENT_PYTHON"

step "Downloading aurorafs client UI"
curl -fsSL "$AURORA_BASE_URL/client.py?token=$AURORA_TOKEN" -o "$APP_DIR/aurorafs_client.py"
chmod 0644 "$APP_DIR/aurorafs_client.py"
ok "client saved to $APP_DIR/aurorafs_client.py"

step "Preparing SSH key for key-only pairing"
if [[ ! -f "$CONF_DIR/id_ed25519" ]]; then
  ssh-keygen -t ed25519 -N "" -f "$CONF_DIR/id_ed25519" >/dev/null
  ok "generated new keypair at $CONF_DIR/id_ed25519"
else
  ok "reusing existing keypair at $CONF_DIR/id_ed25519"
fi

step "Pairing this PC key with phone pcbridge service"
curl -fsS -X POST "$AURORA_BASE_URL/pair?token=$AURORA_TOKEN" --data-binary @"$CONF_DIR/id_ed25519.pub" >/dev/null
ok "public key accepted by phone"

step "Writing aurorafs connection config"
AURORA_HOST="$("$CLIENT_PYTHON" - "$AURORA_BASE_URL" <<'PY_HOST'
import sys
import urllib.parse
u = urllib.parse.urlparse(sys.argv[1])
print(u.hostname or "")
PY_HOST
)"
if [[ -z "$AURORA_HOST" ]]; then
  echo "pcbridge bootstrap: failed parsing host from bootstrap URL." >&2
  exit 1
fi

KNOWN_HOSTS_PATH="$CONF_DIR/known_hosts"
{
  if [[ -n "$AURORA_HOSTKEY_ED25519" ]]; then
    printf '[%s]:%s ssh-ed25519 %s\n' "$AURORA_HOST" "$AURORA_SSH_PORT" "$AURORA_HOSTKEY_ED25519"
  fi
  if [[ -n "$AURORA_HOSTKEY_RSA" ]]; then
    printf '[%s]:%s ssh-rsa %s\n' "$AURORA_HOST" "$AURORA_SSH_PORT" "$AURORA_HOSTKEY_RSA"
  fi
} >"$KNOWN_HOSTS_PATH"
if [[ ! -s "$KNOWN_HOSTS_PATH" ]]; then
  echo "pcbridge bootstrap: missing server host key data." >&2
  exit 1
fi
chmod 600 "$KNOWN_HOSTS_PATH"
ok "pinned phone SSH host key(s) in $KNOWN_HOSTS_PATH"

"$CLIENT_PYTHON" - "$CONF_DIR/config.json" "$AURORA_HOST" "$AURORA_SSH_PORT" "$CONF_DIR/id_ed25519" "$KNOWN_HOSTS_PATH" <<'PY_CFG'
import json
import os
import sys

cfg_path, host, port, key_path, known_hosts_path = sys.argv[1:6]

def default_local_root():
    home = os.path.expanduser("~")
    if not os.environ.get("WSL_DISTRO_NAME"):
        return home
    users_root = "/mnt/c/Users"
    if not os.path.isdir(users_root):
        return home
    wanted = (os.environ.get("USERNAME") or os.environ.get("USER") or "").strip()
    if wanted:
        direct = os.path.join(users_root, wanted, "Desktop")
        if os.path.isdir(direct):
            return direct
        try:
            for name in os.listdir(users_root):
                if name.lower() == wanted.lower():
                    cand = os.path.join(users_root, name, "Desktop")
                    if os.path.isdir(cand):
                        return cand
        except Exception:
            pass
    skip = {"public", "default", "default user", "all users"}
    try:
        for name in os.listdir(users_root):
            if name.lower() in skip:
                continue
            cand = os.path.join(users_root, name, "Desktop")
            if os.path.isdir(cand):
                return cand
    except Exception:
        pass
    return home

payload = {
    "host": host,
    "ssh_port": int(port),
    "username": "root",
    "remote_root": "/storage",
    "local_root": default_local_root(),
    "key_path": os.path.expanduser(key_path),
    "known_hosts_path": os.path.expanduser(known_hosts_path),
}
with open(cfg_path, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY_CFG
ok "config written to $CONF_DIR/config.json"

step "Installing aurorafs launcher command"
cat >"$BIN_DIR/aurorafs" <<'EOF_LAUNCH'
#!/usr/bin/env bash
set -euo pipefail
APP_DIR="$HOME/.local/share/aurorafs"
CFG_PATH="$HOME/.config/aurorafs/config.json"
if [[ -x "$APP_DIR/.venv/bin/python" ]]; then
  exec "$APP_DIR/.venv/bin/python" "$APP_DIR/aurorafs_client.py" --config "$CFG_PATH" "$@"
fi
exec python3 "$APP_DIR/aurorafs_client.py" --config "$CFG_PATH" "$@"
EOF_LAUNCH
chmod +x "$BIN_DIR/aurorafs"
ok "launcher installed at $BIN_DIR/aurorafs"

update_profile() {
  local file="$1"
  local start="# >>> aurorafs >>>"
  local end="# <<< aurorafs <<<"
  local tmp
  tmp="$(mktemp)"
  touch "$file"
  awk -v s="$start" -v e="$end" '
    BEGIN {skip=0}
    $0 == s {skip=1; next}
    $0 == e {skip=0; next}
    !skip {print}
  ' "$file" >"$tmp"
  {
    printf '%s\n' "$start"
    printf '%s\n' 'alias aurorafs="$HOME/.local/bin/aurorafs"'
    printf '%s\n' "$end"
  } >>"$tmp"
  mv -f -- "$tmp" "$file"
}

step "Updating shell aliases"
update_profile "$HOME/.bashrc"
ok "updated alias block in $HOME/.bashrc"
if [[ -f "$HOME/.zshrc" ]]; then
  update_profile "$HOME/.zshrc"
  ok "updated alias block in $HOME/.zshrc"
fi

step "Setup completed"
ok "aurorafs is ready"
echo "Run now: aurorafs"
'''

CLEANUP_TEMPLATE = r'''#!/usr/bin/env bash
set -euo pipefail

AURORA_BASE_URL="__BASE_URL__"
AURORA_STEP=0

step() {
  AURORA_STEP=$((AURORA_STEP + 1))
  printf '[%02d] %s\n' "$AURORA_STEP" "$1"
}

ok() {
  printf '     [ok] %s\n' "$1"
}

note() {
  printf '     [..] %s\n' "$1"
}

remove_tree() {
  local p="$1"
  if [[ -e "$p" ]]; then
    rm -rf -- "$p"
    ok "removed $p"
  else
    note "$p already clean"
  fi
}

remove_file() {
  local p="$1"
  if [[ -f "$p" || -L "$p" ]]; then
    rm -f -- "$p"
    ok "removed $p"
  else
    note "$p already clean"
  fi
}

remove_profile_block() {
  local file="$1"
  local start="# >>> aurorafs >>>"
  local end="# <<< aurorafs <<<"
  local tmp had

  if [[ ! -f "$file" ]]; then
    note "$file not found (skipped)"
    return
  fi

  had=0
  if grep -Fq "$start" "$file"; then
    had=1
  fi

  tmp="$(mktemp)"
  awk -v s="$start" -v e="$end" '
    BEGIN {skip=0}
    $0 == s {skip=1; next}
    $0 == e {skip=0; next}
    !skip {print}
  ' "$file" >"$tmp"
  mv -f -- "$tmp" "$file"

  if [[ "$had" == "1" ]]; then
    ok "removed aurorafs alias block from $file"
  else
    note "no aurorafs alias block in $file"
  fi
}

step "Starting aurorafs PC-side cleanup"
ok "cleanup endpoint reached at $AURORA_BASE_URL"

step "Removing aurorafs files and folders"
remove_tree "$HOME/.config/aurorafs"
remove_tree "$HOME/.local/share/aurorafs"
remove_file "$HOME/.local/bin/aurorafs"

step "Removing shell alias entries"
remove_profile_block "$HOME/.bashrc"
if [[ -f "$HOME/.zshrc" ]]; then
  remove_profile_block "$HOME/.zshrc"
else
  note "$HOME/.zshrc not found (skipped)"
fi

step "Cleanup completed"
ok "aurorafs files were removed from this PC user profile"
ok "system/python packages were not changed"
echo "You can run first setup again from phone option [f]."
'''


def now_iso():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


last_event = ""


def write_event(name):
    global last_event
    event_name = str(name or "").strip()
    if not event_name:
        return
    if event_name == last_event:
        return
    last_event = event_name
    try:
        os.makedirs(os.path.dirname(token_event_file), exist_ok=True)
    except Exception:
        pass
    payload = f"{event_name}\t{now_iso()}\n"
    try:
        tmp = token_event_file + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            fh.write(payload)
        os.replace(tmp, token_event_file)
        try:
            os.chmod(token_event_file, 0o600)
        except Exception:
            pass
    except Exception:
        pass


def token_manually_expired():
    try:
        with open(token_control_file, "r", encoding="utf-8") as fh:
            marker = fh.read(128).strip().lower()
    except Exception:
        return False
    return marker in {"expire", "expired", "1", "true", "yes", "manual-expire"}


def token_is_valid(value):
    global token_paired
    if not value or value != token:
        return False, "invalid token"
    if token_paired:
        return False, "token already used"
    if token_manually_expired():
        write_event("manually_expired")
        return False, "token manually expired"
    if time.time() > started_at + token_ttl:
        write_event("expired")
        return False, "token expired"
    return True, ""


def safe_key_line(raw):
    text = (raw or "").strip()
    if not text:
        return ""
    if len(text) > 16384:
        return ""
    if not re.match(r"^ssh-(ed25519|rsa) [A-Za-z0-9+/=]+(?: .*)?$", text):
        return ""
    return text


def sanitize_hostkey_blob(raw):
    text = str(raw or "").strip()
    if re.match(r"^[A-Za-z0-9+/=]{32,8192}$", text):
        return text
    return ""


hostkey_ed25519_pub = sanitize_hostkey_blob(hostkey_ed25519_pub)
hostkey_rsa_pub = sanitize_hostkey_blob(hostkey_rsa_pub)
if not hostkey_ed25519_pub and not hostkey_rsa_pub:
    raise SystemExit("pcbridge: missing valid host key data")


def build_bootstrap(base_url):
    body = BOOTSTRAP_TEMPLATE
    body = body.replace("__BASE_URL__", base_url)
    body = body.replace("__TOKEN__", token)
    body = body.replace("__SSH_PORT__", str(ssh_port))
    body = body.replace("__HOSTKEY_ED25519__", hostkey_ed25519_pub)
    body = body.replace("__HOSTKEY_RSA__", hostkey_rsa_pub)
    return body


def build_cleanup(base_url):
    body = CLEANUP_TEMPLATE
    body = body.replace("__BASE_URL__", base_url)
    return body


write_event("ready")


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        return

    def _send(self, code, body, ctype="text/plain; charset=utf-8"):
        if isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _request_token(self):
        parsed = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(parsed.query)
        header_token = ""
        auth_header = ""
        try:
            for hk, hv in self.headers.items():
                key = str(hk or "").strip().lower()
                val = str(hv or "").strip()
                if key == "x-aurora-token" and val and not header_token:
                    header_token = val
                elif key == "authorization" and val and not auth_header:
                    auth_header = val
        except Exception:
            pass

        if not header_token and auth_header:
            if auth_header.lower().startswith("bearer "):
                header_token = auth_header[7:].strip()
            else:
                header_token = auth_header.strip()

        if not header_token:
            try:
                raw_headers = self.headers.as_string()
                for line in raw_headers.splitlines():
                    line_l = line.lower()
                    if line_l.startswith("x-aurora-token:"):
                        header_token = line.split(":", 1)[1].strip()
                        break
                    if line_l.startswith("authorization:"):
                        auth = line.split(":", 1)[1].strip()
                        if auth.lower().startswith("bearer "):
                            auth = auth[7:].strip()
                        if auth:
                            header_token = auth
                            break
            except Exception:
                pass

        query_token = (q.get("token", [""])[0] or "").strip()
        req_token = header_token or query_token
        return parsed.path, req_token

    def _base_url(self):
        host = ""
        port = http_port
        try:
            sock = self.connection.getsockname()
            if isinstance(sock, tuple):
                host = str(sock[0] or "")
                if len(sock) > 1:
                    port = int(sock[1])
        except Exception:
            pass
        if not host or host == "0.0.0.0":
            host = "127.0.0.1"
        if ":" in host and not host.startswith("["):
            host = f"[{host}]"
        return f"http://{host}:{port}"

    def do_GET(self):
        global bootstrap_command_consumed
        global cleanup_command_consumed
        path, req_token = self._request_token()
        with lock:
            ok, msg = token_is_valid(req_token)
            if not ok:
                self._send(403, f"forbidden: {msg}\n")
                return

            base_url = self._base_url()

            if path == "/bootstrap.sh":
                if bootstrap_command_consumed:
                    self._send(403, "forbidden: bootstrap command already used\n")
                    return
                bootstrap_command_consumed = True
                write_event("bootstrap_command_used")
                self._send(200, build_bootstrap(base_url), "text/x-shellscript; charset=utf-8")
                return
            if path == "/cleanup.sh":
                if cleanup_command_consumed:
                    self._send(403, "forbidden: cleanup command already used\n")
                    return
                cleanup_command_consumed = True
                write_event("cleanup_command_used")
                self._send(200, build_cleanup(base_url), "text/x-shellscript; charset=utf-8")
                return
            if path == "/client.py":
                self._send(200, CLIENT_PY, "text/x-python; charset=utf-8")
                return
            if path == "/manifest.json":
                payload = {
                    "service": "pcbridge",
                    "ssh_port": ssh_port,
                    "http_port": http_port,
                    "token_ttl_sec": token_ttl,
                    "started_at": started_at_iso,
                }
                self._send(200, json.dumps(payload, indent=2) + "\n", "application/json; charset=utf-8")
                return
            self._send(404, "not found\n")

    def do_POST(self):
        global token_paired
        path, req_token = self._request_token()
        if path != "/pair":
            self._send(404, "not found\n")
            return

        with lock:
            ok, msg = token_is_valid(req_token)
            if not ok:
                self._send(403, f"forbidden: {msg}\n")
                return

            try:
                length = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                length = 0
            if length <= 0:
                self._send(400, "missing ssh public key payload\n")
                return
            if length > MAX_PAIR_KEY_BYTES:
                self._send(413, "ssh public key payload too large\n")
                return
            raw = self.rfile.read(max(0, length)).decode("utf-8", errors="ignore")
            key = safe_key_line(raw)
            if not key:
                self._send(400, "invalid ssh public key\n")
                return

            os.makedirs(os.path.dirname(keys_file), exist_ok=True)
            existing = set()
            if os.path.exists(keys_file):
                with open(keys_file, "r", encoding="utf-8") as fh:
                    for line in fh:
                        line = line.strip()
                        if line:
                            existing.add(line)
            if key not in existing:
                with open(keys_file, "a", encoding="utf-8") as fh:
                    fh.write(key + "\n")
            os.chmod(keys_file, 0o600)
            token_paired = True
            write_event("paired")

        self._send(200, json.dumps({"ok": True}) + "\n", "application/json; charset=utf-8")


server = http.server.ThreadingHTTPServer(("0.0.0.0", http_port), Handler)
server.serve_forever()
PY_SERVER
HTTP_CHILD="$!"
fi

started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)"
if [ "$PAIRING_ENABLED" = "1" ]; then
  cat >"$STATE_JSON" <<EOF_JSON
{
  "service": "pcbridge",
  "mode": "pairing",
  "token": "$TOKEN",
  "ssh_port": $SSH_PORT,
  "http_port": $HTTP_PORT,
  "token_ttl_sec": $TOKEN_TTL,
  "hostkey_mode": "dedicated",
  "hostkey_dir": "$HOSTKEY_DIR",
  "system_ssh_hostkeys_missing": $SYSTEM_HOSTKEYS_MISSING,
  "started_at": "$started_at"
}
EOF_JSON
else
  cat >"$STATE_JSON" <<EOF_JSON
{
  "service": "pcbridge",
  "mode": "normal",
  "ssh_port": $SSH_PORT,
  "hostkey_mode": "dedicated",
  "hostkey_dir": "$HOSTKEY_DIR",
  "system_ssh_hostkeys_missing": $SYSTEM_HOSTKEYS_MISSING,
  "started_at": "$started_at"
}
EOF_JSON
fi
chmod 600 "$STATE_JSON"

cleanup() {
  trap - INT TERM EXIT
  if [ -n "$HTTP_CHILD" ]; then
    kill "$HTTP_CHILD" >/dev/null 2>&1 || true
  fi
  kill "$SSHD_CHILD" >/dev/null 2>&1 || true
  if [ -n "$HTTP_CHILD" ]; then
    wait "$HTTP_CHILD" 2>/dev/null || true
  fi
  wait "$SSHD_CHILD" 2>/dev/null || true
  rm -f -- "$TOKEN_FILE" "$TOKEN_EVENT_FILE" "$TOKEN_CONTROL_FILE" "$STATE_JSON"
}

trap cleanup INT TERM EXIT

while true; do
  if [ -n "$HTTP_CHILD" ]; then
    if ! kill -0 "$HTTP_CHILD" >/dev/null 2>&1; then
      echo "pcbridge: bootstrap http endpoint exited." >&2
      exit 1
    fi
  fi
  if ! kill -0 "$SSHD_CHILD" >/dev/null 2>&1; then
    echo "pcbridge: ssh endpoint exited." >&2
    exit 1
  fi
  sleep 1
done
EOF_PCBRIDGE
}
