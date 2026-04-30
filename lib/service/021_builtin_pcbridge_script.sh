chroot_service_builtin_pcbridge_script_content() {
  cat <<'EOF_PCBRIDGE'
#!/bin/sh
set -eu

RUNDIR="/run/aurora-pcbridge"
STOP_REQUEST_FILE="$RUNDIR/stop_request"
STORE_DIR="/etc/aurora-pcbridge"
STATE_JSON="$STORE_DIR/state.json"
TOKEN_FILE="$STORE_DIR/token"
KEYS_FILE="$STORE_DIR/authorized_keys"
SSHD_LOG="$STORE_DIR/sshd.log"
HTTP_LOG="$STORE_DIR/http.log"
WARN_LOG="$STORE_DIR/warnings.log"
TOKEN_EVENT_FILE="$STORE_DIR/token_event"
TOKEN_CONTROL_FILE="$STORE_DIR/token_control"
BROWSER_REQUEST_FILE="$STORE_DIR/browser_request.json"
BROWSER_APPROVAL_FILE="$STORE_DIR/browser_approval"
HOSTKEY_DIR="$STORE_DIR/hostkeys"
HOSTKEY_ED25519="$HOSTKEY_DIR/ssh_host_ed25519_key"
HOSTKEY_RSA="$HOSTKEY_DIR/ssh_host_rsa_key"
SSH_PORT="${AURORA_PCBRIDGE_SSH_PORT:-2223}"
HTTP_PORT="${AURORA_PCBRIDGE_HTTP_PORT:-47077}"
TOKEN_TTL="${AURORA_PCBRIDGE_TOKEN_TTL_SEC:-900}"
PAIRING_FLAG="${AURORA_PCBRIDGE_PAIRING:-0}"
PAIRING_ACTION="${AURORA_PCBRIDGE_ACTION:-bootstrap}"
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

case "$PAIRING_ACTION" in
  bootstrap|setup|first|first-run)
    PAIRING_ACTION="bootstrap"
    ;;
  cleanup|clean)
    PAIRING_ACTION="cleanup"
    ;;
  *)
    PAIRING_ACTION="bootstrap"
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
rm -f -- "$STOP_REQUEST_FILE" "$TOKEN_FILE" "$TOKEN_EVENT_FILE" "$TOKEN_CONTROL_FILE" "$BROWSER_REQUEST_FILE" "$BROWSER_APPROVAL_FILE" 2>/dev/null || true

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

  "$PYTHON_BIN" - "$TOKEN" "$HTTP_PORT" "$TOKEN_TTL" "$SSH_PORT" "$KEYS_FILE" "$TOKEN_EVENT_FILE" "$TOKEN_CONTROL_FILE" "$HOSTKEY_ED25519_PUB" "$HOSTKEY_RSA_PUB" "$PAIRING_ACTION" "$BROWSER_REQUEST_FILE" "$BROWSER_APPROVAL_FILE" <<'PY_SERVER' >"$HTTP_LOG" 2>&1 &
import base64
import html
import http.server
import json
import os
import posixpath
import re
import stat
import secrets
import threading
import time
import urllib.parse
import sys

token, http_port, token_ttl, ssh_port, keys_file, token_event_file, token_control_file, hostkey_ed25519_pub, hostkey_rsa_pub, pairing_action, browser_request_file, browser_approval_file = sys.argv[1:13]
http_port = int(http_port)
token_ttl = int(token_ttl)
ssh_port = int(ssh_port)
pairing_action = "cleanup" if str(pairing_action or "").strip().lower() == "cleanup" else "bootstrap"
started_at = time.time()
started_at_iso = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(started_at))
token_paired = False
bootstrap_command_consumed = False
cleanup_command_consumed = False
current_browser_request = None
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

FAST_SFTP_WINDOW_SIZE = 16 * 1024 * 1024
FAST_SFTP_MAX_PACKET_SIZE = 256 * 1024
PHONE_STOP_REQUEST_PATH = "/run/aurora-pcbridge/stop_request"
CTRL_K = 11


class CancelledError(Exception):
    pass


def human_size(num):
    units = ["B", "KB", "MB", "GB", "TB"]
    value = float(num)
    for unit in units:
        if value < 1024 or unit == units[-1]:
            return f"{value:.1f}{unit}" if unit != "B" else f"{int(value)}B"
        value /= 1024.0
    return f"{int(num)}B"


def load_config(path):
    with open(path, "r", encoding="utf-8-sig") as fh:
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


def detect_windows_desktop():
    if os.name != "nt":
        return None
    home = Path.home()
    desktop = home / "Desktop"
    return str(desktop) if desktop.is_dir() else str(home)


class BridgeUI:
    def __init__(self, stdscr, sftp, cfg):
        self.stdscr = stdscr
        self.sftp = sftp
        self.cfg = cfg
        configured_local = str(cfg.get("local_root", "") or "").strip()
        wsl_desktop = detect_wsl_desktop()
        windows_desktop = detect_windows_desktop()
        if configured_local:
            self.local_cwd = Path(configured_local).expanduser()
        else:
            self.local_cwd = Path(wsl_desktop or windows_desktop) if (wsl_desktop or windows_desktop) else Path.home()
        if wsl_desktop and str(self.local_cwd) == str(Path.home()):
            self.local_cwd = Path(wsl_desktop)
        if windows_desktop and str(self.local_cwd) == str(Path.home()):
            self.local_cwd = Path(windows_desktop)
        if not self.local_cwd.exists():
            if wsl_desktop and Path(wsl_desktop).exists():
                self.local_cwd = Path(wsl_desktop)
            elif windows_desktop and Path(windows_desktop).exists():
                self.local_cwd = Path(windows_desktop)
            else:
                self.local_cwd = Path.home()
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
        self.operation_cancel = None
        self.operation_stop_allowed = False
        self.operation_process = None
        self.operation_resources = []
        self.transfer_info = None
        self.state_lock = threading.RLock()
        self.phone_stop_armed_until = 0.0

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
        with self.state_lock:
            self.status = str(text).strip()[:300]
            self.status_kind = kind

    def operation_active(self):
        return self.operation_thread is not None

    def operation_stoppable(self):
        return self.operation_active() and bool(self.operation_stop_allowed)

    def check_cancelled(self, cancel_event=None):
        event = cancel_event or self.operation_cancel
        if event is not None and event.is_set():
            raise CancelledError("transfer stopped")

    def set_operation_process(self, proc):
        with self.state_lock:
            self.operation_process = proc

    def register_operation_resource(self, resource):
        if resource is None:
            return
        with self.state_lock:
            self.operation_resources.append(resource)

    def terminate_process(self, proc):
        if proc is None:
            return
        try:
            if proc.poll() is not None:
                return
        except Exception:
            return
        try:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
        except Exception:
            try:
                proc.kill()
            except Exception:
                pass

    def close_operation_resources(self):
        with self.state_lock:
            resources = list(self.operation_resources)
            self.operation_resources = []
            proc = self.operation_process
        self.terminate_process(proc)
        for resource in reversed(resources):
            try:
                resource.close()
            except Exception:
                pass

    def action_stop_transfer(self):
        if not self.operation_active():
            self.set_status("No transfer is running.", "warn")
            return
        if not self.operation_stop_allowed:
            self.set_status("Current operation cannot be stopped safely.", "warn")
            return
        if self.operation_cancel is not None:
            self.operation_cancel.set()
        with self.state_lock:
            if self.transfer_info is not None:
                self.transfer_info["stopping"] = True
        self.close_operation_resources()
        self.set_status("Stopping transfer...", "warn")

    def action_stop_phone_pcbridge(self):
        now = time.time()
        if now > self.phone_stop_armed_until:
            self.phone_stop_armed_until = now + 8
            self.delete_armed = None
            self.set_status("Press Ctrl+K again to stop phone pcbridge and exit aurorafs.", "warn")
            return False

        self.phone_stop_armed_until = 0.0
        payload = f"stop requested by aurorafs at {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}\n"
        try:
            with self.sftp.open(PHONE_STOP_REQUEST_PATH, "w") as fh:
                fh.write(payload)
            try:
                self.sftp.chmod(PHONE_STOP_REQUEST_PATH, 0o600)
            except Exception:
                pass
        except Exception as exc:
            self.set_status(f"Failed to stop phone pcbridge: {exc}", "error")
            return False

        self.set_status("Stop requested. Exiting aurorafs.", "ok")
        return True

    def operation_progress(self, ctx, current="", files_inc=0, bytes_inc=0, item_done=False, total_bytes=None, phase=None, force=False):
        if total_bytes is not None:
            ctx["total_bytes"] = max(0, int(total_bytes))
        if phase:
            ctx["phase"] = str(phase)
        if files_inc:
            ctx["files"] += int(files_inc)
        if bytes_inc > 0:
            ctx["bytes"] += int(bytes_inc)
        if item_done:
            ctx["done"] += 1
        if current:
            ctx["current"] = str(current)
        now = time.time()

        if ctx.get("show_progress"):
            with self.state_lock:
                if self.transfer_info is None:
                    self.transfer_info = {}
                self.transfer_info.update({
                    "label": ctx.get("label", self.operation_label),
                    "phase": ctx.get("phase", ""),
                    "done": int(ctx.get("done", 0)),
                    "total": int(ctx.get("total", 0)),
                    "bytes": int(ctx.get("bytes", 0)),
                    "total_bytes": int(ctx.get("total_bytes", 0)),
                    "current": str(ctx.get("current", "") or ""),
                    "started_at": float(ctx.get("started_at", self.operation_started_at or now)),
                    "stopping": bool(ctx.get("stopping", False)),
                })

        if not force and (now - ctx["last_emit"]) < 0.12:
            return
        ctx["last_emit"] = now
        total = int(ctx.get("total_bytes", 0))
        if total > 0:
            pct = min(100.0, (float(ctx["bytes"]) / float(total)) * 100.0)
            msg = f"{ctx['label']}: {human_size(ctx['bytes'])}/{human_size(total)} {pct:.0f}%"
        else:
            msg = f"{ctx['label']}: {ctx.get('phase', 'working')} {human_size(ctx['bytes'])}"
        if ctx.get("total", 0):
            msg = f"{msg} items {ctx['done']}/{ctx['total']}"
        cur = str(ctx.get("current", "") or "")
        if cur:
            msg = f"{msg} | {truncate_middle(cur, 70)}"
        self.set_status(msg, "warn")

    def start_background_operation(self, label, worker, stop_allowed=False, show_progress=False):
        if self.operation_active():
            self.set_status("Another operation is still running.", "warn")
            return False
        self.operation_label = str(label)
        self.operation_started_at = time.time()
        self.operation_result = None
        self.operation_cancel = threading.Event()
        self.operation_stop_allowed = bool(stop_allowed)
        self.operation_process = None
        self.operation_resources = []
        if show_progress:
            with self.state_lock:
                self.transfer_info = {
                    "label": self.operation_label,
                    "phase": "starting",
                    "done": 0,
                    "total": 0,
                    "bytes": 0,
                    "total_bytes": 0,
                    "current": "",
                    "started_at": self.operation_started_at,
                    "stopping": False,
                }
        else:
            with self.state_lock:
                self.transfer_info = None
        self.set_status(f"{self.operation_label}: starting...", "warn")

        def runner():
            try:
                payload = worker()
                self.operation_result = {"ok": True, "payload": payload}
            except CancelledError:
                self.operation_result = {"ok": False, "cancelled": True}
            except Exception as exc:
                if self.operation_cancel is not None and self.operation_cancel.is_set():
                    self.operation_result = {"ok": False, "cancelled": True}
                else:
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
        self.operation_cancel = None
        self.operation_stop_allowed = False
        self.operation_process = None
        self.operation_resources = []
        with self.state_lock:
            self.transfer_info = None
        if result.get("cancelled"):
            self.delete_armed = None
            self.refresh_all()
            self.set_status("Transfer stopped. Partial files may remain at the destination.", "warn")
            return
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

    def transfer_progress_line(self, width):
        with self.state_lock:
            info = dict(self.transfer_info or {})
        if not info:
            return ""
        label = str(info.get("label", "Transfer"))
        phase = str(info.get("phase", "") or "working")
        done = max(0, int(info.get("bytes", 0)))
        total = max(0, int(info.get("total_bytes", 0)))
        current = str(info.get("current", "") or "")
        started = float(info.get("started_at", time.time()) or time.time())
        elapsed = max(0.001, time.time() - started)
        rate = done / elapsed
        if info.get("stopping"):
            phase = "stopping"
        bar_w = max(10, min(28, width // 4))
        if total > 0:
            shown = min(done, total)
            filled = min(bar_w, int((shown / total) * bar_w))
            bar = "[" + "#" * filled + "-" * (bar_w - filled) + "]"
            pct = min(100.0, (shown / total) * 100.0)
            if rate > 0 and shown < total:
                eta = int((total - shown) / rate)
                eta_text = f" ETA {eta}s"
            else:
                eta_text = ""
            line = f"{label} {bar} {human_size(shown)}/{human_size(total)} {pct:.0f}% {human_size(rate)}/s{eta_text}"
        else:
            bar = "[" + "." * bar_w + "]"
            line = f"{label} {bar} {phase} {human_size(done)} {human_size(rate)}/s"
        if current:
            remaining = max(10, width - len(line) - 3)
            line = f"{line} | {truncate_middle(current, remaining)}"
        return truncate_middle(line, width)

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
        if p and os.name == "nt":
            p = os.path.normcase(os.path.normpath(p))
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
                    base = kp.rstrip("/\\")
                    if p == kp or p.startswith(base + "/") or p.startswith(base + "\\"):
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
        self.safe_add(h - 4, 0, " " * max(0, w - 1), self.color(6))
        self.safe_add(h - 4, 1, truncate_middle(f"{clip} | {selected}", w - 3), self.color(6))

        progress_line = self.transfer_progress_line(w - 3)
        progress_attr = self.color(3, curses.A_BOLD)
        self.safe_add(h - 3, 0, " " * max(0, w - 1), progress_attr)
        if progress_line:
            self.safe_add(h - 3, 1, progress_line, progress_attr)

        status_attr = self.color(1)
        with self.state_lock:
            status = self.status
            status_kind = self.status_kind
        if status_kind == "error":
            status_attr = self.color(5, curses.A_BOLD)
        elif status_kind == "warn":
            status_attr = self.color(3, curses.A_BOLD)
        elif status_kind == "ok":
            status_attr = self.color(4, curses.A_BOLD)
        self.safe_add(h - 2, 0, " " * max(0, w - 1), status_attr)
        self.safe_add(h - 2, 1, truncate_middle(status, w - 3), status_attr)

        if self.operation_active():
            help_text = "Transfer running | s stop transfer | Tab switch | Arrows move | Enter open folder | Back up | r refresh"
        else:
            help_text = "Tab pane | Enter open | Space select | ^K stop phone | c/m/p copy/move/paste | d del | r refresh | q quit"
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
        if h < 17 or w < 90:
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
        pane_h = h - 6
        split = w // 2
        local_w = split
        remote_w = w - split
        self.draw_pane("local", 0, pane_top, local_w, pane_h)
        self.draw_pane("remote", split, pane_top, remote_w, pane_h)

        self.draw_status_lines(h, w)
        self.draw_menu()
        self.stdscr.refresh()

    def remote_exists(self, path, follow_symlinks=True, sftp=None):
        client = sftp or self.sftp
        try:
            if follow_symlinks:
                client.stat(path)
            else:
                client.lstat(path)
            return True
        except Exception:
            return False

    def remote_lstat(self, path, sftp=None):
        return (sftp or self.sftp).lstat(path)

    def remote_is_symlink(self, path, sftp=None):
        try:
            return stat.S_ISLNK(self.remote_lstat(path, sftp=sftp).st_mode)
        except Exception:
            return False

    def remote_is_dir(self, path, follow_symlinks=False, sftp=None):
        client = sftp or self.sftp
        st = client.stat(path) if follow_symlinks else self.remote_lstat(path, sftp=client)
        return stat.S_ISDIR(st.st_mode)

    def remote_mkdir_p(self, path, cache=None, sftp=None):
        client = sftp or self.sftp
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
                client.stat(cur)
                if cache is not None:
                    cache.add(cur)
            except FileNotFoundError:
                client.mkdir(cur)
                if cache is not None:
                    cache.add(cur)
            except IOError:
                try:
                    client.mkdir(cur)
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

    def remote_unique_target(self, base_dir, name, avoid_path=None, sftp=None):
        base = remote_join(base_dir, name)
        if not self.remote_exists(base, sftp=sftp) or (avoid_path and base == avoid_path):
            return base
        stem, suffix = os.path.splitext(name)
        for i in range(2, 1000):
            cand = remote_join(base_dir, f"{stem} ({i}){suffix}")
            if not self.remote_exists(cand, sftp=sftp):
                return cand
        return base

    def local_path_bytes(self, path, cancel_event=None):
        self.check_cancelled(cancel_event)
        p = Path(path)
        total = 0
        files = 0
        try:
            if p.is_dir() and not p.is_symlink():
                for root, dirs, names in os.walk(p):
                    self.check_cancelled(cancel_event)
                    for name in names:
                        fp = Path(root) / name
                        try:
                            total += int(fp.stat().st_size)
                            files += 1
                        except Exception:
                            continue
                return total, files
            return int(p.stat().st_size), 1
        except Exception:
            return 0, 0

    def observed_local_bytes(self, path):
        try:
            return self.local_path_bytes(path)[0]
        except Exception:
            return 0

    def remote_path_bytes(self, path, st=None, sftp=None, cancel_event=None):
        self.check_cancelled(cancel_event)
        client = sftp or self.sftp
        if st is None:
            st = client.lstat(path)
        mode = int(getattr(st, "st_mode", 0))
        if stat.S_ISLNK(mode):
            raise RuntimeError(f"Refusing to copy symlink from phone: {path}")
        if stat.S_ISDIR(mode):
            total = 0
            files = 0
            for item in client.listdir_attr(path):
                self.check_cancelled(cancel_event)
                child = posixpath.join(path, item.filename) if path != "/" else "/" + item.filename
                child_total, child_files = self.remote_path_bytes(child, st=item, sftp=client, cancel_event=cancel_event)
                total += child_total
                files += child_files
            return total, files
        return int(getattr(st, "st_size", 0)), 1

    def observed_remote_bytes(self, path, sftp=None):
        try:
            return self.remote_path_bytes(path, sftp=sftp)[0]
        except Exception:
            return 0

    def open_transfer_connection(self):
        cfg = self.cfg
        host = str(cfg.get("host", "")).strip()
        if not host:
            raise RuntimeError("Missing host in config")
        port = int(cfg.get("ssh_port", 2223))
        username = str(cfg.get("username", "root")).strip() or "root"
        key_path = os.path.expanduser(str(cfg.get("key_path", "~/aurora-pcbridge/id_ed25519")))
        known_hosts_path = os.path.expanduser(str(cfg.get("known_hosts_path", "~/aurora-pcbridge/known_hosts")))
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
        self.register_operation_resource(ssh)
        sftp = open_optimized_sftp(ssh)
        try:
            sftp.get_channel().settimeout(60)
        except Exception:
            pass
        self.register_operation_resource(sftp)
        return ssh, sftp

    def sftp_batch_quote(self, path):
        text = str(path)
        text = text.replace("\\", "\\\\")
        text = text.replace('"', '\\"')
        text = text.replace("\r", "\\r")
        text = text.replace("\n", "\\n")
        return f'"{text}"'

    def sftp_local_path(self, path):
        text = str(path)
        if os.name == "nt":
            text = text.replace("\\", "/")
        return text

    def native_sftp_base_cmd(self):
        sftp_bin = shutil.which("sftp")
        if not sftp_bin:
            return None
        host = str(self.cfg.get("host", "") or "").strip()
        if not host:
            return None
        try:
            port = int(self.cfg.get("ssh_port", 2223))
        except Exception:
            port = 2223
        username = str(self.cfg.get("username", "root") or "root").strip() or "root"
        key_path = os.path.expanduser(str(self.cfg.get("key_path", "~/aurora-pcbridge/id_ed25519")))
        known_hosts_path = os.path.expanduser(str(self.cfg.get("known_hosts_path", "~/aurora-pcbridge/known_hosts")))
        if not os.path.isfile(key_path) or not os.path.isfile(known_hosts_path):
            return None
        return [
            sftp_bin,
            "-q",
            "-b",
            "-",
            "-P",
            str(port),
            "-i",
            key_path,
            "-o",
            "BatchMode=yes",
            "-o",
            "IdentitiesOnly=yes",
            "-o",
            f"UserKnownHostsFile={known_hosts_path}",
            "-o",
            "StrictHostKeyChecking=yes",
            "-o",
            "Compression=no",
            f"{username}@{host}",
        ]

    def run_native_sftp_batch(self, batch, cancel_event=None, progress_poll=None, poll_interval=0.20):
        cmd = self.native_sftp_base_cmd()
        if not cmd:
            return False
        proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.set_operation_process(proc)
        output = {"stdout": "", "stderr": "", "error": ""}

        def communicate():
            try:
                out, err = proc.communicate(batch)
                output["stdout"] = out or ""
                output["stderr"] = err or ""
            except Exception as exc:
                output["error"] = str(exc)

        io_thread = threading.Thread(target=communicate, daemon=True)
        io_thread.start()
        poll_interval = max(0.05, float(poll_interval))
        try:
            while io_thread.is_alive():
                if cancel_event is not None and cancel_event.is_set():
                    self.terminate_process(proc)
                    raise CancelledError("transfer stopped")
                if progress_poll:
                    try:
                        progress_poll()
                    except CancelledError:
                        self.terminate_process(proc)
                        raise
                io_thread.join(poll_interval)
            if progress_poll:
                progress_poll()
            if cancel_event is not None and cancel_event.is_set():
                self.terminate_process(proc)
                raise CancelledError("transfer stopped")
        finally:
            self.set_operation_process(None)
        if output.get("error"):
            raise RuntimeError(output["error"])
        if proc.returncode != 0:
            msg = (output.get("stderr") or output.get("stdout") or "").strip()
            if len(msg) > 220:
                msg = msg[:220] + "..."
            raise RuntimeError(f"native sftp failed ({proc.returncode}){': ' + msg if msg else ''}")
        return True

    def copy_local_to_remote(self, src, dst, mkdir_cache=None, progress=None, allow_native=True, sftp=None, cancel_event=None, expected_bytes=None):
        client = sftp or self.sftp
        self.check_cancelled(cancel_event)
        src_p = Path(src)
        self.remote_mkdir_p(posixpath.dirname(dst) or "/", cache=mkdir_cache, sftp=client)
        size = int(expected_bytes) if expected_bytes is not None else self.local_path_bytes(src_p, cancel_event=cancel_event)[0]
        if allow_native:
            seen = 0
            try:
                op = "put -r" if src_p.is_dir() else "put"
                batch = f"{op} {self.sftp_batch_quote(self.sftp_local_path(src_p))} {self.sftp_batch_quote(dst)}\n"
                self.set_status(f"Fast sftp upload: {truncate_middle(str(src_p), 70)}", "warn")

                def poll():
                    nonlocal seen
                    current = self.observed_remote_bytes(dst, sftp=client)
                    if size > 0:
                        current = min(current, size)
                    delta = max(0, current - seen)
                    if delta:
                        seen = current
                        if progress:
                            progress(str(src_p), delta)

                poll_interval = 1.0 if src_p.is_dir() else 0.20
                if self.run_native_sftp_batch(batch, cancel_event=cancel_event, progress_poll=poll, poll_interval=poll_interval):
                    poll()
                    if size > 0 and seen < size and progress:
                        progress(str(src_p), size - seen)
                    if progress:
                        progress(str(src_p), 0)
                    return
            except Exception as exc:
                self.check_cancelled(cancel_event)
                if seen > 0:
                    raise RuntimeError(f"fast sftp upload failed after partial transfer: {exc}")
                self.set_status(f"Fast sftp upload fallback: {exc}", "warn")
        if src_p.is_dir():
            self.remote_mkdir_p(dst, cache=mkdir_cache, sftp=client)
            for item in src_p.iterdir():
                self.check_cancelled(cancel_event)
                child_dst = posixpath.join(dst, item.name)
                self.copy_local_to_remote(str(item), child_dst, mkdir_cache=mkdir_cache, progress=progress, allow_native=False, sftp=client, cancel_event=cancel_event)
            return
        sent = 0

        def cb(transferred, total):
            nonlocal sent
            self.check_cancelled(cancel_event)
            delta = max(0, int(transferred) - sent)
            if delta:
                sent += delta
                if progress:
                    progress(str(src_p), delta)

        try:
            client.put(str(src_p), dst, callback=cb, confirm=False)
        except TypeError:
            client.put(str(src_p), dst, callback=cb)
        if size > 0 and sent < size and progress:
            progress(str(src_p), size - sent)

    def copy_remote_to_local(self, src, dst, st=None, progress=None, allow_native=True, sftp=None, cancel_event=None, expected_bytes=None):
        client = sftp or self.sftp
        self.check_cancelled(cancel_event)
        if st is None:
            st = self.remote_lstat(src, sftp=client)
        mode = int(getattr(st, "st_mode", 0))
        if stat.S_ISLNK(mode):
            raise RuntimeError(f"Refusing to copy symlink from phone: {src}")
        parent = os.path.dirname(dst)
        if parent:
            os.makedirs(parent, exist_ok=True)
        if allow_native:
            seen = 0
            try:
                op = "get -r" if stat.S_ISDIR(mode) else "get"
                batch = f"{op} {self.sftp_batch_quote(src)} {self.sftp_batch_quote(self.sftp_local_path(dst))}\n"
                self.set_status(f"Fast sftp download: {truncate_middle(src, 70)}", "warn")
                size = int(expected_bytes) if expected_bytes is not None else int(getattr(st, "st_size", 0))

                def poll():
                    nonlocal seen
                    current = self.observed_local_bytes(dst)
                    if size > 0:
                        current = min(current, size)
                    delta = max(0, current - seen)
                    if delta:
                        seen = current
                        if progress:
                            progress(src, delta)

                poll_interval = 1.0 if stat.S_ISDIR(mode) else 0.20
                if self.run_native_sftp_batch(batch, cancel_event=cancel_event, progress_poll=poll, poll_interval=poll_interval):
                    poll()
                    if size > 0 and seen < size and progress:
                        progress(src, size - seen)
                    if progress:
                        progress(src, 0)
                    return
            except Exception as exc:
                self.check_cancelled(cancel_event)
                if seen > 0:
                    raise RuntimeError(f"fast sftp download failed after partial transfer: {exc}")
                self.set_status(f"Fast sftp download fallback: {exc}", "warn")
        if stat.S_ISDIR(mode):
            os.makedirs(dst, exist_ok=True)
            for item in client.listdir_attr(src):
                self.check_cancelled(cancel_event)
                child_src = posixpath.join(src, item.filename) if src != "/" else "/" + item.filename
                child_dst = os.path.join(dst, item.filename)
                self.copy_remote_to_local(child_src, child_dst, st=item, progress=progress, allow_native=False, sftp=client, cancel_event=cancel_event)
            return
        received = 0

        def cb(transferred, total):
            nonlocal received
            self.check_cancelled(cancel_event)
            delta = max(0, int(transferred) - received)
            if delta:
                received += delta
                if progress:
                    progress(src, delta)

        try:
            client.get(src, dst, callback=cb, prefetch=True)
        except TypeError:
            client.get(src, dst, callback=cb)
        size = int(expected_bytes) if expected_bytes is not None else int(getattr(st, "st_size", 0))
        if size > 0 and received < size and progress:
            progress(src, size - received)

    def copy_file_local(self, src, dst, progress=None, cancel_event=None):
        total = 0
        sent = 0
        try:
            total = int(Path(src).stat().st_size)
        except Exception:
            total = 0
        os.makedirs(os.path.dirname(dst) or ".", exist_ok=True)
        with open(src, "rb") as in_fh, open(dst, "wb") as out_fh:
            while True:
                self.check_cancelled(cancel_event)
                chunk = in_fh.read(1024 * 1024)
                if not chunk:
                    break
                out_fh.write(chunk)
                sent += len(chunk)
                if progress:
                    progress(src, len(chunk))
        try:
            shutil.copystat(src, dst)
        except Exception:
            pass
        if total > 0 and sent < total and progress:
            progress(src, total - sent)

    def copy_local_to_local(self, src, dst, progress=None, cancel_event=None):
        self.check_cancelled(cancel_event)
        src_p = Path(src)
        if src_p.is_dir():
            os.makedirs(dst, exist_ok=True)
            for item in src_p.iterdir():
                self.check_cancelled(cancel_event)
                self.copy_local_to_local(str(item), str(Path(dst) / item.name), progress=progress, cancel_event=cancel_event)
            try:
                shutil.copystat(src, dst)
            except Exception:
                pass
            return
        self.copy_file_local(str(src_p), str(dst), progress=progress, cancel_event=cancel_event)

    def remote_delete(self, path, st=None, progress=None, sftp=None, cancel_event=None):
        client = sftp or self.sftp
        self.check_cancelled(cancel_event)
        if st is None:
            st = self.remote_lstat(path, sftp=client)
        mode = int(getattr(st, "st_mode", 0))
        if stat.S_ISLNK(mode):
            client.remove(path)
            if progress:
                progress(path, int(getattr(st, "st_size", 0)))
            return
        if stat.S_ISDIR(mode):
            for item in client.listdir_attr(path):
                self.check_cancelled(cancel_event)
                child = posixpath.join(path, item.filename) if path != "/" else "/" + item.filename
                self.remote_delete(child, st=item, progress=progress, sftp=client, cancel_event=cancel_event)
            client.rmdir(path)
            return
        client.remove(path)
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
            if os.name == "nt" and hasattr(os, "startfile"):
                os.startfile(target)
                return True
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
            stamp = time.time_ns() if hasattr(time, "time_ns") else int(time.time() * 1000000)
            target = self.open_cache_dir / f"{stamp}-{safe_name}"
            src_path = str(row["path"])
            dst_path = str(target)
            ctx = {
                "label": "Open file",
                "total": 1,
                "done": 0,
                "files": 0,
                "bytes": 0,
                "total_bytes": 0,
                "current": src_path,
                "phase": "Scanning",
                "started_at": time.time(),
                "last_emit": 0.0,
                "show_progress": True,
            }

            def progress_cb(path, size):
                self.operation_progress(ctx, current=path, bytes_inc=size)

            def worker():
                cancel_event = self.operation_cancel
                ssh = None
                transfer_sftp = None
                try:
                    ssh, transfer_sftp = self.open_transfer_connection()
                    total_bytes, _ = self.remote_path_bytes(src_path, sftp=transfer_sftp, cancel_event=cancel_event)
                    ctx["started_at"] = time.time()
                    self.operation_progress(ctx, current=src_path, total_bytes=total_bytes, phase="Transferring", force=True)
                    self.copy_remote_to_local(src_path, dst_path, progress=progress_cb, sftp=transfer_sftp, cancel_event=cancel_event, expected_bytes=total_bytes)
                    self.operation_progress(ctx, current=src_path, item_done=True, force=True)
                    self.check_cancelled(cancel_event)
                    opened = self.open_with_default_app(dst_path)
                    return {
                        "kind": "open",
                        "opened": bool(opened),
                        "target": dst_path,
                    }
                finally:
                    for resource in (transfer_sftp, ssh):
                        try:
                            if resource is not None:
                                resource.close()
                        except Exception:
                            pass

            self.start_background_operation("Open file", worker, stop_allowed=True, show_progress=True)
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

    def action_open_dir_only(self):
        row = self.selected()
        if not row:
            return
        if row.get("is_dir"):
            self.clear_selection(self.active)
            self.action_open()
        else:
            self.set_status("Transfer running. File actions are locked until it finishes.", "warn")

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
        if self.operation_active():
            self.set_status("Transfer running. Copy/move is locked until it finishes.", "warn")
            return
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
            "total_bytes": 0,
            "current": "",
            "phase": "Scanning",
            "started_at": time.time(),
            "last_emit": 0.0,
            "show_progress": True,
        }

        def transfer_progress(path, size):
            self.operation_progress(ctx, current=path, bytes_inc=size)

        def worker():
            cancel_event = self.operation_cancel
            done = 0
            mkdir_cache = {"/"}
            ssh = None
            transfer_sftp = None
            try:
                if src_side == "remote" or dst_side == "remote":
                    ssh, transfer_sftp = self.open_transfer_connection()

                item_sizes = {}
                total_bytes = 0
                self.operation_progress(ctx, phase="Scanning", force=True)
                for item in items:
                    self.check_cancelled(cancel_event)
                    src_path = str(item.get("path", ""))
                    name = item.get("name", "item")
                    if src_side == "remote":
                        item_bytes, _ = self.remote_path_bytes(src_path, sftp=transfer_sftp, cancel_event=cancel_event)
                    else:
                        item_bytes, _ = self.local_path_bytes(src_path, cancel_event=cancel_event)
                    item_sizes[src_path] = item_bytes
                    total_bytes += item_bytes
                    self.operation_progress(ctx, current=name, total_bytes=total_bytes, phase="Scanning", force=True)

                ctx["started_at"] = time.time()
                self.operation_progress(ctx, total_bytes=total_bytes, phase="Transferring", force=True)

                for item in items:
                    self.check_cancelled(cancel_event)
                    src_path = str(item.get("path", ""))
                    name = item.get("name", "item")
                    expected = int(item_sizes.get(src_path, 0))
                    if src_side == "local" and dst_side == "remote":
                        target = self.remote_unique_target(remote_cwd, name, avoid_path=src_path if src_side == dst_side else None, sftp=transfer_sftp)
                        self.copy_local_to_remote(src_path, target, mkdir_cache=mkdir_cache, progress=transfer_progress, sftp=transfer_sftp, cancel_event=cancel_event, expected_bytes=expected)
                        if mode == "move":
                            self.check_cancelled(cancel_event)
                            self.operation_progress(ctx, current=name, phase="Deleting source", force=True)
                            self.local_delete(src_path)
                    elif src_side == "remote" and dst_side == "local":
                        target = self.local_unique_target(local_cwd, name, avoid_path=src_path if src_side == dst_side else None)
                        self.copy_remote_to_local(src_path, str(target), progress=transfer_progress, sftp=transfer_sftp, cancel_event=cancel_event, expected_bytes=expected)
                        if mode == "move":
                            self.check_cancelled(cancel_event)
                            self.operation_progress(ctx, current=name, phase="Deleting source", force=True)
                            self.remote_delete(src_path, sftp=transfer_sftp, cancel_event=cancel_event)
                    elif src_side == "local" and dst_side == "local":
                        target = self.local_unique_target(local_cwd, name, avoid_path=src_path)
                        if mode == "move":
                            try:
                                os.rename(src_path, str(target))
                                if expected > 0:
                                    transfer_progress(src_path, expected)
                            except OSError:
                                self.copy_local_to_local(src_path, str(target), progress=transfer_progress, cancel_event=cancel_event)
                                self.check_cancelled(cancel_event)
                                self.local_delete(src_path)
                        else:
                            self.copy_local_to_local(src_path, str(target), progress=transfer_progress, cancel_event=cancel_event)
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
            finally:
                for resource in (transfer_sftp, ssh):
                    try:
                        if resource is not None:
                            resource.close()
                    except Exception:
                        pass

        self.start_background_operation(f"{mode.title()} {src_side}->{dst_side}", worker, stop_allowed=True, show_progress=True)

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

    def handle_mouse(self, navigation_only=False):
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

        if navigation_only:
            self.close_menu()

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
            if navigation_only:
                self.set_status("Transfer running. Menu actions are locked until it finishes.", "warn")
                return
            if ctrl_down and row is not None:
                self.toggle_select_row(side, row)
                return
            self.show_context_menu(side, idx, mx, my)
            return

        if bstate & (b1_click | b1_press | b1_double):
            if navigation_only:
                if ctrl_down:
                    self.set_status("Transfer running. Selection changes are locked until it finishes.", "warn")
                    return
                if row is not None and row.get("is_dir"):
                    self.clear_selection(side)
                    self.action_open()
                else:
                    self.set_status("Transfer running. File actions are locked until it finishes.", "warn")
                return
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

            if key == curses.KEY_RESIZE:
                self.set_status("Layout updated after resize.", "ok")
                continue

            if key == curses.KEY_MOUSE:
                self.handle_mouse(navigation_only=self.operation_active())
                continue

            if self.operation_active():
                if key == CTRL_K:
                    self.set_status("Transfer running. Stop it first with s before stopping phone pcbridge.", "warn")
                    continue
                if key in (ord("s"), ord("S")):
                    self.action_stop_transfer()
                    continue
                if key in (ord("q"), ord("Q")):
                    self.set_status("Transfer running. Stop it first with s before quitting.", "warn")
                    continue
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
                if key in (10, 13, curses.KEY_RIGHT):
                    self.action_open_dir_only()
                    continue
                if key in (curses.KEY_BACKSPACE, 127, 8, curses.KEY_LEFT):
                    self.action_up()
                    continue
                if key in (ord("r"), ord("R")):
                    self.refresh_all()
                    self.set_status("Refreshed.", "ok")
                    continue
                if key in (ord(" "), ord("c"), ord("C"), ord("m"), ord("M"), ord("p"), ord("P"), ord("d"), ord("D"), curses.KEY_DC, ord("o"), ord("O")):
                    self.set_status("Transfer running. File actions are locked; use s to stop.", "warn")
                    continue
                self.set_status("Transfer running. Browse is available; file actions are locked.", "warn")
                continue

            if self.handle_menu_keys(key):
                continue

            if key == CTRL_K:
                if self.action_stop_phone_pcbridge():
                    return
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


def open_optimized_sftp(ssh):
    transport = ssh.get_transport()
    if transport is not None:
        try:
            transport.set_keepalive(30)
        except Exception:
            pass
        try:
            sftp = paramiko.SFTPClient.from_transport(
                transport,
                window_size=FAST_SFTP_WINDOW_SIZE,
                max_packet_size=FAST_SFTP_MAX_PACKET_SIZE,
            )
            if sftp is not None:
                return sftp
        except TypeError:
            pass
        except Exception:
            pass
    return ssh.open_sftp()


def main():
    parser = argparse.ArgumentParser(description="aurorafs TUI client")
    parser.add_argument("--config", default=os.path.expanduser("~/aurora-pcbridge/config.json"))
    parser.add_argument("--local-root", default="", help="Override initial local pane path")
    args, extras = parser.parse_known_args()

    cfg = load_config(os.path.expanduser(args.config))
    local_override = str(getattr(args, "local_root", "") or "").strip()
    if local_override:
        cfg["local_root"] = os.path.expanduser(local_override)
    elif extras:
        # Ignore extra trailing args here because shell aliases or functions may append them.
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
    key_path = os.path.expanduser(str(cfg.get("key_path", "~/aurora-pcbridge/id_ed25519")))
    known_hosts_path = os.path.expanduser(str(cfg.get("known_hosts_path", "~/aurora-pcbridge/known_hosts")))
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
    sftp = open_optimized_sftp(ssh)
    try:
        sftp.get_channel().settimeout(60)
    except Exception:
        pass
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
AURORA_DONE_REPORTED=0

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

report_event() {
  local event="$1"
  local url="$AURORA_BASE_URL/event?token=$AURORA_TOKEN&event=$event"
  local py_bin=""
  if command -v curl >/dev/null 2>&1; then
    curl -fsS -X POST "$url" >/dev/null 2>&1 && return 0
  fi
  py_bin="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)"
  if [[ -n "$py_bin" ]]; then
    "$py_bin" - "$url" <<'PY_EVENT' >/dev/null 2>&1 || true
import sys
import urllib.request

req = urllib.request.Request(sys.argv[1], method="POST")
urllib.request.urlopen(req, timeout=5).read()
PY_EVENT
  fi
}

report_failure_on_exit() {
  local rc=$?
  if [[ "$rc" -ne 0 && "$AURORA_DONE_REPORTED" != "1" ]]; then
    report_event bootstrap_failed
  fi
  exit "$rc"
}

trap report_failure_on_exit EXIT

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

ROOT_DIR="$HOME/aurora-pcbridge"
CONF_DIR="$ROOT_DIR"
APP_DIR="$ROOT_DIR"
BIN_DIR="$ROOT_DIR"
step "Preparing local directories"
mkdir -p "$ROOT_DIR"
ok "created/verified: $ROOT_DIR"

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
APP_DIR="$HOME/aurora-pcbridge"
CFG_PATH="$HOME/aurora-pcbridge/config.json"
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
    printf '%s\n' 'alias aurorafs="$HOME/aurora-pcbridge/aurorafs"'
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
AURORA_DONE_REPORTED=1
report_event setup_done
echo "Run now: aurorafs"
'''

BOOTSTRAP_PS1_TEMPLATE = r'''$ErrorActionPreference = "Stop"

$AuroraBaseUrl = "__BASE_URL__"
$AuroraToken = "__TOKEN__"
$AuroraSshPort = "__SSH_PORT__"
$AuroraHostKeyEd25519 = "__HOSTKEY_ED25519__"
$AuroraHostKeyRsa = "__HOSTKEY_RSA__"
$AuroraBashBootstrapB64 = "__BASH_BOOTSTRAP_B64__"
$AuroraDoneReported = $false
$AuroraStep = 0

function Step([string]$Text) {
  $script:AuroraStep += 1
  "[{0:D2}] {1}" -f $script:AuroraStep, $Text
}

function Ok([string]$Text) {
  "     [ok] $Text"
}

function Note([string]$Text) {
  "     [..] $Text"
}

function Report-Event([string]$Event) {
  try {
    Invoke-RestMethod -Method Post -Uri "$AuroraBaseUrl/event?token=$AuroraToken&event=$Event" | Out-Null
  } catch {
  }
}

trap {
  if (-not $script:AuroraDoneReported) {
    Report-Event "bootstrap_failed"
  }
  throw
}

function Test-WindowsRuntime {
  return [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
}

function Invoke-EmbeddedBash([string]$PayloadB64) {
  $bash = Get-Command bash -ErrorAction SilentlyContinue
  if (-not $bash) {
    throw "PowerShell is not running on Windows, and bash was not found for WSL/Linux setup."
  }
  $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("aurorafs-" + [System.Guid]::NewGuid().ToString("N") + ".sh")
  [System.IO.File]::WriteAllBytes($tmp, [System.Convert]::FromBase64String($PayloadB64))
  try {
    & $bash.Source $tmp
    if ($LASTEXITCODE -ne 0) {
      exit $LASTEXITCODE
    }
  } finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  }
}

function Require-Command([string[]]$Names, [string]$Label) {
  foreach ($name in $Names) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) {
      return $cmd.Source
    }
  }
  throw "Missing $Label. Install it, then run Aurora pcbridge setup again."
}

function Test-PythonModule([string]$Python, [string]$Module) {
  & $Python -c "import importlib.util, sys; sys.exit(0 if importlib.util.find_spec(sys.argv[1]) is not None else 1)" $Module *> $null
  return $LASTEXITCODE -eq 0
}

Step "Starting aurorafs first-time setup"
Ok "bootstrap endpoint reachable at $AuroraBaseUrl"

if (-not (Test-WindowsRuntime)) {
  Step "Using WSL/Linux setup path"
  Invoke-EmbeddedBash $AuroraBashBootstrapB64
  exit 0
}

Step "Checking required tools on Windows"
$SshKeygen = Require-Command @("ssh-keygen.exe", "ssh-keygen") "OpenSSH Client ssh-keygen"
$null = Require-Command @("sftp.exe", "sftp") "OpenSSH Client sftp"
$PythonExe = $null
$PythonPrefix = @()
$PyLauncher = Get-Command py.exe -ErrorAction SilentlyContinue
if ($PyLauncher) {
  $PythonExe = $PyLauncher.Source
  $PythonPrefix = @("-3")
} else {
  $PythonCmd = Get-Command python.exe -ErrorAction SilentlyContinue
  if (-not $PythonCmd) {
    $PythonCmd = Get-Command python -ErrorAction SilentlyContinue
  }
  if (-not $PythonCmd) {
    throw "Missing Python 3. Install Python 3 for Windows, then run Aurora pcbridge setup again."
  }
  $PythonExe = $PythonCmd.Source
}
Ok "required tools are available"

$HomeDir = [Environment]::GetFolderPath("UserProfile")
if ([string]::IsNullOrWhiteSpace($HomeDir)) {
  $HomeDir = $HOME
}
$RootDir = Join-Path $HomeDir "aurora-pcbridge"
$ConfDir = $RootDir
$AppDir = $RootDir
$BinDir = $RootDir
$VenvDir = Join-Path $RootDir ".venv"
$ClientPython = Join-Path $VenvDir "Scripts\python.exe"

Step "Preparing local directories"
New-Item -ItemType Directory -Path $RootDir -Force | Out-Null
Ok "created/verified: $RootDir"

Step "Resolving Python runtime for aurorafs client"
if (-not (Test-Path -LiteralPath $ClientPython)) {
  & $PythonExe @PythonPrefix -m venv $VenvDir
  if ($LASTEXITCODE -ne 0) {
    throw "failed to create Python virtualenv"
  }
  Ok "virtualenv created at $VenvDir"
}

& $ClientPython -m pip --version *> $null
if ($LASTEXITCODE -ne 0) {
  & $ClientPython -m ensurepip --upgrade *> $null
}
& $ClientPython -m pip --version *> $null
if ($LASTEXITCODE -ne 0) {
  throw "pip is unavailable in virtualenv"
}

if ((-not (Test-PythonModule $ClientPython "paramiko")) -or (-not (Test-PythonModule $ClientPython "curses"))) {
  & $ClientPython -m pip install --upgrade pip *> $null
  & $ClientPython -m pip install --upgrade paramiko windows-curses
  if ($LASTEXITCODE -ne 0) {
    throw "failed to install aurorafs Python dependencies"
  }
  Ok "installed Python dependencies in virtualenv"
}
Ok "python runtime ready: $ClientPython"

Step "Downloading aurorafs client UI"
$ClientPath = Join-Path $AppDir "aurorafs_client.py"
Invoke-WebRequest -Uri "$AuroraBaseUrl/client.py?token=$AuroraToken" -OutFile $ClientPath
Ok "client saved to $ClientPath"

Step "Preparing SSH key for key-only pairing"
$KeyPath = Join-Path $ConfDir "id_ed25519"
$PubKeyPath = "$KeyPath.pub"
if (-not (Test-Path -LiteralPath $KeyPath)) {
  & $SshKeygen -t ed25519 -N "" -f $KeyPath *> $null
  if ($LASTEXITCODE -ne 0) {
    throw "failed to generate SSH keypair"
  }
  Ok "generated new keypair at $KeyPath"
} else {
  Ok "reusing existing keypair at $KeyPath"
}

Step "Pairing this Windows key with phone pcbridge service"
Invoke-RestMethod -Method Post -Uri "$AuroraBaseUrl/pair?token=$AuroraToken" -InFile $PubKeyPath -ContentType "text/plain" | Out-Null
Ok "public key accepted by phone"

Step "Writing aurorafs connection config"
$AuroraUri = [System.Uri]$AuroraBaseUrl
$AuroraHost = $AuroraUri.Host
if ([string]::IsNullOrWhiteSpace($AuroraHost)) {
  throw "failed parsing host from bootstrap URL"
}

$KnownHostsPath = Join-Path $ConfDir "known_hosts"
$KnownHostLines = @()
if (-not [string]::IsNullOrWhiteSpace($AuroraHostKeyEd25519)) {
  $KnownHostLines += "[$AuroraHost]:$AuroraSshPort ssh-ed25519 $AuroraHostKeyEd25519"
}
if (-not [string]::IsNullOrWhiteSpace($AuroraHostKeyRsa)) {
  $KnownHostLines += "[$AuroraHost]:$AuroraSshPort ssh-rsa $AuroraHostKeyRsa"
}
if ($KnownHostLines.Count -lt 1) {
  throw "missing server host key data"
}
Set-Content -LiteralPath $KnownHostsPath -Value $KnownHostLines -Encoding ASCII
Ok "pinned phone SSH host key(s) in $KnownHostsPath"

$Desktop = Join-Path $HomeDir "Desktop"
$LocalRoot = if (Test-Path -LiteralPath $Desktop -PathType Container) { $Desktop } else { $HomeDir }
$ConfigPath = Join-Path $ConfDir "config.json"
$Config = [ordered]@{
  host = $AuroraHost
  ssh_port = [int]$AuroraSshPort
  username = "root"
  remote_root = "/storage"
  local_root = $LocalRoot
  key_path = $KeyPath
  known_hosts_path = $KnownHostsPath
}
$Config | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
Ok "config written to $ConfigPath"

Step "Installing aurorafs launcher command"
$LauncherPath = Join-Path $BinDir "aurorafs.cmd"
$Launcher = @"
@echo off
set "APP_DIR=%USERPROFILE%\aurora-pcbridge"
set "CFG_PATH=%USERPROFILE%\aurora-pcbridge\config.json"
if exist "%APP_DIR%\.venv\Scripts\python.exe" (
  "%APP_DIR%\.venv\Scripts\python.exe" "%APP_DIR%\aurorafs_client.py" --config "%CFG_PATH%" %*
) else (
  python "%APP_DIR%\aurorafs_client.py" --config "%CFG_PATH%" %*
)
"@
Set-Content -LiteralPath $LauncherPath -Value $Launcher -Encoding ASCII
Ok "launcher installed at $LauncherPath"

function Update-ProfileBlock([string]$File) {
  $start = "# >>> aurorafs >>>"
  $end = "# <<< aurorafs <<<"
  $parent = Split-Path -Parent $File
  if (-not [string]::IsNullOrWhiteSpace($parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
  }
  $existing = @()
  if (Test-Path -LiteralPath $File) {
    $existing = @(Get-Content -LiteralPath $File)
  }
  $out = New-Object System.Collections.Generic.List[string]
  $skip = $false
  foreach ($line in $existing) {
    if ($line -eq $start) {
      $skip = $true
      continue
    }
    if ($line -eq $end) {
      $skip = $false
      continue
    }
    if (-not $skip) {
      $out.Add($line)
    }
  }
  $out.Add($start)
  $out.Add('function aurorafs { & "$HOME\aurora-pcbridge\aurorafs.cmd" @args }')
  $out.Add($end)
  Set-Content -LiteralPath $File -Value $out -Encoding UTF8
}

Step "Updating PowerShell alias"
Update-ProfileBlock $PROFILE
function aurorafs { & "$HOME\aurora-pcbridge\aurorafs.cmd" @args }
Ok "updated alias block in $PROFILE"

Step "Setup completed"
Ok "aurorafs is ready"
$script:AuroraDoneReported = $true
Report-Event "setup_done"
echo "Run now: aurorafs"
'''

CLEANUP_TEMPLATE = r'''#!/usr/bin/env bash
set -euo pipefail

AURORA_BASE_URL="__BASE_URL__"
AURORA_TOKEN="__TOKEN__"
AURORA_DONE_REPORTED=0
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

report_event() {
  local event="$1"
  local url="$AURORA_BASE_URL/event?token=$AURORA_TOKEN&event=$event"
  local py_bin=""
  if command -v curl >/dev/null 2>&1; then
    curl -fsS -X POST "$url" >/dev/null 2>&1 && return 0
  fi
  py_bin="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)"
  if [[ -n "$py_bin" ]]; then
    "$py_bin" - "$url" <<'PY_EVENT' >/dev/null 2>&1 || true
import sys
import urllib.request

req = urllib.request.Request(sys.argv[1], method="POST")
urllib.request.urlopen(req, timeout=5).read()
PY_EVENT
  fi
}

report_failure_on_exit() {
  local rc=$?
  if [[ "$rc" -ne 0 && "$AURORA_DONE_REPORTED" != "1" ]]; then
    report_event cleanup_failed
  fi
  exit "$rc"
}

trap report_failure_on_exit EXIT

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
remove_tree "$HOME/aurora-pcbridge"

step "Removing opened-file cache"
CACHE_CANDIDATES=()
if [[ -n "${TMPDIR:-}" ]]; then
  CACHE_CANDIDATES+=("$TMPDIR/aurorafs-open")
fi
if [[ -n "${TEMP:-}" ]]; then
  CACHE_CANDIDATES+=("$TEMP/aurorafs-open")
fi
if [[ -n "${TMP:-}" ]]; then
  CACHE_CANDIDATES+=("$TMP/aurorafs-open")
fi
CACHE_CANDIDATES+=("/tmp/aurorafs-open")
for cache_dir in "${CACHE_CANDIDATES[@]}"; do
  if [[ -z "$cache_dir" ]]; then
    continue
  fi
  remove_tree "$cache_dir"
done

step "Removing shell alias entries"
remove_profile_block "$HOME/.bashrc"
if [[ -f "$HOME/.zshrc" ]]; then
  remove_profile_block "$HOME/.zshrc"
else
  note "$HOME/.zshrc not found (skipped)"
fi

step "Cleanup completed"
ok "aurorafs files were removed from this PC user profile"
ok "opened-file cache was removed"
ok "system/python packages were not changed"
AURORA_DONE_REPORTED=1
report_event cleanup_done
echo "You can run first setup again from phone option [f]."
'''

CLEANUP_PS1_TEMPLATE = r'''$ErrorActionPreference = "Stop"

$AuroraBaseUrl = "__BASE_URL__"
$AuroraToken = "__TOKEN__"
$AuroraBashCleanupB64 = "__BASH_CLEANUP_B64__"
$AuroraDoneReported = $false
$AuroraStep = 0

function Step([string]$Text) {
  $script:AuroraStep += 1
  "[{0:D2}] {1}" -f $script:AuroraStep, $Text
}

function Ok([string]$Text) {
  "     [ok] $Text"
}

function Note([string]$Text) {
  "     [..] $Text"
}

function Report-Event([string]$Event) {
  try {
    Invoke-RestMethod -Method Post -Uri "$AuroraBaseUrl/event?token=$AuroraToken&event=$Event" | Out-Null
  } catch {
  }
}

trap {
  if (-not $script:AuroraDoneReported) {
    Report-Event "cleanup_failed"
  }
  throw
}

function Test-WindowsRuntime {
  return [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
}

function Invoke-EmbeddedBash([string]$PayloadB64) {
  $bash = Get-Command bash -ErrorAction SilentlyContinue
  if (-not $bash) {
    throw "PowerShell is not running on Windows, and bash was not found for WSL/Linux cleanup."
  }
  $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("aurorafs-cleanup-" + [System.Guid]::NewGuid().ToString("N") + ".sh")
  [System.IO.File]::WriteAllBytes($tmp, [System.Convert]::FromBase64String($PayloadB64))
  try {
    & $bash.Source $tmp
    if ($LASTEXITCODE -ne 0) {
      exit $LASTEXITCODE
    }
  } finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  }
}

function Remove-Tree([string]$Path) {
  if (Test-Path -LiteralPath $Path) {
    Remove-Item -LiteralPath $Path -Recurse -Force
    Ok "removed $Path"
  } else {
    Note "$Path already clean"
  }
}

function Remove-File([string]$Path) {
  if (Test-Path -LiteralPath $Path) {
    Remove-Item -LiteralPath $Path -Force
    Ok "removed $Path"
  } else {
    Note "$Path already clean"
  }
}

function Remove-ProfileBlock([string]$File) {
  $start = "# >>> aurorafs >>>"
  $end = "# <<< aurorafs <<<"
  if (-not (Test-Path -LiteralPath $File)) {
    Note "$File not found (skipped)"
    return
  }
  $had = $false
  $out = New-Object System.Collections.Generic.List[string]
  $skip = $false
  foreach ($line in @(Get-Content -LiteralPath $File)) {
    if ($line -eq $start) {
      $had = $true
      $skip = $true
      continue
    }
    if ($line -eq $end) {
      $skip = $false
      continue
    }
    if (-not $skip) {
      $out.Add($line)
    }
  }
  Set-Content -LiteralPath $File -Value $out -Encoding UTF8
  if ($had) {
    Ok "removed aurorafs alias block from $File"
  } else {
    Note "no aurorafs alias block in $File"
  }
}

Step "Starting aurorafs PC-side cleanup"
Ok "cleanup endpoint reached at $AuroraBaseUrl"

if (-not (Test-WindowsRuntime)) {
  Step "Using WSL/Linux cleanup path"
  Invoke-EmbeddedBash $AuroraBashCleanupB64
  exit 0
}

$HomeDir = [Environment]::GetFolderPath("UserProfile")
if ([string]::IsNullOrWhiteSpace($HomeDir)) {
  $HomeDir = $HOME
}
$RootDir = Join-Path $HomeDir "aurora-pcbridge"
$CacheDir = Join-Path ([System.IO.Path]::GetTempPath()) "aurorafs-open"

Step "Removing PowerShell alias"
Remove-ProfileBlock $PROFILE

Step "Removing aurorafs files and folders"
Remove-Tree $RootDir

Step "Removing opened-file cache"
Remove-Tree $CacheDir

Step "Cleanup completed"
Ok "aurorafs files were removed from this Windows user profile"
Ok "opened-file cache was removed"
Ok "system/python packages were not changed"
$script:AuroraDoneReported = $true
Report-Event "cleanup_done"
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


def token_event_is_valid(value):
    if not value or value != token:
        return False, "invalid token"
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


def build_bootstrap_ps1(base_url):
    body = BOOTSTRAP_PS1_TEMPLATE
    bash_body = base64.b64encode(build_bootstrap(base_url).encode("utf-8")).decode("ascii")
    body = body.replace("__BASE_URL__", base_url)
    body = body.replace("__TOKEN__", token)
    body = body.replace("__SSH_PORT__", str(ssh_port))
    body = body.replace("__HOSTKEY_ED25519__", hostkey_ed25519_pub)
    body = body.replace("__HOSTKEY_RSA__", hostkey_rsa_pub)
    body = body.replace("__BASH_BOOTSTRAP_B64__", bash_body)
    return body


def build_cleanup(base_url):
    body = CLEANUP_TEMPLATE
    body = body.replace("__BASE_URL__", base_url)
    body = body.replace("__TOKEN__", token)
    return body


def build_cleanup_ps1(base_url):
    body = CLEANUP_PS1_TEMPLATE
    bash_body = base64.b64encode(build_cleanup(base_url).encode("utf-8")).decode("ascii")
    body = body.replace("__BASE_URL__", base_url)
    body = body.replace("__TOKEN__", token)
    body = body.replace("__BASH_CLEANUP_B64__", bash_body)
    return body


def pairing_action_label():
    if pairing_action == "cleanup":
        return "PC cleanup"
    return "first-run setup"


def pairing_action_description():
    if pairing_action == "cleanup":
        return "Cleanup removes aurorafs files, aliases, and opened-file cache for this PC user. System packages stay installed."
    return "Setup pairs this PC key with the phone, installs the aurorafs client files, and prepares the aurorafs command."


def pairing_endpoint():
    return "cleanup.sh" if pairing_action == "cleanup" else "bootstrap.sh"


def build_pc_command(base_url):
    endpoint = pairing_endpoint()
    ps_endpoint = endpoint[:-3] + ".ps1" if endpoint.endswith(".sh") else endpoint
    return (
        "pwsh -NoProfile -ExecutionPolicy Bypass -Command "
        f"\"Invoke-Expression (Invoke-RestMethod -Uri '{base_url}/{ps_endpoint}?token={token}')\" "
        "|| "
        f"bash -lc \"$(curl -fsSL '{base_url}/{endpoint}?token={token}')\""
    )


def safe_header_text(value, limit=180):
    text = str(value or "").replace("\r", " ").replace("\n", " ").replace("\t", " ").strip()
    text = re.sub(r"\s+", " ", text)
    return text[:limit]


def browser_session_problem():
    if token_manually_expired():
        write_event("manually_expired")
        return "manually_expired"
    if time.time() > started_at + token_ttl:
        write_event("expired")
        return "expired"
    return ""


def write_browser_request(req):
    try:
        os.makedirs(os.path.dirname(browser_request_file), exist_ok=True)
    except Exception:
        pass
    try:
        tmp = browser_request_file + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(req, fh, indent=2, sort_keys=True)
            fh.write("\n")
        os.replace(tmp, browser_request_file)
        try:
            os.chmod(browser_request_file, 0o600)
        except Exception:
            pass
    except Exception:
        pass


def clear_browser_approval():
    try:
        os.unlink(browser_approval_file)
    except FileNotFoundError:
        pass
    except Exception:
        pass


def read_browser_approval():
    try:
        with open(browser_approval_file, "r", encoding="utf-8") as fh:
            raw = fh.read(512).strip()
    except Exception:
        return {}
    parts = raw.split("\t")
    if len(parts) < 2:
        return {}
    request_id = parts[0].strip()
    decision = parts[1].strip().lower()
    if not re.match(r"^[A-Fa-f0-9]{16}$", request_id):
        return {}
    if decision not in {"approved", "denied"}:
        return {}
    return {"request_id": request_id, "decision": decision}


def read_browser_request():
    try:
        with open(browser_request_file, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception:
        return {}
    if not isinstance(data, dict):
        return {}
    request_id = str(data.get("request_id", "")).strip()
    action = str(data.get("action", "")).strip().lower()
    code = str(data.get("code", "")).strip()
    if not re.match(r"^[A-Fa-f0-9]{16}$", request_id):
        return {}
    if action not in {"bootstrap", "cleanup"}:
        return {}
    if not re.match(r"^[0-9]{6}$", code):
        return {}
    return data


def browser_request_for(request_id):
    request_id = str(request_id or "").strip()
    req = current_browser_request
    if isinstance(req, dict) and req.get("request_id") == request_id:
        return req
    req = read_browser_request()
    if isinstance(req, dict) and req.get("request_id") == request_id:
        return req
    return {}


def create_browser_request(handler):
    global current_browser_request
    remote_ip = ""
    try:
        remote_ip = str(handler.client_address[0] or "")
    except Exception:
        remote_ip = ""
    try:
        user_agent = safe_header_text(handler.headers.get("User-Agent", ""))
    except Exception:
        user_agent = ""
    req = {
        "request_id": secrets.token_hex(8),
        "action": pairing_action,
        "remote_ip": safe_header_text(remote_ip, 80) or "unknown",
        "user_agent": user_agent,
        "code": f"{secrets.randbelow(1000000):06d}",
        "created_at": now_iso(),
    }
    current_browser_request = req
    clear_browser_approval()
    write_browser_request(req)
    write_event("browser_request")
    return req


def browser_status_for(request_id):
    problem = browser_session_problem()
    if problem:
        return {"status": problem}
    request_id = str(request_id or "").strip()
    if not re.match(r"^[A-Fa-f0-9]{16}$", request_id):
        return {"status": "invalid"}
    req = browser_request_for(request_id)
    if not isinstance(req, dict) or req.get("request_id") != request_id:
        return {"status": "superseded"}
    approval = read_browser_approval()
    if approval.get("request_id") == request_id:
        decision = approval.get("decision")
        if decision == "approved":
            return {"status": "approved", "command_url": f"/command?id={urllib.parse.quote(request_id)}"}
        if decision == "denied":
            return {"status": "denied"}
    decision = str(req.get("decision", "") or "").strip().lower()
    if decision == "approved":
        return {"status": "approved", "command_url": f"/command?id={urllib.parse.quote(request_id)}"}
    if decision == "denied":
        return {"status": "denied"}
    return {"status": "pending"}


def page_shell(title, body, extra_head=""):
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Cache-Control" content="no-store">
<title>{html.escape(title)}</title>
<style>
:root {{ color-scheme: light dark; font-family: Arial, sans-serif; }}
body {{ margin: 0; background: #f4f7fb; color: #18202a; }}
main {{ max-width: 920px; margin: 0 auto; padding: 32px 18px; }}
.panel {{ background: #ffffff; border: 1px solid #d9e2ef; border-radius: 8px; padding: 22px; box-shadow: 0 10px 28px rgba(28, 42, 60, 0.08); }}
h1 {{ margin: 0 0 12px; font-size: 28px; }}
p {{ line-height: 1.5; }}
.code {{ display: inline-block; padding: 8px 12px; border-radius: 6px; background: #102033; color: #ffffff; font: 700 24px ui-monospace, SFMono-Regular, Consolas, monospace; letter-spacing: 2px; }}
.muted {{ color: #526170; }}
.status {{ margin-top: 18px; padding: 12px; border-radius: 6px; background: #eef5ff; color: #16395f; }}
textarea {{ box-sizing: border-box; width: 100%; min-height: 132px; margin: 12px 0; padding: 12px; border: 1px solid #b8c5d6; border-radius: 6px; font: 14px ui-monospace, SFMono-Regular, Consolas, monospace; resize: vertical; }}
button {{ border: 0; border-radius: 6px; background: #1659a8; color: #fff; padding: 10px 14px; font-weight: 700; cursor: pointer; }}
button:focus, textarea:focus {{ outline: 3px solid #92c2ff; outline-offset: 2px; }}
li {{ margin: 8px 0; }}
@media (prefers-color-scheme: dark) {{
  body {{ background: #0f141b; color: #e8edf3; }}
  .panel {{ background: #161d26; border-color: #2a3544; box-shadow: none; }}
  .status {{ background: #172b43; color: #d9ebff; }}
  .muted {{ color: #a8b4c1; }}
  textarea {{ background: #0d1117; color: #e8edf3; border-color: #3a4656; }}
}}
</style>
{extra_head}
</head>
<body><main><section class="panel">{body}</section></main></body>
</html>
"""


def waiting_page(req):
    req_id = html.escape(str(req.get("request_id", "")))
    code = html.escape(str(req.get("code", "")))
    action = html.escape(pairing_action_label())
    remote_ip = html.escape(str(req.get("remote_ip", "unknown")))
    description = html.escape(pairing_action_description())
    body = f"""
<h1>Aurora pcbridge {action}</h1>
<p>{description}</p>
<p>This browser is waiting for approval on your phone. Confirm that the phone shows this same code before approving.</p>
<p class="code">{code}</p>
<p class="muted">Browser request from: {remote_ip}</p>
<div id="status" class="status">Waiting for phone approval...</div>
<script>
const requestId = "{req_id}";
const statusBox = document.getElementById("status");
async function poll() {{
  try {{
    const res = await fetch("/approval/status?id=" + encodeURIComponent(requestId), {{cache: "no-store"}});
    const data = await res.json();
    if (data.status === "approved") {{
      statusBox.textContent = "Approved. Opening command page...";
      window.location.href = data.command_url;
      return;
    }}
    if (data.status === "denied") {{
      statusBox.textContent = "Denied on phone. Refresh this page to request approval again.";
      return;
    }}
    if (data.status === "expired" || data.status === "manually_expired") {{
      statusBox.textContent = "This pcbridge setup/cleanup session expired. Restart pcbridge from the phone.";
      return;
    }}
    if (data.status === "superseded") {{
      statusBox.textContent = "A newer browser request replaced this one. Use the newest browser tab or refresh.";
      return;
    }}
  }} catch (err) {{
    statusBox.textContent = "Waiting for phone approval... retrying.";
  }}
  setTimeout(poll, 1200);
}}
poll();
</script>
"""
    refresh_url = "/approval/wait?id=" + urllib.parse.quote(str(req.get("request_id", "")))
    return page_shell(
        f"Aurora pcbridge {action}",
        body,
        f'<meta http-equiv="refresh" content="2; url={html.escape(refresh_url)}">',
    )


def denied_page():
    return page_shell(
        "Aurora pcbridge denied",
        "<h1>Request denied</h1><p>The phone denied this browser request. Refresh the short URL to request approval again.</p>",
    )


def expired_page():
    return page_shell(
        "Aurora pcbridge expired",
        "<h1>Session expired</h1><p>Restart pcbridge setup/cleanup from the phone.</p>",
    )


def command_page(base_url, req):
    action = html.escape(pairing_action_label())
    description = html.escape(pairing_action_description())
    command = build_pc_command(base_url)
    escaped_command = html.escape(command)
    post_setup = "After setup completes, run aurorafs from PowerShell or WSL/Linux." if pairing_action != "cleanup" else "After cleanup completes, you can run first-run setup again from the phone."
    body = f"""
<h1>Aurora pcbridge {action}</h1>
<p>{description}</p>
<ol>
  <li>Keep the phone waiting screen open until this command finishes.</li>
  <li>Copy the command below into PowerShell or WSL/Linux on this computer.</li>
  <li>Press Enter and wait for the phone to report success or failure.</li>
</ol>
<textarea id="cmd" readonly spellcheck="false">{escaped_command}</textarea>
<button id="copyBtn" type="button">Copy command</button>
<p id="copyStatus" class="muted">This command is one-time. If it reports forbidden or expired, restart setup/cleanup from the phone.</p>
<p>{html.escape(post_setup)}</p>
<script>
const cmd = document.getElementById("cmd");
const copyStatus = document.getElementById("copyStatus");
cmd.addEventListener("focus", () => cmd.select());
document.getElementById("copyBtn").addEventListener("click", async () => {{
  cmd.select();
  try {{
    await navigator.clipboard.writeText(cmd.value);
    copyStatus.textContent = "Command copied.";
  }} catch (err) {{
    document.execCommand("copy");
    copyStatus.textContent = "Command selected. Copy it with Ctrl+C if needed.";
  }}
}});
</script>
"""
    return page_shell(f"Aurora pcbridge {action} command", body)


write_event("ready")


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        return

    def _send(self, code, body, ctype="text/plain; charset=utf-8"):
        if isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Pragma", "no-cache")
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
        host_header = ""
        try:
            host_header = str(self.headers.get("Host", "") or "").strip()
        except Exception:
            host_header = ""
        if host_header:
            safe_host = re.match(r"^[A-Za-z0-9._:\-\[\]]{1,255}$", host_header) is not None
            if safe_host:
                if host_header.startswith("["):
                    if host_header.endswith("]"):
                        host_header = f"{host_header}:{http_port}"
                elif ":" not in host_header:
                    host_header = f"{host_header}:{http_port}"
                return f"http://{host_header}"

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
        parsed = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(parsed.query)

        if path in {"/", "/approval", "/setup", "/cleanup"}:
            with lock:
                problem = browser_session_problem()
                if problem:
                    self._send(410, page_shell("Aurora pcbridge expired", "<h1>Session expired</h1><p>Restart pcbridge setup/cleanup from the phone.</p>"), "text/html; charset=utf-8")
                    return
                req = create_browser_request(self)
                self._send(200, waiting_page(req), "text/html; charset=utf-8")
                return

        if path == "/approval/status":
            request_id = (q.get("id", [""])[0] or "").strip()
            with lock:
                payload = browser_status_for(request_id)
                self._send(200, json.dumps(payload) + "\n", "application/json; charset=utf-8")
                return

        if path == "/approval/wait":
            request_id = (q.get("id", [""])[0] or "").strip()
            with lock:
                payload = browser_status_for(request_id)
                status = payload.get("status")
                if status == "approved":
                    req = browser_request_for(request_id)
                    self._send(200, command_page(self._base_url(), req), "text/html; charset=utf-8")
                    return
                if status == "denied":
                    self._send(200, denied_page(), "text/html; charset=utf-8")
                    return
                if status in {"expired", "manually_expired"}:
                    self._send(410, expired_page(), "text/html; charset=utf-8")
                    return
                req = browser_request_for(request_id)
                if not isinstance(req, dict) or req.get("request_id") != request_id:
                    self._send(404, page_shell("Aurora pcbridge request not found", "<h1>Request not found</h1><p>Refresh the short URL to request phone approval again.</p>"), "text/html; charset=utf-8")
                    return
                self._send(200, waiting_page(req), "text/html; charset=utf-8")
                return

        if path == "/command":
            request_id = (q.get("id", [""])[0] or "").strip()
            with lock:
                payload = browser_status_for(request_id)
                if payload.get("status") != "approved":
                    self._send(403, page_shell("Aurora pcbridge not approved", "<h1>Not approved</h1><p>This browser request is not approved. Refresh the short URL and approve it on the phone.</p>"), "text/html; charset=utf-8")
                    return
                req = current_browser_request if isinstance(current_browser_request, dict) else {}
                self._send(200, command_page(self._base_url(), req), "text/html; charset=utf-8")
                return

        if path == "/favicon.ico":
            self._send(204, "", "text/plain; charset=utf-8")
            return

        with lock:
            ok, msg = token_is_valid(req_token)
            if not ok:
                self._send(403, f"forbidden: {msg}\n")
                return

            base_url = self._base_url()

            if path in {"/bootstrap.sh", "/bootstrap.ps1"}:
                if pairing_action != "bootstrap":
                    self._send(403, "forbidden: setup endpoint is not active in this session\n")
                    return
                if bootstrap_command_consumed:
                    self._send(403, "forbidden: bootstrap command already used\n")
                    return
                bootstrap_command_consumed = True
                write_event("bootstrap_command_used")
                if path == "/bootstrap.ps1":
                    self._send(200, build_bootstrap_ps1(base_url), "text/plain; charset=utf-8")
                else:
                    self._send(200, build_bootstrap(base_url), "text/x-shellscript; charset=utf-8")
                return
            if path in {"/cleanup.sh", "/cleanup.ps1"}:
                if pairing_action != "cleanup":
                    self._send(403, "forbidden: cleanup endpoint is not active in this session\n")
                    return
                if cleanup_command_consumed:
                    self._send(403, "forbidden: cleanup command already used\n")
                    return
                cleanup_command_consumed = True
                write_event("cleanup_command_used")
                if path == "/cleanup.ps1":
                    self._send(200, build_cleanup_ps1(base_url), "text/plain; charset=utf-8")
                else:
                    self._send(200, build_cleanup(base_url), "text/x-shellscript; charset=utf-8")
                return
            if path == "/client.py":
                self._send(200, CLIENT_PY, "text/x-python; charset=utf-8")
                return
            if path == "/manifest.json":
                payload = {
                    "service": "pcbridge",
                    "pairing_action": pairing_action,
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
        if path not in {"/pair", "/event"}:
            self._send(404, "not found\n")
            return

        with lock:
            if path == "/event":
                ok, msg = token_event_is_valid(req_token)
                if not ok:
                    self._send(403, f"forbidden: {msg}\n")
                    return
                parsed = urllib.parse.urlparse(self.path)
                q = urllib.parse.parse_qs(parsed.query)
                event = (q.get("event", [""])[0] or "").strip()
                if event not in {"setup_done", "bootstrap_failed", "cleanup_done", "cleanup_failed"}:
                    self._send(400, "invalid event\n")
                    return
                write_event(event)
                self._send(200, json.dumps({"ok": True}) + "\n", "application/json; charset=utf-8")
                return

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
  "pairing_action": "$PAIRING_ACTION",
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
  rm -f -- "$STOP_REQUEST_FILE" "$TOKEN_FILE" "$TOKEN_EVENT_FILE" "$TOKEN_CONTROL_FILE" "$BROWSER_REQUEST_FILE" "$BROWSER_APPROVAL_FILE" "$STATE_JSON"
}

trap cleanup INT TERM EXIT

while true; do
  if [ -e "$STOP_REQUEST_FILE" ]; then
    echo "pcbridge: stop requested by aurorafs client." >&2
    exit 0
  fi
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
