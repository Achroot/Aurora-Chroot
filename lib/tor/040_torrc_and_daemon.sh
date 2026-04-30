chroot_tor_pid_starttime() {
  local pid="$1"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  awk '{print $22}' "/proc/$pid/stat" 2>/dev/null
}

chroot_tor_pid_is_live() {
  local pid="$1"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$pid" >/dev/null 2>&1
}

chroot_tor_detect_daemon_identity() {
  local distro="$1"
  local rootfs passwd_file row user uid gid

  rootfs="$(chroot_distro_rootfs_dir "$distro")"
  passwd_file="$rootfs/etc/passwd"

  if [[ -r "$passwd_file" ]]; then
    while IFS=: read -r user _ uid gid _; do
      case "$user" in
        debian-tor|tor|_tor)
          [[ "$uid" =~ ^[0-9]+$ ]] || continue
          [[ "$gid" =~ ^[0-9]+$ ]] || gid="$uid"
          printf 'system-user|%s|%s|%s|\n' "$user" "$uid" "$gid"
          return 0
          ;;
      esac
    done <"$passwd_file"
  fi

  printf 'root|root|0|0|Tor package user not found inside distro; refusing to run tor as root.\n'
}

chroot_tor_prepare_rootfs_paths() {
  local distro="$1"
  local daemon_uid="$2"
  local daemon_gid="$3"
  local config_dir runtime_dir data_dir

  config_dir="$(chroot_tor_rootfs_config_dir "$distro")"
  runtime_dir="$(chroot_tor_rootfs_runtime_dir "$distro")"
  data_dir="$(chroot_tor_rootfs_data_dir "$distro")"

  chroot_run_root mkdir -p "$config_dir" "$runtime_dir" "$data_dir"
  chroot_run_root chown "$daemon_uid:$daemon_gid" "$runtime_dir" "$data_dir" >/dev/null 2>&1 || true
  chroot_run_root chmod 700 "$runtime_dir" "$data_dir" >/dev/null 2>&1 || true
}

chroot_tor_rotation_minutes() {
  local value
  value="$(chroot_setting_get tor_rotation_min 2>/dev/null || true)"
  [[ "$value" =~ ^[0-9]+$ ]] || value="5"
  if (( value < 1 )); then
    value=1
  fi
  if (( value > 120 )); then
    value=120
  fi
  printf '%s\n' "$value"
}

chroot_tor_bootstrap_timeout_seconds() {
  local value
  value="$(chroot_setting_get tor_bootstrap_timeout_sec 2>/dev/null || true)"
  [[ "$value" =~ ^[0-9]+$ ]] || value="$CHROOT_TOR_BOOTSTRAP_TIMEOUT_SEC_DEFAULT"
  if (( value < 10 )); then
    value=10
  fi
  if (( value > 600 )); then
    value=600
  fi
  printf '%s\n' "$value"
}

chroot_tor_write_torrc() {
  local distro="$1"
  local daemon_user="$2"
  local use_saved_exit="${3:-0}"
  local torrc tmp
  local rotation_min
  local exit_codes="" exit_strict="0" exit_csv=""

  rotation_min="$(chroot_tor_rotation_minutes)"
  if [[ "$use_saved_exit" == "1" ]]; then
    IFS=$'\t' read -r exit_strict exit_codes exit_csv <<<"$(chroot_tor_exit_policy_tsv "$distro")"
  fi

  torrc="$(chroot_tor_rootfs_torrc_file "$distro")"
  tmp="$torrc.tmp"

  {
    printf 'DataDirectory /var/lib/aurora-tor/data\n'
    printf 'PidFile /var/lib/aurora-tor/tor.pid\n'
    printf 'SocksPort 127.0.0.1:%s\n' "$CHROOT_TOR_DEFAULT_SOCKS_PORT"
    printf 'TransPort 127.0.0.1:%s\n' "$CHROOT_TOR_DEFAULT_TRANS_PORT"
    printf 'DNSPort 127.0.0.1:%s\n' "$CHROOT_TOR_DEFAULT_DNS_PORT"
    printf 'ControlPort 127.0.0.1:%s\n' "$CHROOT_TOR_DEFAULT_CONTROL_PORT"
    printf 'CookieAuthentication 1\n'
    printf 'CookieAuthFile /var/lib/aurora-tor/control_auth_cookie\n'
    printf 'AutomapHostsOnResolve 1\n'
    printf 'VirtualAddrNetworkIPv4 10.192.0.0/10\n'
    printf 'ClientUseIPv6 0\n'
    printf 'MaxCircuitDirtiness %s minutes\n' "$rotation_min"
    if [[ -n "$exit_csv" ]]; then
      printf 'ExitNodes %s\n' "$exit_csv"
      if [[ "$exit_strict" == "1" ]]; then
        printf 'StrictNodes 1\n'
      else
        printf 'StrictNodes 0\n'
      fi
    fi
    if [[ -n "$daemon_user" && "$daemon_user" != "root" ]]; then
      printf 'User %s\n' "$daemon_user"
    fi
  } >"$tmp"

  mv -f -- "$tmp" "$torrc"
  chroot_run_root chmod 600 "$torrc" >/dev/null 2>&1 || true
}

chroot_tor_verify_config() {
  local distro="$1"
  local tor_bin
  tor_bin="$(chroot_tor_chroot_tor_bin "$distro" || true)"
  [[ -n "$tor_bin" ]] || chroot_die "tor binary missing inside $distro"
  chroot_tor_run_in_distro "$distro" "$tor_bin" --verify-config -f /etc/aurora-tor/torrc >/dev/null
}

chroot_tor_current_pid() {
  local distro="$1"
  local pid_file pid current_start saved_pid saved_start
  pid_file="$(chroot_tor_rootfs_pid_file "$distro")"
  [[ -f "$pid_file" ]] || return 1
  pid="$(tr -d '[:space:]' <"$pid_file" 2>/dev/null || true)"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  if ! chroot_tor_pid_is_live "$pid"; then
    return 1
  fi
  current_start="$(chroot_tor_pid_starttime "$pid" 2>/dev/null || true)"
  IFS='|' read -r saved_pid saved_start <<<"$(chroot_tor_saved_pid_identity_tsv "$distro")"
  if [[ "$saved_pid" =~ ^[0-9]+$ && "$saved_pid" == "$pid" && "$saved_start" =~ ^[0-9]+$ ]]; then
    [[ "$current_start" == "$saved_start" ]] || return 1
  fi
  printf '%s\n' "$pid"
}

chroot_tor_raw_pid_from_file() {
  local pid_file="$1"
  local pid
  [[ -f "$pid_file" ]] || return 1
  pid="$(tr -d '[:space:]' <"$pid_file" 2>/dev/null || true)"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  chroot_tor_pid_is_live "$pid" || return 1
  printf '%s\n' "$pid"
}

chroot_tor_port_ready() {
  local port="$1"
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$port" <<'PY'
import socket
import sys

port = int(sys.argv[1])
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.settimeout(0.5)
try:
    sock.connect(("127.0.0.1", port))
except Exception:
    sys.exit(1)
finally:
    sock.close()
sys.exit(0)
PY
}

chroot_tor_port_bound() {
  local port="$1"
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$port" <<'PY'
import os
import sys

port = int(sys.argv[1])
wanted = f"{port:04X}"

for path in ("/proc/net/tcp", "/proc/net/tcp6", "/proc/net/udp", "/proc/net/udp6"):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            next(fh, None)
            for raw in fh:
                parts = raw.split()
                if len(parts) < 2 or ":" not in parts[1]:
                    continue
                _addr, local_port = parts[1].rsplit(":", 1)
                if local_port.upper() == wanted:
                    raise SystemExit(0)
    except FileNotFoundError:
        continue
    except StopIteration:
        continue

raise SystemExit(1)
PY
}

chroot_tor_control_bootstrap_tsv() {
  local cookie_file="$1"
  local port="$2"
  [[ -f "$cookie_file" ]] || return 1

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$cookie_file" "$port" <<'PY'
import shlex
import socket
import sys

cookie_path, port_text = sys.argv[1:3]
port = int(port_text)

with open(cookie_path, "rb") as fh:
    cookie = fh.read().strip()

def recv_reply(sock):
    data = b""
    while True:
        chunk = sock.recv(4096)
        if not chunk:
            break
        data += chunk
        if data.endswith(b"250 OK\r\n") or data.startswith(b"5"):
            break
    return data.decode("utf-8", errors="replace")

def send_cmd(sock, command):
    sock.sendall((command + "\r\n").encode("utf-8", errors="replace"))
    reply = recv_reply(sock)
    if not reply.startswith("250"):
        raise RuntimeError(reply.strip())
    return reply

summary = ""
progress = 0
tag = ""

with socket.create_connection(("127.0.0.1", port), timeout=2.0) as sock:
    send_cmd(sock, f"AUTHENTICATE {cookie.hex()}")
    reply = send_cmd(sock, "GETINFO status/bootstrap-phase")
    send_cmd(sock, "QUIT")

for raw in reply.splitlines():
    line = raw.strip()
    if "status/bootstrap-phase=" not in line:
        continue
    payload = line.split("status/bootstrap-phase=", 1)[1].strip()
    for token in shlex.split(payload):
        if "=" not in token:
            continue
        key, value = token.split("=", 1)
        if key == "PROGRESS":
            try:
                progress = int(value)
            except Exception:
                progress = 0
        elif key == "SUMMARY":
            summary = str(value or "").strip()
        elif key == "TAG":
            tag = str(value or "").strip().lower()
    break

complete = "1" if progress >= 100 or tag == "done" else "0"
summary = summary.replace("\t", " ").replace("\r", " ").replace("\n", " ").strip()
print(f"{complete}\t{summary}")
PY
}

chroot_tor_bootstrap_state_tsv() {
  local distro="$1"
  chroot_tor_control_bootstrap_tsv "$(chroot_tor_rootfs_control_cookie_file "$distro")" "$CHROOT_TOR_DEFAULT_CONTROL_PORT"
}

chroot_tor_bootstrap_complete() {
  local distro="$1"
  local complete summary
  IFS=$'\t' read -r complete summary <<<"$(chroot_tor_bootstrap_state_tsv "$distro" 2>/dev/null || true)"
  [[ "$complete" == "1" ]]
}

chroot_tor_bootstrap_summary() {
  local distro="$1"
  local complete summary
  IFS=$'\t' read -r complete summary <<<"$(chroot_tor_bootstrap_state_tsv "$distro" 2>/dev/null || true)"
  [[ -n "$summary" ]] || return 1
  printf '%s\n' "$summary"
}

chroot_tor_ports_ready() {
  local distro="$1"
  chroot_tor_port_ready "$CHROOT_TOR_DEFAULT_SOCKS_PORT" || return 1
  chroot_tor_port_bound "$CHROOT_TOR_DEFAULT_TRANS_PORT" || return 1
  chroot_tor_port_bound "$CHROOT_TOR_DEFAULT_DNS_PORT" || return 1
}

chroot_tor_start_daemon() {
  local distro="$1"
  local daemon_uid="$2"
  local daemon_gid="$3"
  local tor_bin

  tor_bin="$(chroot_tor_chroot_tor_bin "$distro" || true)"
  [[ -n "$tor_bin" ]] || chroot_die "tor binary missing inside $distro"

  chroot_run_root rm -f -- "$(chroot_tor_rootfs_pid_file "$distro")" >/dev/null 2>&1 || true

  chroot_tor_run_in_distro "$distro" "$tor_bin" --RunAsDaemon 1 -f /etc/aurora-tor/torrc
}

chroot_tor_wait_for_bootstrap() {
  local distro="$1"
  local timeout="${2:-$CHROOT_TOR_BOOTSTRAP_TIMEOUT_SEC_DEFAULT}"
  local elapsed=0

  while (( elapsed < timeout )); do
    if chroot_tor_current_pid "$distro" >/dev/null 2>&1; then
      if chroot_tor_ports_ready "$distro" && chroot_tor_bootstrap_complete "$distro"; then
        return 0
      fi
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

chroot_tor_stop_daemon() {
  local distro="$1"
  local pid i
  pid="$(chroot_tor_current_pid "$distro" 2>/dev/null || true)"
  if [[ -z "$pid" ]]; then
    pid="$(chroot_tor_raw_pid_from_file "$(chroot_tor_rootfs_pid_file "$distro")" 2>/dev/null || true)"
  fi
  [[ -n "$pid" ]] || {
    chroot_run_root rm -f -- "$(chroot_tor_rootfs_pid_file "$distro")" >/dev/null 2>&1 || true
    return 0
  }

  chroot_run_root kill -TERM "$pid" >/dev/null 2>&1 || true
  for (( i=0; i<10; i++ )); do
    if ! chroot_tor_pid_is_live "$pid"; then
      chroot_run_root rm -f -- "$(chroot_tor_rootfs_pid_file "$distro")" >/dev/null 2>&1 || true
      return 0
    fi
    sleep 1
  done

  chroot_run_root kill -KILL "$pid" >/dev/null 2>&1 || true
  sleep 1
  if chroot_tor_pid_is_live "$pid"; then
    return 1
  fi

  chroot_run_root rm -f -- "$(chroot_tor_rootfs_pid_file "$distro")" >/dev/null 2>&1 || true
  return 0
}

chroot_tor_performance_probe_cleanup_paths() {
  local distro="$1"
  local path

  for path in \
    "$(chroot_tor_probe_rootfs_config_dir "$distro")" \
    "$(chroot_tor_probe_rootfs_runtime_dir "$distro")"
  do
    if chroot_run_root test -e "$path" >/dev/null 2>&1; then
      chroot_run_root rm -rf -- "$path" >/dev/null 2>&1 || true
    fi
  done
}

chroot_tor_performance_probe_prepare_rootfs_paths() {
  local distro="$1"
  local daemon_uid="$2"
  local daemon_gid="$3"
  local config_dir runtime_dir data_dir

  config_dir="$(chroot_tor_probe_rootfs_config_dir "$distro")"
  runtime_dir="$(chroot_tor_probe_rootfs_runtime_dir "$distro")"
  data_dir="$(chroot_tor_probe_rootfs_data_dir "$distro")"

  chroot_run_root mkdir -p "$config_dir" "$runtime_dir" "$data_dir"
  chroot_run_root chown "$daemon_uid:$daemon_gid" "$runtime_dir" "$data_dir" >/dev/null 2>&1 || true
  chroot_run_root chmod 700 "$runtime_dir" "$data_dir" >/dev/null 2>&1 || true
}

chroot_tor_performance_probe_write_torrc() {
  local distro="$1"
  local daemon_user="$2"
  local torrc tmp

  torrc="$(chroot_tor_probe_rootfs_torrc_file "$distro")"
  tmp="$torrc.tmp"

  {
    printf 'DataDirectory /var/lib/aurora-tor/performance-probe/data\n'
    printf 'PidFile /var/lib/aurora-tor/performance-probe/tor.pid\n'
    printf 'SocksPort 127.0.0.1:%s\n' "$CHROOT_TOR_PERFORMANCE_PROBE_SOCKS_PORT_DEFAULT"
    printf 'ControlPort 127.0.0.1:%s\n' "$CHROOT_TOR_PERFORMANCE_PROBE_CONTROL_PORT_DEFAULT"
    printf 'CookieAuthentication 1\n'
    printf 'CookieAuthFile /var/lib/aurora-tor/performance-probe/control_auth_cookie\n'
    printf 'AutomapHostsOnResolve 1\n'
    printf 'ClientUseIPv6 0\n'
    printf 'SafeLogging 1\n'
    if [[ -n "$daemon_user" && "$daemon_user" != "root" ]]; then
      printf 'User %s\n' "$daemon_user"
    fi
  } >"$tmp"

  mv -f -- "$tmp" "$torrc"
  chroot_run_root chmod 600 "$torrc" >/dev/null 2>&1 || true
}

chroot_tor_performance_probe_current_pid() {
  local distro="$1"
  local pid_file pid
  pid_file="$(chroot_tor_probe_rootfs_pid_file "$distro")"
  [[ -f "$pid_file" ]] || return 1
  pid="$(tr -d '[:space:]' <"$pid_file" 2>/dev/null || true)"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  chroot_tor_pid_is_live "$pid" || return 1
  printf '%s\n' "$pid"
}

chroot_tor_performance_probe_bootstrap_state_tsv() {
  local distro="$1"
  chroot_tor_control_bootstrap_tsv "$(chroot_tor_probe_rootfs_control_cookie_file "$distro")" "$CHROOT_TOR_PERFORMANCE_PROBE_CONTROL_PORT_DEFAULT"
}

chroot_tor_performance_probe_bootstrap_complete() {
  local distro="$1"
  local complete summary
  IFS=$'\t' read -r complete summary <<<"$(chroot_tor_performance_probe_bootstrap_state_tsv "$distro" 2>/dev/null || true)"
  [[ "$complete" == "1" ]]
}

chroot_tor_performance_probe_bootstrap_summary() {
  local distro="$1"
  local complete summary
  IFS=$'\t' read -r complete summary <<<"$(chroot_tor_performance_probe_bootstrap_state_tsv "$distro" 2>/dev/null || true)"
  [[ -n "$summary" ]] || return 1
  printf '%s\n' "$summary"
}

chroot_tor_performance_probe_wait_for_bootstrap() {
  local distro="$1"
  local timeout="${2:-$CHROOT_TOR_BOOTSTRAP_TIMEOUT_SEC_DEFAULT}"
  local elapsed=0

  while (( elapsed < timeout )); do
    if chroot_tor_performance_probe_current_pid "$distro" >/dev/null 2>&1; then
      if chroot_tor_port_ready "$CHROOT_TOR_PERFORMANCE_PROBE_SOCKS_PORT_DEFAULT" && chroot_tor_performance_probe_bootstrap_complete "$distro"; then
        return 0
      fi
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

chroot_tor_performance_probe_stop() {
  local distro="$1"
  local pid i
  pid="$(chroot_tor_performance_probe_current_pid "$distro" 2>/dev/null || true)"
  [[ -n "$pid" ]] || {
    chroot_run_root rm -f -- "$(chroot_tor_probe_rootfs_pid_file "$distro")" >/dev/null 2>&1 || true
    return 0
  }

  chroot_run_root kill -TERM "$pid" >/dev/null 2>&1 || true
  for (( i=0; i<10; i++ )); do
    if ! chroot_tor_pid_is_live "$pid"; then
      chroot_run_root rm -f -- "$(chroot_tor_probe_rootfs_pid_file "$distro")" >/dev/null 2>&1 || true
      return 0
    fi
    sleep 1
  done

  chroot_run_root kill -KILL "$pid" >/dev/null 2>&1 || true
  sleep 1
  if chroot_tor_pid_is_live "$pid"; then
    return 1
  fi

  chroot_run_root rm -f -- "$(chroot_tor_probe_rootfs_pid_file "$distro")" >/dev/null 2>&1 || true
  return 0
}

chroot_tor_performance_probe_start() {
  local distro="$1"
  local daemon_user="$2"
  local daemon_uid="$3"
  local daemon_gid="$4"
  local tor_bin timeout excerpt

  tor_bin="$(chroot_tor_chroot_tor_bin "$distro" || true)"
  [[ -n "$tor_bin" ]] || chroot_die "tor binary missing inside $distro"

  chroot_tor_performance_probe_stop "$distro" >/dev/null 2>&1 || true
  chroot_tor_performance_probe_cleanup_paths "$distro"
  chroot_tor_performance_probe_prepare_rootfs_paths "$distro" "$daemon_uid" "$daemon_gid"
  chroot_tor_performance_probe_write_torrc "$distro" "$daemon_user"
  chroot_tor_run_in_distro "$distro" "$tor_bin" --verify-config -f /etc/aurora-tor/performance-probe/torrc >/dev/null
  chroot_tor_run_in_distro "$distro" "$tor_bin" --RunAsDaemon 1 -f /etc/aurora-tor/performance-probe/torrc >/dev/null

  timeout="$(chroot_tor_bootstrap_timeout_seconds)"
  if ! chroot_tor_performance_probe_wait_for_bootstrap "$distro" "$timeout"; then
    excerpt="$(chroot_tor_performance_probe_bootstrap_summary "$distro" 2>/dev/null || true)"
    chroot_tor_performance_probe_stop "$distro" >/dev/null 2>&1 || true
    chroot_tor_performance_probe_cleanup_paths "$distro"
    [[ -n "$excerpt" ]] && chroot_die "performance probe tor did not bootstrap: $excerpt"
    chroot_die "performance probe tor did not bootstrap"
  fi
}

chroot_tor_apply_base_exit_policy() {
  local distro="$1"
  local cookie_file pid active_distro active_at run_mode use_saved_exit exit_strict exit_codes exit_csv

  IFS='|' read -r active_distro active_at <<<"$(chroot_tor_global_active_tsv)"
  [[ -n "$active_distro" && "$active_distro" == "$distro" ]] || chroot_die "selected distro is not the active Tor backend: $distro"

  pid="$(chroot_tor_current_pid "$distro" 2>/dev/null || true)"
  [[ -n "$pid" ]] || chroot_die "tor daemon is not running for $distro"

  cookie_file="$(chroot_tor_rootfs_control_cookie_file "$distro")"
  [[ -f "$cookie_file" ]] || chroot_die "tor control cookie is missing for $distro"

  run_mode="$(chroot_tor_saved_run_mode "$distro" | tr -d '[:space:]')"
  use_saved_exit=0
  if chroot_tor_run_mode_uses_saved_exit "$run_mode"; then
    use_saved_exit=1
    IFS=$'\t' read -r exit_strict exit_codes exit_csv <<<"$(chroot_tor_exit_policy_tsv "$distro")"
  else
    exit_strict="0"
    exit_csv=""
  fi

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$cookie_file" "$CHROOT_TOR_DEFAULT_CONTROL_PORT" "$use_saved_exit" "$exit_csv" "$exit_strict" <<'PY'
import socket
import sys

cookie_path, port_text, use_saved_exit, exit_csv, exit_strict = sys.argv[1:6]
port = int(port_text)

with open(cookie_path, "rb") as fh:
    cookie = fh.read().strip()

def recv_reply(sock):
    data = b""
    while True:
        chunk = sock.recv(4096)
        if not chunk:
            break
        data += chunk
        if data.endswith(b"250 OK\r\n") or data.startswith(b"5"):
            break
    return data.decode("utf-8", errors="replace")

def send_cmd(sock, command):
    sock.sendall((command + "\r\n").encode("utf-8", errors="replace"))
    reply = recv_reply(sock)
    if not reply.startswith("250"):
        raise SystemExit(f"Tor control command failed ({command}): {reply.strip()}")
    return reply

with socket.create_connection(("127.0.0.1", port), timeout=5.0) as sock:
    send_cmd(sock, f"AUTHENTICATE {cookie.hex()}")
    if use_saved_exit == "1" and exit_csv:
        strict_value = "1" if str(exit_strict).strip() == "1" else "0"
        send_cmd(sock, f"SETCONF ExitNodes={exit_csv} StrictNodes={strict_value}")
    else:
        send_cmd(sock, "RESETCONF ExitNodes StrictNodes")
    send_cmd(sock, "QUIT")
PY
}

chroot_tor_freeze_current() {
  local distro="$1"
  local cookie_file pid active_distro active_at public_exit_json freeze_json refreshed_public_exit_json run_mode

  IFS='|' read -r active_distro active_at <<<"$(chroot_tor_global_active_tsv)"
  [[ -n "$active_distro" && "$active_distro" == "$distro" ]] || chroot_die "selected distro is not the active Tor backend: $distro"

  pid="$(chroot_tor_current_pid "$distro" 2>/dev/null || true)"
  [[ -n "$pid" ]] || chroot_die "tor daemon is not running for $distro"
  chroot_tor_bootstrap_complete "$distro" >/dev/null 2>&1 || chroot_die "tor daemon is not bootstrapped yet for $distro"
  run_mode="$(chroot_tor_saved_run_mode "$distro" | tr -d '[:space:]')"
  if chroot_tor_performance_mode_enabled_for_run "$distro" "$run_mode" && chroot_tor_performance_is_active "$distro"; then
    chroot_die "freeze is unavailable while performance mode is active; performance mode manages relay pinning automatically"
  fi

  cookie_file="$(chroot_tor_rootfs_control_cookie_file "$distro")"
  [[ -f "$cookie_file" ]] || chroot_die "tor control cookie is missing for $distro"

  public_exit_json="$(chroot_tor_public_exit_json "$distro" "$pid" 1 "$CHROOT_TOR_DEFAULT_SOCKS_PORT")"

  chroot_require_python
  freeze_json="$("$CHROOT_PYTHON_BIN" - "$cookie_file" "$CHROOT_TOR_DEFAULT_CONTROL_PORT" "$public_exit_json" "$(chroot_now_ts)" "$(chroot_tor_saved_run_mode "$distro")" <<'PY'
import json
import socket
import sys

cookie_path, port_text, public_exit_text, pinned_at, run_mode = sys.argv[1:6]
port = int(port_text)

public_exit = {}
public_ip = ""
public_lookup_error = ""
try:
    parsed_public_exit = json.loads(public_exit_text)
    if isinstance(parsed_public_exit, dict):
        public_exit = parsed_public_exit
except Exception as exc:
    public_lookup_error = str(exc)

if public_exit.get("available"):
    public_ip = str(public_exit.get("ip") or "").strip()
else:
    public_lookup_error = str(public_exit.get("error") or public_exit.get("reason") or public_lookup_error or "")

with open(cookie_path, "rb") as fh:
    cookie = fh.read().strip()

def recv_reply(sock):
    data = b""
    while True:
        chunk = sock.recv(4096)
        if not chunk:
            break
        data += chunk
        if data.endswith(b"250 OK\r\n") or data.startswith(b"5"):
            break
    return data.decode("utf-8", errors="replace")

def send_cmd(sock, command):
    sock.sendall((command + "\r\n").encode("utf-8", errors="replace"))
    reply = recv_reply(sock)
    if not reply.startswith("250"):
        raise SystemExit(f"Tor control command failed ({command}): {reply.strip()}")
    return reply

def parse_exit_candidates(circuit_text):
    out = []
    for raw in circuit_text.splitlines():
        line = raw.strip()
        if not line or not line[:1].isdigit():
            continue
        if " BUILT " not in line:
            continue
        if "BUILD_FLAGS=IS_INTERNAL" in line or ",IS_INTERNAL" in line:
            continue
        circuit_id = line.split(" ", 1)[0]
        path = line.split(" BUILT ", 1)[1]
        for marker in (" BUILD_FLAGS=", " PURPOSE=", " HS_STATE=", " REND_QUERY=", " TIME_CREATED="):
            if marker in path:
                path = path.split(marker, 1)[0]
        created_at = ""
        if " TIME_CREATED=" in line:
            created_at = line.split(" TIME_CREATED=", 1)[1].split(" ", 1)[0].strip()
        hops = [part.strip() for part in path.split(",") if part.strip()]
        if not hops:
            continue
        exit_hop = hops[-1]
        fingerprint = ""
        nickname = ""
        if exit_hop.startswith("$"):
            fingerprint = exit_hop[1:].split("~", 1)[0].upper()
            if "~" in exit_hop:
                nickname = exit_hop.split("~", 1)[1]
        else:
            nickname = exit_hop
        out.append((circuit_id, fingerprint, nickname, created_at))
    return out

def relay_ip_for_fingerprint(sock, fingerprint):
    if not fingerprint:
        return "", ""
    reply = send_cmd(sock, f"GETINFO ns/id/{fingerprint}")
    nickname = ""
    relay_ip = ""
    for raw in reply.splitlines():
        line = raw.strip()
        if line.startswith("r "):
            parts = line.split()
            if len(parts) >= 7:
                nickname = parts[1]
                relay_ip = parts[6]
            break
    return relay_ip, nickname

with socket.create_connection(("127.0.0.1", port), timeout=5.0) as sock:
    send_cmd(sock, f"AUTHENTICATE {cookie.hex()}")
    circuit_text = send_cmd(sock, "GETINFO circuit-status")
    chosen_fp = ""
    chosen_nick = ""
    chosen_ip = ""
    candidates = []
    for _cid, fingerprint, nickname, created_at in parse_exit_candidates(circuit_text):
        relay_ip, desc_nickname = relay_ip_for_fingerprint(sock, fingerprint)
        candidates.append((fingerprint, desc_nickname or nickname, relay_ip, created_at))
        if public_ip and relay_ip and relay_ip == public_ip:
            chosen_fp = fingerprint
            chosen_nick = desc_nickname or nickname
            chosen_ip = relay_ip
            break
    if not chosen_fp and candidates:
        candidates.sort(key=lambda row: row[3] or "")
        chosen_fp, chosen_nick, chosen_ip, _created_at = candidates[-1]
    if not chosen_fp:
        raise SystemExit("could not determine a current Tor exit relay")
    send_cmd(sock, f"SETCONF ExitNodes=${chosen_fp} StrictNodes=1")
    send_cmd(sock, "QUIT")

payload = {
    "active": True,
    "pinned_at": str(pinned_at or ""),
    "run_mode": str(run_mode or ""),
    "exit_fingerprint": f"${chosen_fp}",
    "exit_nickname": str(chosen_nick or ""),
    "exit_ip": str(chosen_ip or public_ip),
    "public_ip": str(public_ip or ""),
    "country": str(public_exit.get("country") or ""),
    "country_code": str(public_exit.get("country_code") or ""),
    "region": str(public_exit.get("region") or ""),
    "city": str(public_exit.get("city") or ""),
    "source": str(public_exit.get("source") or ("control-only" if not public_ip else "")),
}
if public_lookup_error:
    payload["lookup_error"] = public_lookup_error
print(json.dumps(payload, indent=2, sort_keys=True))
PY
)"

  sleep 1
  refreshed_public_exit_json="$(chroot_tor_public_exit_json "$distro" "$pid" 1 "$CHROOT_TOR_DEFAULT_SOCKS_PORT")"
  freeze_json="$("$CHROOT_PYTHON_BIN" - "$freeze_json" "$refreshed_public_exit_json" <<'PY'
import json
import sys

base_text, refreshed_text = sys.argv[1:3]
try:
    payload = json.loads(base_text)
except Exception as exc:
    raise SystemExit(f"failed to parse base freeze state: {exc}")
if not isinstance(payload, dict):
    raise SystemExit("failed to parse base freeze state: payload must be an object")

try:
    refreshed = json.loads(refreshed_text)
except Exception:
    refreshed = {}
if not isinstance(refreshed, dict):
    refreshed = {}

if refreshed.get("available"):
    payload["public_ip"] = str(refreshed.get("ip") or "")
    payload["country"] = str(refreshed.get("country") or "")
    payload["country_code"] = str(refreshed.get("country_code") or "")
    payload["region"] = str(refreshed.get("region") or "")
    payload["city"] = str(refreshed.get("city") or "")
    payload["source"] = str(refreshed.get("source") or payload.get("source") or "")
    payload.pop("lookup_error", None)
else:
    lookup_error = str(refreshed.get("error") or refreshed.get("reason") or "").strip()
    if lookup_error:
      payload["lookup_error"] = lookup_error
      if not payload.get("source"):
          payload["source"] = "control-only"
print(json.dumps(payload, indent=2, sort_keys=True))
PY
)"

  chroot_tor_freeze_write_json "$distro" "$freeze_json"
}

chroot_tor_control_signal_newnym() {
  local cookie_file="$1"
  local port="${2:-$CHROOT_TOR_DEFAULT_CONTROL_PORT}"
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$cookie_file" "$port" <<'PY'
import socket
import sys

cookie_path, port_text = sys.argv[1:3]
port = int(port_text)

with open(cookie_path, "rb") as fh:
    cookie = fh.read().strip()

def recv_reply(sock):
    data = b""
    while True:
        chunk = sock.recv(4096)
        if not chunk:
            break
        data += chunk
        if b"\r\n" in data and (data.startswith(b"250 ") or data.startswith(b"5")):
            break
        if data.endswith(b"250 OK\r\n"):
            break
    return data.decode("utf-8", errors="replace")

with socket.create_connection(("127.0.0.1", port), timeout=5.0) as sock:
    sock.sendall(f"AUTHENTICATE {cookie.hex()}\r\n".encode("ascii"))
    reply = recv_reply(sock)
    if not reply.startswith("250"):
        raise SystemExit(f"Tor control AUTHENTICATE failed: {reply.strip()}")

    sock.sendall(b"SIGNAL NEWNYM\r\n")
    reply = recv_reply(sock)
    if not reply.startswith("250"):
        raise SystemExit(f"Tor control NEWNYM failed: {reply.strip()}")

    sock.sendall(b"QUIT\r\n")
PY
}

chroot_tor_newnym() {
  local distro="$1"
  local cookie_file pid active_distro active_at run_mode

  IFS='|' read -r active_distro active_at <<<"$(chroot_tor_global_active_tsv)"
  [[ -n "$active_distro" && "$active_distro" == "$distro" ]] || chroot_die "selected distro is not the active Tor backend: $distro"

  pid="$(chroot_tor_current_pid "$distro" 2>/dev/null || true)"
  [[ -n "$pid" ]] || chroot_die "tor daemon is not running for $distro"

  cookie_file="$(chroot_tor_rootfs_control_cookie_file "$distro")"
  [[ -f "$cookie_file" ]] || chroot_die "tor control cookie is missing for $distro"

  run_mode="$(chroot_tor_saved_run_mode "$distro" | tr -d '[:space:]')"
  if chroot_tor_performance_mode_enabled_for_run "$distro" "$run_mode"; then
    chroot_tor_performance_request "$distro" "newnym"
    chroot_tor_performance_controller_start "$distro" >/dev/null 2>&1 || true
    return 0
  fi

  chroot_tor_apply_base_exit_policy "$distro"
  chroot_tor_freeze_clear "$distro"

  chroot_tor_control_signal_newnym "$cookie_file" "$CHROOT_TOR_DEFAULT_CONTROL_PORT"
}

chroot_tor_performance_mode_enabled_for_run() {
  local distro="$1"
  local run_mode="${2:-default}"
  local enabled="0"
  chroot_tor_run_mode_uses_saved_performance "$run_mode" || return 1
  enabled="$(chroot_tor_exit_performance_enabled "$distro" 2>/dev/null | tr -d '[:space:]')"
  [[ "$enabled" == "1" ]]
}

chroot_tor_performance_is_active() {
  local distro="$1"
  local perf_file
  perf_file="$(chroot_tor_performance_file "$distro")"
  [[ -f "$perf_file" ]] || return 1
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$perf_file" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {}
sys.exit(0 if data.get("active") else 1)
PY
}

chroot_tor_performance_state_tsv() {
  local distro="$1"
  local perf_file
  perf_file="$(chroot_tor_performance_file "$distro")"
  [[ -f "$perf_file" ]] || {
    printf '0||||\n'
    return 0
  }
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$perf_file" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {}

score = data.get("current_score", {}) if isinstance(data.get("current_score"), dict) else {}
active = "1" if data.get("active") else "0"
controller_pid = data.get("controller_pid")
controller_pid = str(controller_pid) if controller_pid not in (None, "") else ""
print(
    "|".join(
        [
            active,
            controller_pid,
            str(data.get("current_exit_fingerprint", "") or ""),
            str(score.get("speed_mbps", "") if score.get("speed_mbps") is not None else ""),
            str(score.get("latency_ms", "") if score.get("latency_ms") is not None else ""),
        ]
    )
)
PY
}

chroot_tor_performance_sync_freeze_from_selection() {
  local distro="$1"
  local selection_json="$2"
  local pinned_at="${3:-$(chroot_now_ts)}"
  chroot_require_python
  local freeze_json
  freeze_json="$("$CHROOT_PYTHON_BIN" - "$selection_json" "$pinned_at" <<'PY'
import json
import sys

selection_text, pinned_at = sys.argv[1:3]
try:
    payload = json.loads(selection_text)
except Exception:
    payload = {}
best = payload.get("best", {}) if isinstance(payload.get("best"), dict) else {}
freeze = {
    "active": bool(best),
    "city": str(best.get("city") or ""),
    "country": str(best.get("country") or ""),
    "country_code": str(best.get("country_code") or ""),
    "exit_fingerprint": str(best.get("fingerprint") or ""),
    "exit_ip": str(best.get("ip") or ""),
    "exit_nickname": str(best.get("nickname") or ""),
    "pinned_at": str(pinned_at or ""),
    "public_ip": str(best.get("public_ip") or best.get("ip") or ""),
    "region": str(best.get("region") or ""),
    "source": "performance",
}
print(json.dumps(freeze, indent=2, sort_keys=True))
PY
)"
  chroot_tor_freeze_write_json "$distro" "$freeze_json"
}

chroot_tor_performance_select_json() {
  local distro="$1"
  local trigger="${2:-startup}"
  local current_fp="${3:-}"
  local cookie_file probe_cookie_file pid ignored_csv selection_json
  local daemon_mode daemon_user daemon_uid daemon_gid daemon_warning
  local rc=0

  pid="$(chroot_tor_current_pid "$distro" 2>/dev/null || true)"
  [[ -n "$pid" ]] || chroot_die "tor daemon is not running for $distro"
  chroot_tor_bootstrap_complete "$distro" >/dev/null 2>&1 || chroot_die "tor daemon is not bootstrapped yet for $distro"

  cookie_file="$(chroot_tor_rootfs_control_cookie_file "$distro")"
  [[ -f "$cookie_file" ]] || chroot_die "tor control cookie is missing for $distro"
  [[ -n "${CHROOT_CURL_BIN:-}" ]] || chroot_die "curl is required for tor performance mode"
  ignored_csv="$(chroot_tor_exit_performance_ignore_csv "$distro")"

  IFS='|' read -r daemon_mode daemon_user daemon_uid daemon_gid daemon_warning <<<"$(chroot_tor_detect_daemon_identity "$distro")"
  if [[ "$daemon_user" == "root" || "$daemon_uid" == "0" ]]; then
    chroot_die "performance probe tor refuses to run as root inside $distro"
  fi

  chroot_tor_performance_probe_start "$distro" "$daemon_user" "$daemon_uid" "$daemon_gid" >/dev/null
  probe_cookie_file="$(chroot_tor_probe_rootfs_control_cookie_file "$distro")"
  if [[ ! -f "$probe_cookie_file" ]]; then
    chroot_tor_performance_probe_stop "$distro" >/dev/null 2>&1 || true
    chroot_tor_performance_probe_cleanup_paths "$distro"
    chroot_die "performance probe tor control cookie is missing for $distro"
  fi

  chroot_require_python
  rc=0
  selection_json="$("$CHROOT_PYTHON_BIN" - "$cookie_file" "$CHROOT_TOR_DEFAULT_CONTROL_PORT" "$probe_cookie_file" "$CHROOT_TOR_PERFORMANCE_PROBE_CONTROL_PORT_DEFAULT" "$CHROOT_TOR_PERFORMANCE_PROBE_SOCKS_PORT_DEFAULT" "$CHROOT_CURL_BIN" "$trigger" "$current_fp" "$ignored_csv" <<'PY'
import base64
import json
import socket
import subprocess
import sys
import time

main_cookie_path, main_port_text, probe_cookie_path, probe_port_text, probe_socks_port_text, curl_bin, trigger, current_fp, ignored_csv = sys.argv[1:10]
main_port = int(main_port_text)
probe_port = int(probe_port_text)
probe_socks_port = int(probe_socks_port_text)
current_fp = str(current_fp or "").strip().lstrip("$").upper()
ignored_countries = {part.strip().lower() for part in str(ignored_csv or "").split(",") if part.strip()}

candidate_target = 10
country_limit = 1
sample_target = 5
scan_limit = 160
latency_urls = [
    "https://www.google.com/generate_204",
    "https://cp.cloudflare.com/generate_204",
    "https://www.torproject.org/",
]
speed_urls = [
    "https://speed.cloudflare.com/__down?bytes=2000000",
    "https://proof.ovh.net/files/1Mb.dat",
    "https://speed.hetzner.de/1MB.bin",
]
def recv_reply(sock):
    data = b""
    while True:
        chunk = sock.recv(65536)
        if not chunk:
            break
        data += chunk
        if data.endswith(b"250 OK\r\n") or data.startswith(b"5"):
            break
    return data.decode("utf-8", errors="replace")


def send_cmd(sock, command):
    sock.sendall((command + "\r\n").encode("utf-8", errors="replace"))
    reply = recv_reply(sock)
    if not reply.startswith("250"):
        raise RuntimeError(f"Tor control command failed ({command}): {reply.strip()}")
    return reply


def extract_getinfo_body(reply, key):
    multi_prefix = f"250+{key}="
    single_prefix = f"250 {key}="
    for marker in (multi_prefix, single_prefix):
        if marker in reply:
            body = reply.split(marker, 1)[1]
            if marker == multi_prefix:
                if "\r\n.\r\n250 OK\r\n" in body:
                    body = body.split("\r\n.\r\n250 OK\r\n", 1)[0]
                elif "\n.\n250 OK\n" in body:
                    body = body.split("\n.\n250 OK\n", 1)[0]
                elif "\n.\n250 OK\r\n" in body:
                    body = body.split("\n.\n250 OK\r\n", 1)[0]
            else:
                body = body.splitlines()[0]
            return body
    return ""


def decode_identity(text):
    raw = str(text or "").strip()
    if not raw:
        return ""
    padding = "=" * ((4 - (len(raw) % 4)) % 4)
    try:
        return base64.b64decode(raw + padding).hex().upper()
    except Exception:
        return ""


def parse_ns_all(reply):
    body = extract_getinfo_body(reply, "ns/all")
    relays = []
    current = None
    for raw in body.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("r "):
            if current:
                relays.append(current)
            parts = line.split()
            if len(parts) < 7:
                current = None
                continue
            current = {
                "nickname": parts[1],
                "fingerprint": decode_identity(parts[2]),
                "ip": parts[6],
                "bandwidth": 0,
                "flags": set(),
            }
        elif current and line.startswith("s "):
            current["flags"] = set(line.split()[1:])
        elif current and line.startswith("w "):
            for token in line.split()[1:]:
                if token.startswith("Bandwidth="):
                    value = token.split("=", 1)[1].strip()
                    try:
                        current["bandwidth"] = int(value)
                    except Exception:
                        current["bandwidth"] = 0
                    break
    if current:
        relays.append(current)

    filtered = []
    for relay in relays:
        flags = relay.get("flags") or set()
        if not relay.get("fingerprint"):
            continue
        if "Exit" not in flags or "Running" not in flags or "Valid" not in flags:
            continue
        if "BadExit" in flags:
            continue
        filtered.append(relay)
    filtered.sort(key=lambda row: (-int(row.get("bandwidth", 0) or 0), str(row.get("nickname") or ""), str(row.get("fingerprint") or "")))
    return filtered


def ip_to_country(sock, ip_addr, cache):
    if ip_addr in cache:
        return cache[ip_addr]
    reply = send_cmd(sock, f"GETINFO ip-to-country/{ip_addr}")
    prefix = f"250-ip-to-country/{ip_addr}="
    value = ""
    for raw in reply.splitlines():
        line = raw.strip()
        if line.startswith(prefix):
            value = line.split("=", 1)[1].strip().lower()
            break
    if value in {"??", "a1", "a2"}:
        value = ""
    cache[ip_addr] = value
    return value


def control_connect(cookie_path, port):
    with open(cookie_path, "rb") as fh:
        cookie = fh.read().strip()
    sock = socket.create_connection(("127.0.0.1", port), timeout=5.0)
    try:
        send_cmd(sock, f"AUTHENTICATE {cookie.hex()}")
    except Exception:
        sock.close()
        raise
    return sock


def parse_exit_candidates(circuit_text):
    out = []
    for raw in circuit_text.splitlines():
        line = raw.strip()
        if not line or not line[:1].isdigit():
            continue
        if " BUILT " not in line:
            continue
        if "BUILD_FLAGS=IS_INTERNAL" in line or ",IS_INTERNAL" in line:
            continue
        circuit_id = line.split(" ", 1)[0]
        path = line.split(" BUILT ", 1)[1]
        for marker in (" BUILD_FLAGS=", " PURPOSE=", " HS_STATE=", " REND_QUERY=", " TIME_CREATED="):
            if marker in path:
                path = path.split(marker, 1)[0]
        created_at = ""
        if " TIME_CREATED=" in line:
            created_at = line.split(" TIME_CREATED=", 1)[1].split(" ", 1)[0].strip()
        hops = [part.strip() for part in path.split(",") if part.strip()]
        if not hops:
            continue
        exit_hop = hops[-1]
        fingerprint = ""
        nickname = ""
        if exit_hop.startswith("$"):
            fingerprint = exit_hop[1:].split("~", 1)[0].upper()
            if "~" in exit_hop:
                nickname = exit_hop.split("~", 1)[1]
        else:
            nickname = exit_hop
        out.append((circuit_id, fingerprint, nickname, created_at))
    return out


def relay_details_for_fingerprint(sock, fingerprint, fallback_nick):
    nickname = str(fallback_nick or "")
    relay_ip = ""
    if not fingerprint:
        return relay_ip, nickname
    reply = send_cmd(sock, f"GETINFO ns/id/{fingerprint}")
    for raw in reply.splitlines():
        line = raw.strip()
        if line.startswith("r "):
            parts = line.split()
            if len(parts) >= 7:
                nickname = parts[1] or nickname
                relay_ip = parts[6]
            break
    return relay_ip, nickname


def current_exit(sock, public_ip=""):
    circuit_text = send_cmd(sock, "GETINFO circuit-status")
    chosen = None
    candidates = []
    for _cid, fingerprint, nickname, created_at in parse_exit_candidates(circuit_text):
        relay_ip, resolved_nick = relay_details_for_fingerprint(sock, fingerprint, nickname)
        row = {
            "fingerprint": f"${fingerprint}" if fingerprint else "",
            "nickname": str(resolved_nick or ""),
            "ip": str(relay_ip or ""),
            "created_at": str(created_at or ""),
            "matched_public_ip": bool(public_ip and relay_ip and relay_ip == public_ip),
        }
        candidates.append(row)
        if row["matched_public_ip"] and chosen is None:
            chosen = row
    if chosen is None and candidates:
        candidates.sort(key=lambda row: row.get("created_at") or "")
        chosen = candidates[-1]
    return chosen or {}


def run_curl(url, *, write_out="", max_time=20, discard_output=True):
    command = [
        curl_bin,
        "--fail",
        "--location",
        "--connect-timeout",
        "8",
        "--max-time",
        str(max_time),
        "--silent",
        "--show-error",
    ]
    command.extend(["--socks5-hostname", f"127.0.0.1:{probe_socks_port}"])
    if write_out:
        command.extend(["--write-out", write_out])
    command.append(url)
    if discard_output:
        command.extend(["-o", "/dev/null"])
    return subprocess.run(command, capture_output=True, text=True)


def lookup_probe_geo():
    for source, url in (("ipwho.is", "https://ipwho.is/"), ("ipapi.co", "https://ipapi.co/json/")):
        completed = run_curl(url, max_time=20, discard_output=False)
        if completed.returncode != 0:
            continue
        try:
            payload = json.loads(completed.stdout or "")
        except Exception:
            continue
        if source == "ipwho.is":
            if payload.get("success") is False:
                continue
            country_code = str(payload.get("country_code") or "").strip().lower()
            ip_addr = str(payload.get("ip") or "").strip()
            country = str(payload.get("country") or "").strip()
            region = str(payload.get("region") or "").strip()
            city = str(payload.get("city") or "").strip()
        else:
            if payload.get("error"):
                continue
            country_code = str(payload.get("country_code") or "").strip().lower()
            ip_addr = str(payload.get("ip") or "").strip()
            country = str(payload.get("country_name") or payload.get("country") or "").strip()
            region = str(payload.get("region") or "").strip()
            city = str(payload.get("city") or "").strip()
        if country_code and ip_addr:
            return {
                "available": True,
                "source": source,
                "ip": ip_addr,
                "country_code": country_code,
                "country": country,
                "region": region,
                "city": city,
            }
    return {"available": False}


def measure_latency():
    for url in latency_urls:
        completed = run_curl(
            url,
            write_out="%{time_starttransfer}|%{time_total}|%{http_code}",
            max_time=20,
        )
        if completed.returncode != 0:
            continue
        parts = (completed.stdout or "").strip().split("|")
        if len(parts) != 3:
            continue
        try:
            start_transfer = float(parts[0])
            total_time = float(parts[1])
        except Exception:
            continue
        return {
            "source": url,
            "latency_ms": round(start_transfer * 1000.0, 1),
            "latency_total_ms": round(total_time * 1000.0, 1),
            "http_code": parts[2],
        }
    return {}


def measure_speed():
    for url in speed_urls:
        completed = run_curl(
            url,
            write_out="%{speed_download}|%{size_download}|%{time_total}|%{http_code}",
            max_time=40,
        )
        if completed.returncode != 0:
            continue
        parts = (completed.stdout or "").strip().split("|")
        if len(parts) != 4:
            continue
        try:
            speed_download = float(parts[0])
            size_download = float(parts[1])
            total_time = float(parts[2])
        except Exception:
            continue
        if size_download <= 0 or speed_download <= 0:
            continue
        return {
            "source": url,
            "speed_download": round(speed_download, 1),
            "speed_mbps": round((speed_download * 8.0) / 1_000_000.0, 3),
            "size_download": int(size_download),
            "download_time_ms": round(total_time * 1000.0, 1),
            "http_code": parts[3],
        }
    return {}


main_sock = control_connect(main_cookie_path, main_port)
probe_sock = control_connect(probe_cookie_path, probe_port)

try:
    relays = parse_ns_all(send_cmd(main_sock, "GETINFO ns/all"))
    relay_by_fp = {str(row.get("fingerprint") or ""): row for row in relays}
    country_cache = {}
    shortlisted = []
    seen_fps = set()
    per_country = {}

    if current_fp and current_fp in relay_by_fp:
        current_row = dict(relay_by_fp[current_fp])
        current_country = ip_to_country(main_sock, current_row["ip"], country_cache)
        if current_country and current_country not in ignored_countries:
            current_row["country_code"] = current_country
            shortlisted.append(current_row)
            seen_fps.add(current_fp)
            per_country[current_country] = 1

    scanned = 0
    for relay in relays:
        scanned += 1
        fingerprint = str(relay.get("fingerprint") or "")
        if not fingerprint or fingerprint in seen_fps:
            if scanned >= scan_limit and shortlisted:
                break
            continue
        country_code = ip_to_country(main_sock, relay["ip"], country_cache)
        if not country_code or country_code in ignored_countries:
            if scanned >= scan_limit and shortlisted:
                break
            continue
        if per_country.get(country_code, 0) >= country_limit:
            if scanned >= scan_limit and shortlisted:
                break
            continue
        relay = dict(relay)
        relay["country_code"] = country_code
        shortlisted.append(relay)
        seen_fps.add(fingerprint)
        per_country[country_code] = per_country.get(country_code, 0) + 1
        if len(shortlisted) >= candidate_target:
            break
        if scanned >= scan_limit and shortlisted:
            break

    if not shortlisted:
        if ignored_countries:
            ignored_text = ", ".join(code.upper() for code in sorted(ignored_countries))
            raise SystemExit(f"no candidate exit relays available outside saved performance-ignore countries: {ignored_text}")
        raise SystemExit("tor performance mode found no usable exit relays")

    samples = []
    for relay in shortlisted:
        send_cmd(probe_sock, f"SETCONF ExitNodes=${relay['fingerprint']} StrictNodes=1")
        send_cmd(probe_sock, "SIGNAL NEWNYM")
        public_geo = {}
        active = {}
        matched = False
        for _ in range(20):
            public_geo = lookup_probe_geo()
            public_ip = str(public_geo.get("ip") or "").strip() if public_geo.get("available") else ""
            active = current_exit(probe_sock, public_ip)
            if active.get("fingerprint", "").lstrip("$").upper() == relay["fingerprint"]:
                matched = True
                break
            if public_ip and relay.get("ip") and public_ip == relay["ip"]:
                matched = True
                break
            time.sleep(1.0)
        if not matched:
            continue

        latency = measure_latency()
        speed = measure_speed()
        if not speed:
            continue

        public_ip = str(public_geo.get("ip") or "").strip() if public_geo.get("available") else ""
        active = current_exit(probe_sock, public_ip)
        sample = {
            "fingerprint": active.get("fingerprint") or f"${relay['fingerprint']}",
            "nickname": active.get("nickname") or relay.get("nickname") or "",
            "ip": public_ip or active.get("ip") or relay.get("ip") or "",
            "country_code": str(public_geo.get("country_code") or relay.get("country_code") or "").lower(),
            "country": str(public_geo.get("country") or ""),
            "region": str(public_geo.get("region") or ""),
            "city": str(public_geo.get("city") or ""),
            "public_ip": public_ip or active.get("ip") or relay.get("ip") or "",
            "bandwidth": int(relay.get("bandwidth", 0) or 0),
            "probe": {
                "latency_ms": float(latency.get("latency_ms", 999999.0) or 999999.0),
                "latency_source": latency.get("source") or "",
                "speed_download": float(speed.get("speed_download", 0.0) or 0.0),
                "speed_mbps": float(speed.get("speed_mbps", 0.0) or 0.0),
                "size_download": int(speed.get("size_download", 0) or 0),
                "speed_source": speed.get("source") or "",
                "download_time_ms": float(speed.get("download_time_ms", 999999.0) or 999999.0),
            },
        }
        samples.append(sample)
        if len(samples) >= sample_target:
            break

    if not samples:
        raise SystemExit("tor performance mode could not measure any usable exit relays")

    best = max(
        samples,
        key=lambda item: (
            float(item.get("probe", {}).get("speed_download", 0.0) or 0.0),
            -float(item.get("probe", {}).get("latency_ms", 999999.0) or 999999.0),
            -float(item.get("probe", {}).get("download_time_ms", 999999.0) or 999999.0),
        ),
    )

    best_fp = str(best.get("fingerprint") or "").lstrip("$").upper()
    if not best_fp:
        raise SystemExit("tor performance mode found no valid relay fingerprint to pin")

    payload = {
        "ignored_country_codes": sorted(ignored_countries),
        "trigger": str(trigger or ""),
        "sample_count": len(samples),
        "samples": samples,
        "best": best,
        "current_same": bool(current_fp and best_fp == current_fp),
    }
    print(json.dumps(payload, indent=2, sort_keys=True))
finally:
    for sock in (probe_sock, main_sock):
        try:
            send_cmd(sock, "QUIT")
        except Exception:
            try:
                sock.close()
            except Exception:
                pass
PY
)" || rc=$?
  if (( rc != 0 )); then
    chroot_tor_performance_probe_stop "$distro" >/dev/null 2>&1 || true
    chroot_tor_performance_probe_cleanup_paths "$distro"
    return "$rc"
  fi

  if ! "$CHROOT_PYTHON_BIN" - "$selection_json" <<'PY' >/dev/null
import json
import sys

try:
    payload = json.loads(sys.argv[1])
except Exception:
    raise SystemExit(1)
if not isinstance(payload, dict):
    raise SystemExit(1)
best = payload.get("best", {})
if not isinstance(best, dict) or not str(best.get("fingerprint") or "").strip():
    raise SystemExit(1)
PY
  then
    chroot_tor_performance_probe_stop "$distro" >/dev/null 2>&1 || true
    chroot_tor_performance_probe_cleanup_paths "$distro"
    chroot_die "performance selection returned an invalid payload"
  fi

  chroot_tor_performance_probe_stop "$distro" >/dev/null 2>&1 || true
  chroot_tor_performance_probe_cleanup_paths "$distro"
  printf '%s\n' "$selection_json"
}

chroot_tor_performance_probe_current_json() {
  local distro="$1"
  local pid public_exit_json active_exit_json

  pid="$(chroot_tor_current_pid "$distro" 2>/dev/null || true)"
  [[ -n "$pid" ]] || chroot_die "tor daemon is not running for $distro"
  chroot_tor_bootstrap_complete "$distro" >/dev/null 2>&1 || chroot_die "tor daemon is not bootstrapped yet for $distro"
  [[ -n "${CHROOT_CURL_BIN:-}" ]] || chroot_die "curl is required for tor performance mode"

  public_exit_json="$(chroot_tor_public_exit_json "$distro" "$pid" 1 "$CHROOT_TOR_DEFAULT_SOCKS_PORT")"
  active_exit_json="$(chroot_tor_active_exit_json "$distro" "$pid" 1 "$public_exit_json")"

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$CHROOT_CURL_BIN" "$CHROOT_TOR_DEFAULT_SOCKS_PORT" "$public_exit_json" "$active_exit_json" <<'PY'
import json
import subprocess
import sys

curl_bin, socks_port_text, public_exit_text, active_exit_text = sys.argv[1:5]
socks_port = int(socks_port_text)
latency_urls = [
    "https://www.google.com/generate_204",
    "https://cp.cloudflare.com/generate_204",
]
speed_urls = [
    "https://speed.cloudflare.com/__down?bytes=750000",
    "https://proof.ovh.net/files/1Mb.dat",
]

def run_curl(url, *, write_out, max_time):
    command = [
        curl_bin,
        "--fail",
        "--location",
        "--connect-timeout",
        "8",
        "--max-time",
        str(max_time),
        "--silent",
        "--show-error",
        "--socks5-hostname",
        f"127.0.0.1:{socks_port}",
        "--write-out",
        write_out,
        url,
        "-o",
        "/dev/null",
    ]
    return subprocess.run(command, capture_output=True, text=True)

def measure_latency():
    for url in latency_urls:
        completed = run_curl(url, write_out="%{time_starttransfer}|%{http_code}", max_time=15)
        if completed.returncode != 0:
            continue
        parts = (completed.stdout or "").strip().split("|")
        if len(parts) != 2:
            continue
        try:
            latency_ms = round(float(parts[0]) * 1000.0, 1)
        except Exception:
            continue
        return {"latency_ms": latency_ms, "latency_source": url}
    return {}

def measure_speed():
    for url in speed_urls:
        completed = run_curl(url, write_out="%{speed_download}|%{size_download}|%{time_total}|%{http_code}", max_time=25)
        if completed.returncode != 0:
            continue
        parts = (completed.stdout or "").strip().split("|")
        if len(parts) != 4:
            continue
        try:
            speed_download = float(parts[0])
            size_download = float(parts[1])
            total_time = float(parts[2])
        except Exception:
            continue
        if speed_download <= 0 or size_download <= 0:
            continue
        return {
            "speed_mbps": round((speed_download * 8.0) / 1_000_000.0, 3),
            "download_time_ms": round(total_time * 1000.0, 1),
        }
    return {}

try:
    public_exit = json.loads(public_exit_text)
    if not isinstance(public_exit, dict):
        public_exit = {}
except Exception:
    public_exit = {}
try:
    active_exit = json.loads(active_exit_text)
    if not isinstance(active_exit, dict):
        active_exit = {}
except Exception:
    active_exit = {}

latency = measure_latency()
speed = measure_speed()
ok = bool(active_exit.get("available") and public_exit.get("available") and latency and speed)
payload = {
    "ok": ok,
    "active_exit": active_exit,
    "public_exit": public_exit,
    "latency_ms": latency.get("latency_ms"),
    "latency_source": latency.get("latency_source", ""),
    "speed_mbps": speed.get("speed_mbps"),
    "download_time_ms": speed.get("download_time_ms"),
}
if not ok:
    payload["error"] = str(public_exit.get("error") or active_exit.get("error") or "probe_failed")
print(json.dumps(payload, indent=2, sort_keys=True))
PY
}

chroot_tor_performance_apply_selection() {
  local distro="$1"
  local selection_json="$2"
  local trigger="${3:-startup}"
  local cookie_file current_same best_fp patch_json now_ts

  cookie_file="$(chroot_tor_rootfs_control_cookie_file "$distro")"
  [[ -f "$cookie_file" ]] || chroot_die "tor control cookie is missing for $distro"

  best_fp="$("$CHROOT_PYTHON_BIN" - "$selection_json" <<'PY'
import json
import sys

try:
    payload = json.loads(sys.argv[1])
except Exception:
    payload = {}
best = payload.get("best", {}) if isinstance(payload.get("best"), dict) else {}
print(str(best.get("fingerprint", "") or ""))
PY
)"
  [[ -n "$best_fp" ]] || chroot_die "performance selection returned no best exit fingerprint"

  current_same="$("$CHROOT_PYTHON_BIN" - "$selection_json" <<'PY'
import json
import sys

try:
    payload = json.loads(sys.argv[1])
except Exception:
    payload = {}
print("1" if payload.get("current_same") else "0")
PY
)"

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$cookie_file" "$CHROOT_TOR_DEFAULT_CONTROL_PORT" "$best_fp" <<'PY'
import socket
import sys

cookie_path, port_text, best_fp = sys.argv[1:4]
port = int(port_text)
best_fp = str(best_fp or "").strip()
if not best_fp:
    raise SystemExit("missing best fingerprint")

with open(cookie_path, "rb") as fh:
    cookie = fh.read().strip()

def recv_reply(sock):
    data = b""
    while True:
        chunk = sock.recv(4096)
        if not chunk:
            break
        data += chunk
        if data.endswith(b"250 OK\r\n") or data.startswith(b"5"):
            break
    return data.decode("utf-8", errors="replace")

def send_cmd(sock, command):
    sock.sendall((command + "\r\n").encode("utf-8", errors="replace"))
    reply = recv_reply(sock)
    if not reply.startswith("250"):
        raise SystemExit(f"Tor control command failed ({command}): {reply.strip()}")

with socket.create_connection(("127.0.0.1", port), timeout=5.0) as sock:
    send_cmd(sock, f"AUTHENTICATE {cookie.hex()}")
    send_cmd(sock, f"SETCONF ExitNodes={best_fp} StrictNodes=1")
    send_cmd(sock, "QUIT")
PY

  if [[ "$trigger" != "startup" && "$current_same" != "1" ]]; then
    chroot_tor_control_signal_newnym "$cookie_file" "$CHROOT_TOR_DEFAULT_CONTROL_PORT"
  fi

  now_ts="$(chroot_now_ts)"
  patch_json="$("$CHROOT_PYTHON_BIN" - "$selection_json" "$trigger" "$now_ts" "$current_same" <<'PY'
import json
import sys

selection_text, trigger, now_ts, current_same_text = sys.argv[1:5]
try:
    payload = json.loads(selection_text)
except Exception:
    payload = {}
best = payload.get("best", {}) if isinstance(payload.get("best"), dict) else {}
probe = best.get("probe", {}) if isinstance(best.get("probe"), dict) else {}
current_same = str(current_same_text).strip() == "1"
patch = {
    "active": True,
    "current_exit_country_code": str(best.get("country_code") or ""),
    "current_exit_fingerprint": str(best.get("fingerprint") or ""),
    "current_exit_ip": str(best.get("ip") or ""),
    "current_exit_nickname": str(best.get("nickname") or ""),
    "current_score": {
        "latency_ms": probe.get("latency_ms"),
        "speed_mbps": probe.get("speed_mbps"),
    },
    "degraded": False,
    "last_error": "",
    "last_probe_at": now_ts,
    "last_reselect_at": now_ts,
    "last_trigger": str(trigger or ""),
    "sample_count": int(payload.get("sample_count", 0) or 0),
}
if not current_same:
    patch["last_switch_at"] = now_ts
print(json.dumps(patch, indent=2, sort_keys=True))
PY
)"
  chroot_tor_performance_merge_json "$distro" "$patch_json"
  chroot_tor_performance_sync_freeze_from_selection "$distro" "$selection_json" "$now_ts"
}

chroot_tor_performance_controller_loop() {
  local distro="$1"
  local controller_pid="${2:-}"
  local controller_pid_starttime="${3:-}"
  local run_mode current_fp baseline_speed baseline_latency
  local probe_interval="${CHROOT_TOR_PERFORMANCE_PROBE_INTERVAL_SEC_DEFAULT}"
  local failure_threshold="${CHROOT_TOR_PERFORMANCE_FAIL_THRESHOLD_DEFAULT}"
  local consecutive_failures=0
  local rotation_sec last_reselect_epoch last_probe_epoch now_epoch
  local request_reason="" selection_json="" probe_json="" state_line=""

  if [[ -z "$controller_pid" ]]; then
    controller_pid="${BASHPID:-$$}"
  fi
  if [[ -z "$controller_pid_starttime" && "$controller_pid" =~ ^[0-9]+$ ]]; then
    controller_pid_starttime="$(chroot_tor_pid_starttime "$controller_pid" 2>/dev/null || true)"
  fi

  IFS='|' read -r _active _controller_pid current_fp baseline_speed baseline_latency <<<"$(chroot_tor_performance_state_tsv "$distro")"
  rotation_sec="$(( $(chroot_tor_rotation_minutes) * 60 ))"
  (( rotation_sec > 0 )) || rotation_sec=300
  last_reselect_epoch="$(date +%s)"
  last_probe_epoch="$last_reselect_epoch"
  chroot_tor_performance_merge_json "$distro" "$("$CHROOT_PYTHON_BIN" - "$controller_pid" "$controller_pid_starttime" <<'PY'
import json
import sys

pid_text, start_text = sys.argv[1:3]
payload = {"active": True, "last_error": ""}
if str(pid_text).strip().isdigit():
    payload["controller_pid"] = int(pid_text)
else:
    payload["controller_pid"] = None
if str(start_text).strip().isdigit():
    payload["controller_pid_starttime"] = int(start_text)
else:
    payload["controller_pid_starttime"] = None
print(json.dumps(payload, indent=2, sort_keys=True))
PY
)"

  while true; do
    run_mode="$(chroot_tor_saved_run_mode "$distro" | tr -d '[:space:]')"
    chroot_tor_is_active_distro "$distro" || break
    chroot_tor_current_pid "$distro" >/dev/null 2>&1 || break
    chroot_tor_bootstrap_complete "$distro" >/dev/null 2>&1 || break
    chroot_tor_performance_mode_enabled_for_run "$distro" "$run_mode" || break

    request_reason="$(chroot_tor_performance_request_reason "$distro" 2>/dev/null || true)"
    now_epoch="$(date +%s)"

    if [[ -n "$request_reason" || $((now_epoch - last_reselect_epoch)) -ge "$rotation_sec" ]]; then
      [[ -n "$request_reason" ]] || request_reason="rotation"
      if selection_json="$(chroot_tor_performance_select_json "$distro" "$request_reason" "$current_fp")"; then
        chroot_tor_performance_apply_selection "$distro" "$selection_json" "$request_reason"
        current_fp="$("$CHROOT_PYTHON_BIN" - "$selection_json" <<'PY'
import json
import sys
try:
    payload = json.loads(sys.argv[1])
except Exception:
    payload = {}
best = payload.get("best", {}) if isinstance(payload.get("best"), dict) else {}
print(str(best.get("fingerprint") or ""))
PY
)"
        IFS=$'\t' read -r baseline_speed baseline_latency <<<"$("$CHROOT_PYTHON_BIN" - "$selection_json" <<'PY'
import json
import sys
try:
    payload = json.loads(sys.argv[1])
except Exception:
    payload = {}
best = payload.get("best", {}) if isinstance(payload.get("best"), dict) else {}
probe = best.get("probe", {}) if isinstance(best.get("probe"), dict) else {}
print("\t".join([
    str(probe.get("speed_mbps", "") if probe.get("speed_mbps") is not None else ""),
    str(probe.get("latency_ms", "") if probe.get("latency_ms") is not None else ""),
]))
PY
)"
        consecutive_failures=0
        last_reselect_epoch="$now_epoch"
        last_probe_epoch="$now_epoch"
        chroot_tor_performance_clear_request "$distro"
      else
        chroot_tor_performance_merge_json "$distro" "$("$CHROOT_PYTHON_BIN" - "performance reselect failed for trigger '$request_reason'" <<'PY'
import json
import sys
print(json.dumps({"degraded": True, "last_error": sys.argv[1]}, indent=2, sort_keys=True))
PY
)"
        chroot_tor_performance_clear_request "$distro"
      fi
      sleep 5
      continue
    fi

    if (( now_epoch - last_probe_epoch >= probe_interval )); then
      if probe_json="$(chroot_tor_performance_probe_current_json "$distro")"; then
        state_line="$("$CHROOT_PYTHON_BIN" - "$probe_json" "$baseline_speed" "$baseline_latency" "$failure_threshold" <<'PY'
import json
import sys

probe_text, baseline_speed_text, baseline_latency_text, threshold_text = sys.argv[1:5]
try:
    payload = json.loads(probe_text)
except Exception:
    payload = {}

def parse_float(text):
    try:
        return float(str(text).strip())
    except Exception:
        return None

threshold = int(threshold_text or 2)
baseline_speed = parse_float(baseline_speed_text)
baseline_latency = parse_float(baseline_latency_text)
speed = parse_float(payload.get("speed_mbps"))
latency = parse_float(payload.get("latency_ms"))
ok = bool(payload.get("ok"))
degraded = False

if not ok:
    degraded = True
elif speed is not None and baseline_speed is not None and baseline_speed > 0:
    if speed < max(0.75, baseline_speed * 0.35):
        degraded = True
elif speed is not None and speed < 0.5:
    degraded = True

if ok and not degraded and latency is not None and baseline_latency is not None and baseline_latency > 0:
    if latency > max(2500.0, baseline_latency * 2.25) and speed is not None and baseline_speed is not None and speed < baseline_speed:
        degraded = True

active_exit = payload.get("active_exit", {}) if isinstance(payload.get("active_exit"), dict) else {}
public_exit = payload.get("public_exit", {}) if isinstance(payload.get("public_exit"), dict) else {}
error = str(payload.get("error") or "")
print("\t".join([
    "1" if ok else "0",
    "1" if degraded else "0",
    str(speed if speed is not None else ""),
    str(latency if latency is not None else ""),
    str(active_exit.get("fingerprint") or ""),
    str(public_exit.get("country_code") or ""),
    error,
]))
PY
)"
        local ok_flag degraded_flag current_speed current_latency active_fp active_country probe_error
        IFS=$'\t' read -r ok_flag degraded_flag current_speed current_latency active_fp active_country probe_error <<<"$state_line"
        if [[ "$ok_flag" == "1" ]]; then
          consecutive_failures=0
          current_fp="${active_fp:-$current_fp}"
          chroot_tor_performance_merge_json "$distro" "$("$CHROOT_PYTHON_BIN" - "$probe_json" "$(chroot_now_ts)" <<'PY'
import json
import sys
probe_text, now_ts = sys.argv[1:3]
try:
    payload = json.loads(probe_text)
except Exception:
    payload = {}
active_exit = payload.get("active_exit", {}) if isinstance(payload.get("active_exit"), dict) else {}
public_exit = payload.get("public_exit", {}) if isinstance(payload.get("public_exit"), dict) else {}
patch = {
    "current_exit_country_code": str(public_exit.get("country_code") or active_exit.get("country_code") or ""),
    "current_exit_fingerprint": str(active_exit.get("fingerprint") or ""),
    "current_exit_ip": str(public_exit.get("ip") or active_exit.get("ip") or ""),
    "current_exit_nickname": str(active_exit.get("nickname") or ""),
    "current_score": {
        "latency_ms": payload.get("latency_ms"),
        "speed_mbps": payload.get("speed_mbps"),
    },
    "degraded": False,
    "last_error": "",
    "last_probe_at": now_ts,
}
print(json.dumps(patch, indent=2, sort_keys=True))
PY
)"
          if [[ "$degraded_flag" == "1" ]]; then
            consecutive_failures=$((consecutive_failures + 1))
          fi
        else
          consecutive_failures=$((consecutive_failures + 1))
          chroot_tor_performance_merge_json "$distro" "$("$CHROOT_PYTHON_BIN" - "${probe_error:-probe_failed}" "$(chroot_now_ts)" <<'PY'
import json
import sys
print(json.dumps({"degraded": True, "last_error": sys.argv[1], "last_probe_at": sys.argv[2]}, indent=2, sort_keys=True))
PY
)"
        fi

        if (( consecutive_failures >= failure_threshold )); then
          chroot_tor_performance_request "$distro" "degraded"
          consecutive_failures=0
        fi
      fi
      last_probe_epoch="$now_epoch"
    fi

    sleep 5
  done

  chroot_tor_performance_merge_json "$distro" "$(printf '{\"active\": false, \"controller_pid\": null, \"controller_pid_starttime\": null}\n')"
}

chroot_tor_performance_controller_start() {
  local distro="$1"
  local pid pid_start saved_pid saved_start current_start attempt=0

  IFS='|' read -r saved_pid saved_start <<<"$(chroot_tor_performance_controller_identity_tsv "$distro" 2>/dev/null || true)"
  if [[ "$saved_pid" =~ ^[0-9]+$ ]] && chroot_tor_pid_is_live "$saved_pid"; then
    current_start="$(chroot_tor_pid_starttime "$saved_pid" 2>/dev/null || true)"
    if [[ -n "$saved_start" && "$current_start" == "$saved_start" ]]; then
      printf '%s\n' "$saved_pid"
      return 0
    fi
  fi

  (
    trap '' HUP
    chroot_tor_performance_controller_loop "$distro"
  ) </dev/null >/dev/null 2>&1 &
  pid=$!
  while (( attempt < 10 )); do
    pid_start="$(chroot_tor_pid_starttime "$pid" 2>/dev/null || true)"
    [[ -n "$pid_start" ]] && break
    sleep 0.1
    attempt=$((attempt + 1))
  done
  chroot_tor_performance_merge_json "$distro" "$("$CHROOT_PYTHON_BIN" - "$pid" "$pid_start" <<'PY'
import json
import sys

pid_text, start_text = sys.argv[1:3]
payload = {"active": True}
payload["controller_pid"] = int(pid_text) if str(pid_text).strip().isdigit() else None
payload["controller_pid_starttime"] = int(start_text) if str(start_text).strip().isdigit() else None
print(json.dumps(payload, indent=2, sort_keys=True))
PY
)"
  printf '%s\n' "$pid"
}

chroot_tor_performance_controller_stop() {
  local distro="$1"
  local pid saved_start current_start i
  IFS='|' read -r pid saved_start <<<"$(chroot_tor_performance_controller_identity_tsv "$distro" 2>/dev/null || true)"
  chroot_tor_performance_clear_request "$distro"
  if [[ "$pid" =~ ^[0-9]+$ ]] && chroot_tor_pid_is_live "$pid"; then
    current_start="$(chroot_tor_pid_starttime "$pid" 2>/dev/null || true)"
  else
    current_start=""
  fi
  if [[ "$pid" =~ ^[0-9]+$ ]] && [[ -n "$saved_start" ]] && [[ "$current_start" == "$saved_start" ]]; then
    kill -TERM "$pid" >/dev/null 2>&1 || true
    for (( i=0; i<10; i++ )); do
      if ! chroot_tor_pid_is_live "$pid"; then
        break
      fi
      sleep 1
    done
    if chroot_tor_pid_is_live "$pid"; then
      kill -KILL "$pid" >/dev/null 2>&1 || true
    fi
  fi
  chroot_tor_performance_clear "$distro"
}
