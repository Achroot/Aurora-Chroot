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
  local config_dir runtime_dir data_dir log_file

  config_dir="$(chroot_tor_rootfs_config_dir "$distro")"
  runtime_dir="$(chroot_tor_rootfs_runtime_dir "$distro")"
  data_dir="$(chroot_tor_rootfs_data_dir "$distro")"
  log_file="$(chroot_tor_rootfs_runtime_log_file "$distro")"

  chroot_run_root mkdir -p "$config_dir" "$runtime_dir" "$data_dir" "$(dirname "$log_file")"
  chroot_run_root touch "$log_file"
  chroot_run_root chown "$daemon_uid:$daemon_gid" "$runtime_dir" "$data_dir" "$log_file" >/dev/null 2>&1 || true
  chroot_run_root chmod 700 "$runtime_dir" "$data_dir" >/dev/null 2>&1 || true
  chroot_run_root chmod 600 "$log_file" >/dev/null 2>&1 || true
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
    printf 'Log notice file /var/log/aurora-tor.log\n'
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

chroot_tor_ports_ready() {
  local distro="$1"
  local log_file
  log_file="$(chroot_tor_rootfs_runtime_log_file "$distro")"
  chroot_tor_port_ready "$CHROOT_TOR_DEFAULT_SOCKS_PORT" || return 1
  [[ -f "$log_file" ]] || return 1
  chroot_run_root grep -q 'Opened DNS listener connection (ready)' "$log_file" >/dev/null 2>&1 || return 1
  chroot_run_root grep -q 'Opened Transparent pf/netfilter listener connection (ready)' "$log_file" >/dev/null 2>&1 || return 1
}

chroot_tor_log_bootstrap_complete() {
  local distro="$1"
  local log_file
  log_file="$(chroot_tor_rootfs_runtime_log_file "$distro")"
  [[ -f "$log_file" ]] || return 1
  chroot_run_root grep -q 'Bootstrapped 100%' "$log_file" >/dev/null 2>&1
}

chroot_tor_log_excerpt() {
  local distro="$1"
  local log_file tmp
  log_file="$(chroot_tor_rootfs_runtime_log_file "$distro")"
  [[ -s "$log_file" ]] || return 1
  tmp="$CHROOT_TMP_DIR/tor-log.$$.txt"
  chroot_run_root cat "$log_file" >"$tmp" 2>/dev/null || {
    rm -f -- "$tmp"
    return 1
  }
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$tmp" <<'PY'
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        lines = fh.readlines()[-40:]
except Exception:
    sys.exit(1)

for raw_line in reversed(lines):
    line = " ".join(raw_line.replace("\t", " ").split())
    if line:
        print(line[:240])
        sys.exit(0)
sys.exit(1)
PY
  local rc=$?
  rm -f -- "$tmp"
  return "$rc"
}

chroot_tor_start_daemon() {
  local distro="$1"
  local daemon_uid="$2"
  local daemon_gid="$3"
  local tor_bin

  tor_bin="$(chroot_tor_chroot_tor_bin "$distro" || true)"
  [[ -n "$tor_bin" ]] || chroot_die "tor binary missing inside $distro"

  chroot_run_root rm -f -- "$(chroot_tor_rootfs_pid_file "$distro")" >/dev/null 2>&1 || true
  chroot_run_root rm -f -- "$(chroot_tor_rootfs_runtime_log_file "$distro")" >/dev/null 2>&1 || true
  chroot_run_root touch "$(chroot_tor_rootfs_runtime_log_file "$distro")"
  chroot_run_root chown "$daemon_uid:$daemon_gid" "$(chroot_tor_rootfs_runtime_log_file "$distro")" >/dev/null 2>&1 || true
  chroot_run_root chmod 600 "$(chroot_tor_rootfs_runtime_log_file "$distro")" >/dev/null 2>&1 || true

  chroot_tor_run_in_distro "$distro" "$tor_bin" --RunAsDaemon 1 -f /etc/aurora-tor/torrc
}

chroot_tor_wait_for_bootstrap() {
  local distro="$1"
  local timeout="${2:-$CHROOT_TOR_BOOTSTRAP_TIMEOUT_SEC_DEFAULT}"
  local elapsed=0

  while (( elapsed < timeout )); do
    if chroot_tor_current_pid "$distro" >/dev/null 2>&1; then
      if chroot_tor_ports_ready "$distro" && chroot_tor_log_bootstrap_complete "$distro"; then
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
  local cookie_file pid active_distro active_at public_exit_json freeze_json refreshed_public_exit_json

  IFS='|' read -r active_distro active_at <<<"$(chroot_tor_global_active_tsv)"
  [[ -n "$active_distro" && "$active_distro" == "$distro" ]] || chroot_die "selected distro is not the active Tor backend: $distro"

  pid="$(chroot_tor_current_pid "$distro" 2>/dev/null || true)"
  [[ -n "$pid" ]] || chroot_die "tor daemon is not running for $distro"
  chroot_tor_log_bootstrap_complete "$distro" >/dev/null 2>&1 || chroot_die "tor daemon is not bootstrapped yet for $distro"

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

chroot_tor_newnym() {
  local distro="$1"
  local cookie_file pid active_distro active_at

  IFS='|' read -r active_distro active_at <<<"$(chroot_tor_global_active_tsv)"
  [[ -n "$active_distro" && "$active_distro" == "$distro" ]] || chroot_die "selected distro is not the active Tor backend: $distro"

  pid="$(chroot_tor_current_pid "$distro" 2>/dev/null || true)"
  [[ -n "$pid" ]] || chroot_die "tor daemon is not running for $distro"

  cookie_file="$(chroot_tor_rootfs_control_cookie_file "$distro")"
  [[ -f "$cookie_file" ]] || chroot_die "tor control cookie is missing for $distro"

  chroot_tor_apply_base_exit_policy "$distro"
  chroot_tor_freeze_clear "$distro"

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$cookie_file" "$CHROOT_TOR_DEFAULT_CONTROL_PORT" <<'PY'
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
