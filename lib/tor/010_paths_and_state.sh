chroot_tor_global_state_dir() {
  printf '%s/_global/tor' "$CHROOT_STATE_DIR"
}

chroot_tor_global_active_file() {
  printf '%s/active.json' "$(chroot_tor_global_state_dir)"
}

chroot_tor_state_dir() {
  local distro="$1"
  printf '%s/tor' "$(chroot_distro_state_dir "$distro")"
}

chroot_tor_status_file() {
  local distro="$1"
  printf '%s/status.json' "$(chroot_tor_state_dir "$distro")"
}

chroot_tor_config_file() {
  local distro="$1"
  printf '%s/config.json' "$(chroot_tor_state_dir "$distro")"
}

chroot_tor_apps_inventory_file() {
  local distro="$1"
  printf '%s/apps.json' "$(chroot_tor_state_dir "$distro")"
}

chroot_tor_exit_inventory_file() {
  local distro="$1"
  printf '%s/exit.json' "$(chroot_tor_state_dir "$distro")"
}

chroot_tor_freeze_file() {
  local distro="$1"
  printf '%s/freeze.json' "$(chroot_tor_state_dir "$distro")"
}

chroot_tor_targets_file() {
  local distro="$1"
  printf '%s/targets.json' "$(chroot_tor_state_dir "$distro")"
}

chroot_tor_policy_v4_prefs_file() {
  local distro="$1"
  printf '%s/policy-v4.prefs' "$(chroot_tor_state_dir "$distro")"
}

chroot_tor_policy_v6_prefs_file() {
  local distro="$1"
  printf '%s/policy-v6.prefs' "$(chroot_tor_state_dir "$distro")"
}

chroot_tor_rootfs_config_dir() {
  local distro="$1"
  printf '%s/etc/aurora-tor' "$(chroot_distro_rootfs_dir "$distro")"
}

chroot_tor_rootfs_torrc_file() {
  local distro="$1"
  printf '%s/torrc' "$(chroot_tor_rootfs_config_dir "$distro")"
}

chroot_tor_rootfs_runtime_dir() {
  local distro="$1"
  printf '%s/var/lib/aurora-tor' "$(chroot_distro_rootfs_dir "$distro")"
}

chroot_tor_rootfs_data_dir() {
  local distro="$1"
  printf '%s/data' "$(chroot_tor_rootfs_runtime_dir "$distro")"
}

chroot_tor_rootfs_runtime_log_file() {
  local distro="$1"
  printf '%s/var/log/aurora-tor.log' "$(chroot_distro_rootfs_dir "$distro")"
}

chroot_tor_rootfs_pid_file() {
  local distro="$1"
  printf '%s/tor.pid' "$(chroot_tor_rootfs_runtime_dir "$distro")"
}

chroot_tor_rootfs_control_cookie_file() {
  local distro="$1"
  printf '%s/control_auth_cookie' "$(chroot_tor_rootfs_runtime_dir "$distro")"
}

chroot_tor_session_id() {
  printf 'tor\n'
}

chroot_tor_ensure_state_layout() {
  local distro="$1"
  chroot_ensure_distro_dirs "$distro"
  mkdir -p "$(chroot_tor_global_state_dir)"
  mkdir -p "$(chroot_tor_state_dir "$distro")"
}

chroot_tor_default_status_json() {
  local distro="$1"
  cat <<JSON
{
  "schema_version": $CHROOT_TOR_SCHEMA_VERSION,
  "distro": "$distro",
  "enabled": false,
  "run_mode": "",
  "mode": "system-wide",
  "activated_at": "",
  "last_changed_at": "",
  "warnings": [],
  "daemon": {
    "identity_mode": "",
    "user": "",
    "uid": null,
    "gid": null,
    "pid": null,
    "pid_starttime": null,
    "socks_port": $CHROOT_TOR_DEFAULT_SOCKS_PORT,
    "trans_port": $CHROOT_TOR_DEFAULT_TRANS_PORT,
    "dns_port": $CHROOT_TOR_DEFAULT_DNS_PORT,
    "control_port": $CHROOT_TOR_DEFAULT_CONTROL_PORT
  },
  "routing": {
    "termux_uid_included": false,
    "root_uid_included": false,
    "udp_policy": "blocked",
    "ipv6_policy": "blocked",
    "lan_bypass": true
  },
  "backend": {
    "distro_family": ""
  },
  "last_error": ""
}
JSON
}

chroot_tor_default_freeze_json() {
  cat <<'JSON'
{
  "active": false,
  "city": "",
  "country": "",
  "country_code": "",
  "exit_fingerprint": "",
  "exit_ip": "",
  "exit_nickname": "",
  "pinned_at": "",
  "public_ip": "",
  "region": "",
  "source": ""
}
JSON
}

chroot_tor_ensure_status_file() {
  local distro="$1"
  local status_file tmp
  status_file="$(chroot_tor_status_file "$distro")"
  [[ -f "$status_file" ]] && return 0
  chroot_tor_ensure_state_layout "$distro"
  tmp="$status_file.$$.tmp"
  chroot_tor_default_status_json "$distro" >"$tmp"
  mv -f -- "$tmp" "$status_file"
}

chroot_tor_freeze_state_json() {
  local distro="$1"
  local freeze_file
  freeze_file="$(chroot_tor_freeze_file "$distro")"
  [[ -f "$freeze_file" ]] || {
    chroot_tor_default_freeze_json
    return 0
  }
  cat "$freeze_file"
}

chroot_tor_freeze_clear() {
  local distro="$1"
  local freeze_file tmp
  freeze_file="$(chroot_tor_freeze_file "$distro")"
  tmp="$freeze_file.$$.tmp"
  chroot_tor_ensure_state_layout "$distro"
  chroot_tor_default_freeze_json >"$tmp"
  mv -f -- "$tmp" "$freeze_file"
}

chroot_tor_freeze_write_json() {
  local distro="$1"
  local json_text="$2"
  local freeze_file tmp
  freeze_file="$(chroot_tor_freeze_file "$distro")"
  tmp="$freeze_file.$$.tmp"
  chroot_tor_ensure_state_layout "$distro"
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$tmp" "$json_text" <<'PY'
import json
import sys

out_path, json_text = sys.argv[1:3]
try:
    data = json.loads(json_text)
except Exception as exc:
    raise SystemExit(f"invalid freeze json: {exc}")
if not isinstance(data, dict):
    raise SystemExit("invalid freeze json: payload must be an object")
with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY
  mv -f -- "$tmp" "$freeze_file"
}

chroot_tor_saved_state_tsv() {
  local distro="$1"
  local status_file
  status_file="$(chroot_tor_status_file "$distro")"
  [[ -f "$status_file" ]] || {
    printf '0||||||||%s|\n' "$distro"
    return 0
  }

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$status_file" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {}

daemon = data.get("daemon", {}) if isinstance(data.get("daemon"), dict) else {}
routing = data.get("routing", {}) if isinstance(data.get("routing"), dict) else {}
backend = data.get("backend", {}) if isinstance(data.get("backend"), dict) else {}

enabled = "1" if data.get("enabled") else "0"
identity_mode = str(daemon.get("identity_mode", "") or "")
daemon_user = str(daemon.get("user", "") or "")
uid = "" if daemon.get("uid") is None else str(daemon.get("uid"))
gid = "" if daemon.get("gid") is None else str(daemon.get("gid"))
termux = "1" if routing.get("termux_uid_included") else "0"
activated_at = str(data.get("activated_at", "") or "")
last_error = str(data.get("last_error", "") or "")
distro = str(data.get("distro", "") or "")
family = str(backend.get("distro_family", "") or "")
print("|".join([enabled, identity_mode, daemon_user, uid, gid, termux, activated_at, last_error, distro, family]))
PY
}

chroot_tor_saved_run_mode() {
  local distro="$1"
  local status_file
  status_file="$(chroot_tor_status_file "$distro")"
  [[ -f "$status_file" ]] || return 0
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$status_file" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {}
print(str(data.get("run_mode", "") or ""))
PY
}

chroot_tor_saved_pid_identity_tsv() {
  local distro="$1"
  local status_file
  status_file="$(chroot_tor_status_file "$distro")"
  [[ -f "$status_file" ]] || {
    printf '|\n'
    return 0
  }

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$status_file" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {}

daemon = data.get("daemon", {}) if isinstance(data.get("daemon"), dict) else {}
pid = "" if daemon.get("pid") is None else str(daemon.get("pid"))
starttime = "" if daemon.get("pid_starttime") is None else str(daemon.get("pid_starttime"))
print("|".join([pid, starttime]))
PY
}

chroot_tor_write_status_file() {
  local distro="$1"
  local enabled="$2"
  local activated_at="$3"
  local run_mode="$4"
  local identity_mode="$5"
  local daemon_user="$6"
  local daemon_uid="$7"
  local daemon_gid="$8"
  local termux_uid_included="$9"
  local daemon_pid="${10}"
  local daemon_starttime="${11}"
  local warnings_json="${12:-[]}"
  local last_error="${13:-}"
  local distro_family="${14:-}"
  local lan_bypass="${15:-1}"
  local status_file tmp

  status_file="$(chroot_tor_status_file "$distro")"
  tmp="$status_file.$$.tmp"
  chroot_tor_ensure_state_layout "$distro"
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$tmp" "$distro" "$enabled" "$activated_at" "$run_mode" "$identity_mode" "$daemon_user" "$daemon_uid" "$daemon_gid" "$termux_uid_included" "$daemon_pid" "$daemon_starttime" "$warnings_json" "$last_error" "$distro_family" "$lan_bypass" "$CHROOT_TOR_SCHEMA_VERSION" "$CHROOT_TOR_DEFAULT_SOCKS_PORT" "$CHROOT_TOR_DEFAULT_TRANS_PORT" "$CHROOT_TOR_DEFAULT_DNS_PORT" "$CHROOT_TOR_DEFAULT_CONTROL_PORT" "$(chroot_now_ts)" <<'PY'
import json
import sys

(
    out_path,
    distro,
    enabled_text,
    activated_at,
    run_mode,
    identity_mode,
    daemon_user,
    daemon_uid_text,
    daemon_gid_text,
    termux_text,
    daemon_pid_text,
    daemon_starttime_text,
    warnings_json_text,
    last_error,
    distro_family,
    lan_bypass_text,
    schema_version_text,
    socks_port_text,
    trans_port_text,
    dns_port_text,
    control_port_text,
    changed_at,
) = sys.argv[1:23]

def parse_int(value):
    text = str(value).strip()
    if not text:
        return None
    try:
        return int(text)
    except Exception:
        return None

enabled = str(enabled_text).strip().lower() in {"1", "true", "yes", "on"}
termux_uid_included = str(termux_text).strip().lower() in {"1", "true", "yes", "on"}
lan_bypass = str(lan_bypass_text).strip().lower() in {"1", "true", "yes", "on"}
daemon_uid = parse_int(daemon_uid_text)
daemon_gid = parse_int(daemon_gid_text)
daemon_pid = parse_int(daemon_pid_text)
daemon_starttime = parse_int(daemon_starttime_text)

try:
    warnings = json.loads(warnings_json_text)
    if not isinstance(warnings, list):
        warnings = []
except Exception:
    warnings = []

payload = {
    "schema_version": int(schema_version_text),
    "distro": distro,
    "enabled": enabled,
    "run_mode": str(run_mode or ""),
    "mode": "system-wide",
    "activated_at": activated_at if enabled else "",
    "last_changed_at": changed_at,
    "warnings": [str(x) for x in warnings if str(x).strip()],
    "daemon": {
        "identity_mode": identity_mode,
        "user": daemon_user,
        "uid": daemon_uid,
        "gid": daemon_gid,
        "pid": daemon_pid,
        "pid_starttime": daemon_starttime,
        "socks_port": int(socks_port_text),
        "trans_port": int(trans_port_text),
        "dns_port": int(dns_port_text),
        "control_port": int(control_port_text),
    },
    "routing": {
        "termux_uid_included": termux_uid_included,
        "root_uid_included": False,
        "udp_policy": "blocked",
        "ipv6_policy": "blocked",
        "lan_bypass": lan_bypass,
    },
    "backend": {
        "distro_family": distro_family,
    },
    "last_error": str(last_error or ""),
}

with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY
  mv -f -- "$tmp" "$status_file"
}

chroot_tor_global_active_tsv() {
  local active_file
  active_file="$(chroot_tor_global_active_file)"
  [[ -f "$active_file" ]] || {
    printf '|\n'
    return 0
  }

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$active_file" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {}

print("|".join([str(data.get("active_distro", "") or ""), str(data.get("activated_at", "") or "")]))
PY
}

chroot_tor_write_global_active() {
  local distro="$1"
  local activated_at="$2"
  local active_file tmp

  active_file="$(chroot_tor_global_active_file)"
  mkdir -p "$(dirname "$active_file")"
  tmp="$active_file.$$.tmp"
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$tmp" "$distro" "$activated_at" "$(chroot_now_ts)" <<'PY'
import json
import sys

out_path, distro, activated_at, changed_at = sys.argv[1:5]
payload = {
    "active_distro": distro,
    "activated_at": activated_at,
    "last_changed_at": changed_at,
}
with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY
  mv -f -- "$tmp" "$active_file"
}

chroot_tor_clear_global_active() {
  rm -f -- "$(chroot_tor_global_active_file)"
}

chroot_tor_policy_pref_file_path() {
  local distro="$1"
  local family="$2"
  case "$family" in
    4) chroot_tor_policy_v4_prefs_file "$distro" ;;
    6) chroot_tor_policy_v6_prefs_file "$distro" ;;
    *) return 1 ;;
  esac
}

chroot_tor_policy_write_prefs_file() {
  local distro="$1"
  local family="$2"
  shift 2
  local out_file tmp pref

  out_file="$(chroot_tor_policy_pref_file_path "$distro" "$family")" || return 1
  chroot_tor_ensure_state_layout "$distro"
  tmp="$out_file.$$.tmp"
  : >"$tmp"
  for pref in "$@"; do
    [[ "$pref" =~ ^[0-9]+$ ]] || continue
    printf '%s\n' "$pref" >>"$tmp"
  done
  mv -f -- "$tmp" "$out_file"
}

chroot_tor_policy_read_prefs_file() {
  local distro="$1"
  local family="$2"
  local in_file

  in_file="$(chroot_tor_policy_pref_file_path "$distro" "$family")" || return 1
  [[ -f "$in_file" ]] || return 0
  awk '/^[0-9]+$/ {print $1}' "$in_file"
}

chroot_tor_policy_clear_prefs_file() {
  local distro="$1"
  local family="$2"
  local out_file

  out_file="$(chroot_tor_policy_pref_file_path "$distro" "$family")" || return 1
  rm -f -- "$out_file"
}

chroot_tor_policy_clear_state() {
  local distro="$1"
  chroot_tor_policy_clear_prefs_file "$distro" 4 >/dev/null 2>&1 || true
  chroot_tor_policy_clear_prefs_file "$distro" 6 >/dev/null 2>&1 || true
}
