chroot_tor_public_exit_json() {
  local distro="$1"
  local daemon_pid="${2:-}"
  local bootstrap_complete="${3:-0}"
  local socks_port="${4:-$CHROOT_TOR_DEFAULT_SOCKS_PORT}"
  local out_file err_file url source err_text

  [[ -n "$daemon_pid" ]] || {
    printf '{\n  "available": false,\n  "reason": "daemon_stopped"\n}\n'
    return 0
  }

  [[ "$bootstrap_complete" == "1" ]] || {
    printf '{\n  "available": false,\n  "reason": "bootstrap_incomplete"\n}\n'
    return 0
  }

  [[ -n "${CHROOT_CURL_BIN:-}" ]] || {
    printf '{\n  "available": false,\n  "reason": "curl_missing"\n}\n'
    return 0
  }

  out_file="$CHROOT_TMP_DIR/tor-public-exit.$$.json"
  err_file="$CHROOT_TMP_DIR/tor-public-exit.$$.err"
  rm -f -- "$out_file" "$err_file"

  for url in "https://ipwho.is/" "https://ipapi.co/json/"; do
    if "$CHROOT_CURL_BIN" --fail --location --connect-timeout 8 --max-time 20 --silent --show-error --socks5-hostname "127.0.0.1:$socks_port" "$url" -o "$out_file" 2>"$err_file"; then
      case "$url" in
        *ipwho.is*) source="ipwho.is" ;;
        *ipapi.co*) source="ipapi.co" ;;
        *) source="$url" ;;
      esac
      break
    fi
  done

  err_text=""
  if [[ -f "$err_file" ]]; then
    err_text="$(head -n 1 "$err_file" | tr '\n' ' ' | tr -s '[:space:]' ' ' | sed 's/^ *//; s/ *$//')"
  fi

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "${source:-}" "$out_file" "$err_text" <<'PY'
import json
import os
import sys

source, payload_path, err_text = sys.argv[1:4]

def unavailable(reason, error_text=""):
    payload = {
        "available": False,
        "reason": reason,
    }
    if error_text:
        payload["error"] = error_text
    print(json.dumps(payload, indent=2, sort_keys=True))

if not source or not os.path.exists(payload_path):
    unavailable("lookup_failed", err_text)
    raise SystemExit(0)

try:
    with open(payload_path, "r", encoding="utf-8") as fh:
        raw = json.load(fh)
except Exception as exc:
    unavailable("lookup_failed", str(exc))
    raise SystemExit(0)

payload = {
    "available": True,
    "source": source,
    "ip": "",
    "country": "",
    "country_code": "",
    "region": "",
    "city": "",
    "latitude": None,
    "longitude": None,
    "asn": None,
    "org": "",
    "isp": "",
}

if source == "ipwho.is":
    if raw.get("success") is False:
        unavailable("lookup_failed", str(raw.get("message") or err_text or "ipwho.is returned success=false"))
        raise SystemExit(0)
    connection = raw.get("connection") if isinstance(raw.get("connection"), dict) else {}
    payload.update(
        {
            "ip": str(raw.get("ip") or ""),
            "country": str(raw.get("country") or ""),
            "country_code": str(raw.get("country_code") or ""),
            "region": str(raw.get("region") or ""),
            "city": str(raw.get("city") or ""),
            "latitude": raw.get("latitude"),
            "longitude": raw.get("longitude"),
            "asn": connection.get("asn"),
            "org": str(connection.get("org") or ""),
            "isp": str(connection.get("isp") or ""),
        }
    )
elif source == "ipapi.co":
    if raw.get("error"):
        unavailable("lookup_failed", str(raw.get("reason") or err_text or "ipapi.co returned error=true"))
        raise SystemExit(0)
    asn_value = raw.get("asn")
    if isinstance(asn_value, str) and asn_value.upper().startswith("AS"):
        try:
            asn_value = int(asn_value[2:])
        except Exception:
            pass
    payload.update(
        {
            "ip": str(raw.get("ip") or ""),
            "country": str(raw.get("country_name") or raw.get("country") or ""),
            "country_code": str(raw.get("country_code") or ""),
            "region": str(raw.get("region") or ""),
            "city": str(raw.get("city") or ""),
            "latitude": raw.get("latitude"),
            "longitude": raw.get("longitude"),
            "asn": asn_value,
            "org": str(raw.get("org") or ""),
            "isp": str(raw.get("org") or ""),
        }
    )
else:
    unavailable("lookup_failed", f"unsupported lookup source: {source}")
    raise SystemExit(0)

if not payload["ip"]:
    unavailable("lookup_failed", err_text or "lookup returned no ip")
    raise SystemExit(0)

print(json.dumps(payload, indent=2, sort_keys=True))
PY

  rm -f -- "$out_file" "$err_file"
}

chroot_tor_active_exit_json() {
  local distro="$1"
  local daemon_pid="${2:-}"
  local bootstrap_complete="${3:-0}"
  local public_exit_json="${4:-{}}"
  local cookie_file catalog_file

  [[ -n "$daemon_pid" ]] || {
    printf '{\n  "available": false,\n  "reason": "daemon_stopped"\n}\n'
    return 0
  }

  [[ "$bootstrap_complete" == "1" ]] || {
    printf '{\n  "available": false,\n  "reason": "bootstrap_incomplete"\n}\n'
    return 0
  }

  cookie_file="$(chroot_tor_rootfs_control_cookie_file "$distro")"
  [[ -f "$cookie_file" ]] || {
    printf '{\n  "available": false,\n  "reason": "control_cookie_missing"\n}\n'
    return 0
  }

  catalog_file="$CHROOT_TMP_DIR/tor-countries.$$.tsv"
  chroot_tor_country_catalog_tsv >"$catalog_file"
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$cookie_file" "$CHROOT_TOR_DEFAULT_CONTROL_PORT" "$public_exit_json" "$catalog_file" <<'PY'
import json
import socket
import sys

cookie_path, port_text, public_exit_text, catalog_path = sys.argv[1:5]
port = int(port_text)

country_names = {}
try:
    with open(catalog_path, "r", encoding="utf-8") as fh:
        for raw in fh:
            raw = raw.strip()
            if not raw or "\t" not in raw:
                continue
            code, name = raw.split("\t", 1)
            country_names[str(code).strip().lower()] = str(name).strip()
except Exception:
    country_names = {}

public_exit = {}
try:
    parsed_public_exit = json.loads(public_exit_text)
    if isinstance(parsed_public_exit, dict):
        public_exit = parsed_public_exit
except Exception:
    public_exit = {}
public_ip = str(public_exit.get("ip") or "").strip() if public_exit.get("available") else ""

def unavailable(reason, error_text=""):
    payload = {
        "available": False,
        "reason": reason,
    }
    if error_text:
        payload["error"] = error_text
    print(json.dumps(payload, indent=2, sort_keys=True))

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
    country_code = ""
    country = ""
    if not fingerprint:
        return relay_ip, nickname, country_code, country

    reply = send_cmd(sock, f"GETINFO ns/id/{fingerprint}")
    for raw in reply.splitlines():
        line = raw.strip()
        if line.startswith("r "):
            parts = line.split()
            if len(parts) >= 7:
                nickname = parts[1] or nickname
                relay_ip = parts[6]
            break

    if relay_ip:
        country_reply = send_cmd(sock, f"GETINFO ip-to-country/{relay_ip}")
        prefix = f"250-ip-to-country/{relay_ip}="
        for raw in country_reply.splitlines():
            line = raw.strip()
            if line.startswith(prefix):
                country_code = line.split("=", 1)[1].strip().lower()
                break
        country = country_names.get(country_code, "")

    return relay_ip, nickname, country_code, country

try:
    with open(cookie_path, "rb") as fh:
        cookie = fh.read().strip()
except Exception as exc:
    unavailable("control_cookie_missing", str(exc))
    raise SystemExit(0)

try:
    with socket.create_connection(("127.0.0.1", port), timeout=5.0) as sock:
        send_cmd(sock, f"AUTHENTICATE {cookie.hex()}")
        circuit_text = send_cmd(sock, "GETINFO circuit-status")
        chosen = None
        candidates = []
        for _cid, fingerprint, nickname, created_at in parse_exit_candidates(circuit_text):
            relay_ip, resolved_nick, country_code, country = relay_details_for_fingerprint(sock, fingerprint, nickname)
            row = {
                "fingerprint": f"${fingerprint}" if fingerprint else "",
                "nickname": str(resolved_nick or ""),
                "ip": str(relay_ip or ""),
                "country_code": str(country_code or ""),
                "country": str(country or ""),
                "matched_public_ip": bool(public_ip and relay_ip and relay_ip == public_ip),
                "created_at": str(created_at or ""),
            }
            candidates.append(row)
            if row["matched_public_ip"] and chosen is None:
                chosen = row
        if chosen is None and candidates:
            candidates.sort(key=lambda row: row.get("created_at") or "")
            chosen = candidates[-1]
        try:
            send_cmd(sock, "QUIT")
        except Exception:
            pass
except Exception as exc:
    unavailable("lookup_failed", str(exc))
    raise SystemExit(0)

if not chosen:
    unavailable("no_exit_circuit")
    raise SystemExit(0)

payload = {
    "available": True,
    "source": "tor-control",
    "fingerprint": str(chosen.get("fingerprint") or ""),
    "nickname": str(chosen.get("nickname") or ""),
    "ip": str(chosen.get("ip") or ""),
    "country_code": str(chosen.get("country_code") or ""),
    "country": str(chosen.get("country") or ""),
    "matched_public_ip": bool(chosen.get("matched_public_ip")),
    "selection": "matched-public-probe" if chosen.get("matched_public_ip") else "latest-built-circuit",
}
print(json.dumps(payload, indent=2, sort_keys=True))
PY
  rm -f -- "$catalog_file"
}

chroot_tor_status_json() {
  local distro="$1"
  local status_file targets_file enabled_saved identity_mode_saved daemon_user_saved uid_saved gid_saved termux_saved activated_at_saved last_error_saved saved_distro saved_family
  local daemon_pid daemon_start rules_active=0 bootstrap_complete=0 log_excerpt=""
  local nat_jump=0 filter_jump=0 filter6_jump=0 policy_v4_active=0 policy_v6_active=0
  local active_distro active_activated_at family tor_bin_host install_backend
  local bypass_count exit_count exit_strict saved_exit_codes saved_exit_resolved
  local apps_file apps_refresh_ok=0
  local saved_exit_strict public_exit_json active_exit_json

  chroot_tor_detect_backends 0

  status_file="$(chroot_tor_status_file "$distro")"
  targets_file="$(chroot_tor_targets_file "$distro")"
  apps_file="$(chroot_tor_apps_inventory_file "$distro")"
  family="$(chroot_tor_detect_distro_family "$distro")"
  tor_bin_host="$(chroot_tor_rootfs_tor_bin "$distro" || true)"
  install_backend="$(chroot_tor_detect_install_backend "$distro")"
  IFS=$'\t' read -r bypass_count exit_count exit_strict <<<"$(chroot_tor_config_summary_tsv "$distro")"
  IFS=$'\t' read -r saved_exit_strict saved_exit_codes saved_exit_resolved <<<"$(chroot_tor_exit_resolved_tsv "$distro")"

  IFS='|' read -r enabled_saved identity_mode_saved daemon_user_saved uid_saved gid_saved termux_saved activated_at_saved last_error_saved saved_distro saved_family <<<"$(chroot_tor_saved_state_tsv "$distro")"
  IFS='|' read -r active_distro active_activated_at <<<"$(chroot_tor_global_active_tsv)"

  daemon_pid="$(chroot_tor_current_pid "$distro" 2>/dev/null || true)"
  daemon_start=""
  if [[ -n "$daemon_pid" ]]; then
    daemon_start="$(chroot_tor_pid_starttime "$daemon_pid" 2>/dev/null || true)"
  fi
  if chroot_tor_rules_active "$distro"; then
    rules_active=1
  fi
  if chroot_tor_apps_refresh "$distro" 0 >/dev/null 2>&1; then
    apps_refresh_ok=1
  fi
  if [[ -n "$CHROOT_TOR_IPTABLES_BIN" ]] && chroot_tor_iptables_has_rule "$CHROOT_TOR_IPTABLES_BIN" -t nat -C OUTPUT -j "$CHROOT_TOR_CHAIN_NAT"; then
    nat_jump=1
  fi
  if [[ -n "$CHROOT_TOR_IPTABLES_BIN" ]] && chroot_tor_iptables_has_rule "$CHROOT_TOR_IPTABLES_BIN" -t filter -C OUTPUT -j "$CHROOT_TOR_CHAIN_FILTER"; then
    filter_jump=1
  fi
  if [[ -n "$CHROOT_TOR_IP6TABLES_BIN" ]] && chroot_tor_iptables_has_rule "$CHROOT_TOR_IP6TABLES_BIN" -t filter -C OUTPUT -j "$CHROOT_TOR_CHAIN_FILTER6"; then
    filter6_jump=1
  fi
  if chroot_tor_policy_rules_active_v4 "$distro"; then
    policy_v4_active=1
  fi
  if chroot_tor_policy_rules_active_v6 "$distro"; then
    policy_v6_active=1
  fi
  if [[ -n "$daemon_pid" ]] && chroot_tor_log_bootstrap_complete "$distro"; then
    bootstrap_complete=1
  fi
  log_excerpt="$(chroot_tor_log_excerpt "$distro" 2>/dev/null || true)"
  public_exit_json="$(chroot_tor_public_exit_json "$distro" "$daemon_pid" "$bootstrap_complete" "$CHROOT_TOR_DEFAULT_SOCKS_PORT")"
  active_exit_json="$(chroot_tor_active_exit_json "$distro" "$daemon_pid" "$bootstrap_complete" "$public_exit_json")"

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$status_file" "$targets_file" "$apps_file" "$distro" "$enabled_saved" "$identity_mode_saved" "$daemon_user_saved" "$uid_saved" "$gid_saved" "$termux_saved" "$activated_at_saved" "$last_error_saved" "$daemon_pid" "$daemon_start" "$rules_active" "$bootstrap_complete" "$nat_jump" "$filter_jump" "$filter6_jump" "$policy_v4_active" "$policy_v6_active" "$log_excerpt" "$tor_bin_host" "$install_backend" "${CHROOT_TOR_IPTABLES_BIN:-}" "${CHROOT_TOR_IP6TABLES_BIN:-}" "${CHROOT_TOR_IP_BIN:-}" "${CHROOT_TOR_UID_SOURCE:-}" "$(chroot_tor_state_dir "$distro")" "$(chroot_tor_rootfs_torrc_file "$distro")" "$(chroot_tor_rootfs_runtime_log_file "$distro")" "$(chroot_tor_rootfs_pid_file "$distro")" "$(chroot_tor_targets_file "$distro")" "$CHROOT_TOR_DEFAULT_SOCKS_PORT" "$CHROOT_TOR_DEFAULT_TRANS_PORT" "$CHROOT_TOR_DEFAULT_DNS_PORT" "$active_distro" "$active_activated_at" "$family" "$bypass_count" "$exit_count" "$exit_strict" "$saved_exit_codes" "$saved_exit_resolved" "$apps_refresh_ok" "$public_exit_json" "$active_exit_json" <<'PY'
import json
import os
import sys

(
    status_file,
    targets_file,
    apps_file,
    selected_distro,
    enabled_saved,
    identity_mode_saved,
    daemon_user_saved,
    uid_saved,
    gid_saved,
    termux_saved,
    activated_at_saved,
    last_error_saved,
    daemon_pid_text,
    daemon_start_text,
    rules_active_text,
    bootstrap_complete_text,
    nat_jump_text,
    filter_jump_text,
    filter6_jump_text,
    policy_v4_active_text,
    policy_v6_active_text,
    log_excerpt,
    tor_bin_host,
    install_backend,
    iptables_bin,
    ip6tables_bin,
    ip_bin,
    uid_source_detected,
    state_dir,
    torrc_path,
    log_path,
    pid_path,
    targets_path,
    socks_port_text,
    trans_port_text,
    dns_port_text,
    active_distro,
    active_activated_at,
    family,
    bypass_count_text,
    exit_count_text,
    exit_strict_text,
    saved_exit_codes,
    saved_exit_resolved,
    apps_refresh_ok_text,
    public_exit_text,
    active_exit_text,
) = sys.argv[1:49]

def parse_json_file(path, default):
    if not path or not os.path.exists(path):
        return default
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        if isinstance(default, dict) and not isinstance(data, dict):
            return default
        return data
    except Exception:
        return default

def parse_int(value):
    text = str(value).strip()
    if not text:
        return None
    try:
        return int(text)
    except Exception:
        return None

status_doc = parse_json_file(status_file, {})
targets_doc = parse_json_file(targets_file, {})
apps_doc = parse_json_file(apps_file, {})
public_exit = {}
try:
    parsed_public_exit = json.loads(public_exit_text)
    if isinstance(parsed_public_exit, dict):
        public_exit = parsed_public_exit
except Exception:
    public_exit = {}
active_exit = {}
try:
    parsed_active_exit = json.loads(active_exit_text)
    if isinstance(parsed_active_exit, dict):
        active_exit = parsed_active_exit
except Exception:
    active_exit = {}
freeze_doc = parse_json_file(os.path.join(state_dir, "freeze.json"), {"active": False})
if not isinstance(freeze_doc, dict):
    freeze_doc = {"active": False}
freeze_doc.setdefault("active", False)

daemon_pid = parse_int(daemon_pid_text)
daemon_start = parse_int(daemon_start_text)
daemon_state = "running" if daemon_pid is not None else "stopped"
rules_active = rules_active_text == "1"
bootstrap_complete = bootstrap_complete_text == "1"
nat_jump = nat_jump_text == "1"
filter_jump = filter_jump_text == "1"
filter6_jump = filter6_jump_text == "1"
policy_v4_active = policy_v4_active_text == "1"
policy_v6_active = policy_v6_active_text == "1"
apps_refresh_ok = apps_refresh_ok_text == "1"
selected_active = bool(active_distro) and active_distro == selected_distro
enabled = selected_active and enabled_saved == "1"

warnings = []
for value in status_doc.get("warnings", []):
    text = str(value).strip()
    if text and text not in warnings:
        warnings.append(text)

if not tor_bin_host:
    if install_backend:
        warnings.append("Tor binary is not installed inside the selected distro yet.")
    else:
        warnings.append("Tor binary is not installed and automatic install is unavailable for the selected distro.")
if selected_active and daemon_pid is None:
    warnings.append("Selected distro is active for Tor but daemon is not running.")
if selected_active and not rules_active:
    warnings.append("Selected distro is active for Tor but host routing rules are not active.")
if selected_active and daemon_pid is not None and not bootstrap_complete:
    warnings.append("Tor daemon is running but bootstrap is not complete.")
if (not selected_active) and daemon_pid is not None:
    warnings.append("Selected distro is not the active Tor backend but still has a Tor daemon running.")
if active_distro and active_distro != selected_distro:
    warnings.append(f"Global Tor traffic is currently routed through distro '{active_distro}'.")
if str(last_error_saved or status_doc.get("last_error", "") or "").strip():
    warnings.append(str(last_error_saved or status_doc.get("last_error", "")).strip())
if enabled:
    if not apps_refresh_ok:
        warnings.append("Current Android app inventory could not be refreshed; target UID staleness is unknown.")
    else:
        current_digest = str(apps_doc.get("packages_digest", "") or "").strip()
        target_digest = str(targets_doc.get("source_packages_digest", "") or "").strip()
        current_count = int(apps_doc.get("package_count", 0) or 0)
        target_count = int(targets_doc.get("source_package_count", 0) or 0)
        if (current_digest and target_digest and current_digest != target_digest) or (target_digest == "" and target_count and current_count != target_count):
            warnings.append("Android app inventory changed since Tor was enabled; restart Tor to refresh targeted UIDs.")
    warnings.append("Android DNS may still depend on system resolver paths outside targeted app UIDs; validate on-device if DNS anonymity matters.")

last_error = str(last_error_saved or status_doc.get("last_error", "") or "").strip()
saved_routing = status_doc.get("routing", {}) if isinstance(status_doc.get("routing"), dict) else {}
lan_bypass = bool(saved_routing.get("lan_bypass", True))

healthy = False
if selected_active:
    healthy = bool(
        tor_bin_host
        and iptables_bin
        and (ip6tables_bin or policy_v6_active)
        and daemon_pid is not None
        and rules_active
        and bootstrap_complete
    )
else:
    healthy = bool(
        tor_bin_host
        and daemon_pid is None
        and not rules_active
        and not last_error
    )
if last_error:
    healthy = False

payload = {
    "schema_version": int(status_doc.get("schema_version", 1) or 1),
    "distro": selected_distro,
    "active_distro": active_distro,
    "enabled": enabled,
    "run_mode": str(status_doc.get("run_mode", "") or ""),
    "healthy": healthy,
    "mode": str(status_doc.get("mode", "system-wide") or "system-wide"),
    "activated_at": active_activated_at if selected_active else "",
    "warnings": warnings,
    "backend": {
        "distro_family": family,
        "tor_binary": tor_bin_host,
        "install_backend": install_backend,
        "iptables_v4": iptables_bin,
        "ip6tables": ip6tables_bin,
        "ip": ip_bin,
        "uid_source": str(targets_doc.get("uid_source", "") or uid_source_detected or ""),
        "owner_match": bool(iptables_bin),
        "routing_backend_v4": "iptables-filter" if filter_jump else ("policy-routing" if policy_v4_active else "none"),
        "routing_backend_v6": "iptables-filter" if filter6_jump else ("policy-routing" if policy_v6_active else "none"),
    },
    "daemon": {
        "state": daemon_state,
        "identity_mode": str(identity_mode_saved or status_doc.get("daemon", {}).get("identity_mode", "") or ""),
        "user": str(daemon_user_saved or status_doc.get("daemon", {}).get("user", "") or ""),
        "uid": parse_int(uid_saved) if parse_int(uid_saved) is not None else status_doc.get("daemon", {}).get("uid"),
        "gid": parse_int(gid_saved) if parse_int(gid_saved) is not None else status_doc.get("daemon", {}).get("gid"),
        "pid": daemon_pid,
        "pid_starttime": daemon_start,
        "socks_port": int(socks_port_text),
        "trans_port": int(trans_port_text),
        "dns_port": int(dns_port_text),
    },
    "routing": {
        "app_uid_count": int(targets_doc.get("app_uid_count", 0) or 0),
        "target_uid_count": int(targets_doc.get("target_uid_count", 0) or 0),
        "uid_range_count": int(targets_doc.get("uid_range_count", 0) or 0),
        "termux_uid_included": termux_saved == "1" or bool(status_doc.get("routing", {}).get("termux_uid_included")),
        "root_uid_included": False,
        "udp_policy": "blocked",
        "ipv6_policy": "blocked",
        "lan_bypass": lan_bypass,
    },
    "saved_config": {
        "bypass_package_count": int(bypass_count_text or 0),
        "exit_country_count": int(exit_count_text or 0),
        "exit_strict": exit_strict_text == "1",
        "exit_countries": [x for x in str(saved_exit_codes or "").split(",") if x],
        "exit_resolved": str(saved_exit_resolved or ""),
    },
    "runtime": {
        "rules_active": rules_active,
        "nat_output_jump": nat_jump,
        "filter_output_jump": filter_jump,
        "filter6_output_jump": filter6_jump,
        "policy_v4_active": policy_v4_active,
        "policy_v6_active": policy_v6_active,
        "bootstrap_complete": bootstrap_complete,
        "app_inventory_refresh_ok": apps_refresh_ok,
        "uid_targets_stale": bool(enabled and apps_refresh_ok and ((str(apps_doc.get("packages_digest", "") or "").strip() and str(targets_doc.get("source_packages_digest", "") or "").strip() and str(apps_doc.get("packages_digest", "") or "").strip() != str(targets_doc.get("source_packages_digest", "") or "").strip()) or (not str(targets_doc.get("source_packages_digest", "") or "").strip() and int(targets_doc.get("source_package_count", 0) or 0) and int(apps_doc.get("package_count", 0) or 0) != int(targets_doc.get("source_package_count", 0) or 0)))),
        "log_excerpt": str(log_excerpt or ""),
    },
    "active_exit": active_exit,
    "public_exit": public_exit,
    "freeze": freeze_doc,
    "paths": {
        "state_dir": state_dir,
        "torrc": torrc_path,
        "log": log_path,
        "pid_file": pid_path,
        "targets": targets_path,
    },
    "last_error": last_error,
}

print(json.dumps(payload, indent=2, sort_keys=True))
PY
}

chroot_tor_status_human() {
  local distro="$1"
  local json_payload
  json_payload="$(chroot_tor_status_json "$distro")"
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$json_payload" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
daemon = data.get("daemon", {})
routing = data.get("routing", {})
backend = data.get("backend", {})
runtime = data.get("runtime", {})
saved = data.get("saved_config", {})
active_exit = data.get("active_exit", {}) if isinstance(data.get("active_exit"), dict) else {}
public_exit = data.get("public_exit", {}) if isinstance(data.get("public_exit"), dict) else {}
freeze = data.get("freeze", {}) if isinstance(data.get("freeze"), dict) else {}
run_mode = str(data.get("run_mode", "") or "").strip().lower()
warnings = data.get("warnings", [])

mode_text = "enabled" if data.get("enabled") else "disabled"
health_text = "healthy" if data.get("healthy") else "degraded"
daemon_state = daemon.get("state", "stopped")
pid = daemon.get("pid")
if pid:
    pid_text = f"running pid={pid} user={daemon.get('user') or '?'} uid={daemon.get('uid')}"
else:
    pid_text = daemon_state
warning_text = "none" if not warnings else " | ".join(str(x) for x in warnings[:3])

print(f"{'Distro':<15} {data.get('distro', '') or '<none>'}")
print(f"{'Active Distro':<15} {data.get('active_distro', '') or 'none'}")
print(f"{'Tor Mode':<15} {mode_text}")
print(f"{'Health':<15} {health_text}")
print(f"{'Daemon':<15} {pid_text}")
print(
    f"{'Routing':<15} "
    f"app-uids={routing.get('app_uid_count', 0)} "
    f"targets={routing.get('target_uid_count', 0)} "
    f"ranges={routing.get('uid_range_count', 0)} "
    f"termux={'yes' if routing.get('termux_uid_included') else 'no'} "
    f"root=no"
)
print(
    f"{'Traffic Policy':<15} "
    f"tcp=tor dns=tor udp={routing.get('udp_policy', 'blocked')} "
    f"ipv6={routing.get('ipv6_policy', 'blocked')} "
    f"lan-bypass={'yes' if routing.get('lan_bypass') else 'no'}"
)
print(
    f"{'Tor Ports':<15} "
    f"socks={daemon.get('socks_port')} "
    f"trans={daemon.get('trans_port')} "
    f"dns={daemon.get('dns_port')}"
)
print(
    f"{'Backend':<15} "
    f"family={backend.get('distro_family') or 'unknown'} "
    f"rules={'on' if runtime.get('rules_active') else 'off'} "
    f"bootstrap={'yes' if runtime.get('bootstrap_complete') else 'no'}"
)
print(
    f"{'Route Mode':<15} "
    f"v4={backend.get('routing_backend_v4') or 'none'} "
    f"v6={backend.get('routing_backend_v6') or 'none'}"
)
print(
    f"{'Saved Config':<15} "
    f"bypass={saved.get('bypass_package_count', 0)} "
    f"exit={saved.get('exit_country_count', 0)} "
    f"strict={'on' if saved.get('exit_strict') else 'off'}"
)
if data.get("enabled"):
    if run_mode == "configured":
        print(f"{'Config Apply':<15} saved apps + exit active")
    elif run_mode == "configured-apps":
        print(f"{'Config Apply':<15} saved apps active; exit ignored")
    elif run_mode == "configured-exit":
        print(f"{'Config Apply':<15} saved exit active; apps ignored")
    elif run_mode == "default":
        print(f"{'Config Apply':<15} plain mode (saved prefs not applied)")
    else:
        print(f"{'Config Apply':<15} active mode unknown")
    print(f"{'Freeze':<15} {'active' if freeze.get('active') else 'off'}")
if saved.get("exit_resolved"):
    print(f"{'Saved Exit':<15} {saved.get('exit_resolved')}")
if active_exit.get("available"):
    relay_name = active_exit.get("nickname") or active_exit.get("fingerprint") or ""
    relay_geo = " ".join(
        part
        for part in [
            str(active_exit.get("country_code") or "").upper(),
            active_exit.get("country") or "",
        ]
        if part
    )
    relay_line = " | ".join(part for part in [active_exit.get("ip") or "", relay_geo, relay_name] if part)
    if relay_line:
        print(f"{'Tor Exit':<15} {relay_line}")
if freeze.get("active"):
    frozen_exit = freeze.get("exit_fingerprint") or ""
    if freeze.get("exit_nickname"):
        frozen_exit = f"{frozen_exit} {freeze.get('exit_nickname')}".strip()
    if frozen_exit:
        print(f"{'Pinned Relay':<15} {frozen_exit}")
    if freeze.get("exit_ip"):
        print(f"{'Relay IP':<15} {freeze.get('exit_ip')}")
    if freeze.get("public_ip"):
        print(f"{'Frozen Public':<15} {freeze.get('public_ip')}")
    frozen_geo = " | ".join(
        part
        for part in [
            freeze.get("country_code") or freeze.get("country"),
            freeze.get("region"),
            freeze.get("city"),
        ]
        if part
    )
    if frozen_geo:
        print(f"{'Frozen Geo':<15} {frozen_geo}")
if public_exit.get("available"):
    print(f"{'Probe IP':<15} {public_exit.get('ip')}")
    location = " | ".join(
        part
        for part in [
            public_exit.get("country_code") or public_exit.get("country"),
            public_exit.get("region"),
            public_exit.get("city"),
        ]
        if part
    )
    if location:
        print(f"{'Probe Geo':<15} {location}")
    network = public_exit.get("org") or public_exit.get("isp") or ""
    asn = public_exit.get("asn")
    if network or asn not in (None, ""):
        if network and asn not in (None, ""):
            print(f"{'Probe Net':<15} {network} (AS{asn})")
        elif network:
            print(f"{'Probe Net':<15} {network}")
        else:
            print(f"{'Probe Net':<15} AS{asn}")
    if public_exit.get("source"):
        print(f"{'Probe Source':<15} {public_exit.get('source')}")
if active_exit.get("available") and public_exit.get("available"):
    active_ip = str(active_exit.get("ip") or "").strip()
    public_ip = str(public_exit.get("ip") or "").strip()
    active_country = str(active_exit.get("country_code") or "").strip().upper()
    public_country = str(public_exit.get("country_code") or "").strip().upper()
    if active_ip and public_ip and not active_exit.get("matched_public_ip"):
        print(f"{'Probe Compare':<15} live SOCKS probe hit a different exit than Tor control's current exit candidate")
    elif active_country and public_country and active_country != public_country:
        print(f"{'Geo Note':<15} Tor control says {active_country}; probe GeoIP says {public_country}")
elif public_exit.get("error"):
    print(f"{'Probe Exit':<15} unavailable ({public_exit.get('error')})")
elif public_exit.get("reason") and daemon_state == "running":
    print(f"{'Probe Exit':<15} unavailable ({public_exit.get('reason')})")
print(f"{'Warnings':<15} {warning_text}")
if backend.get("tor_binary"):
    print(f"{'Tor Binary':<15} {backend.get('tor_binary')}")
if runtime.get("log_excerpt"):
    print(f"{'Last Log':<15} {runtime.get('log_excerpt')}")
PY
}

chroot_tor_doctor_human() {
  local distro="$1"
  local json_payload
  json_payload="$(chroot_tor_doctor_json "$distro")"
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$json_payload" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
backend = data.get("backend", {})
identity = data.get("daemon_identity", {})
probe = data.get("routing_probe", {})
rotation = data.get("rotation", {})

print(f"{'Distro':<18} {data.get('distro', '')}")
print(f"{'Family':<18} {backend.get('distro_family', '') or 'unknown'}")
print(f"{'Tor Binary':<18} {backend.get('tor_binary', '') or 'missing'}")
print(f"{'Install Backend':<18} {backend.get('install_backend', '') or 'unavailable'}")
print(f"{'iptables v4':<18} {backend.get('iptables_v4', '') or 'missing'}")
print(f"{'ip6tables':<18} {backend.get('ip6tables', '') or 'missing'}")
print(
    f"{'Daemon User':<18} "
    f"{identity.get('user') or 'unknown'} "
    f"(mode={identity.get('mode') or 'unknown'} uid={identity.get('uid')} gid={identity.get('gid')})"
)
if identity.get("warning"):
    print(f"{'Identity Warn':<18} {identity.get('warning')}")
print(f"{'Rotation Min':<18} {rotation.get('tor_rotation_min')}")
print(f"{'Bootstrap Sec':<18} {rotation.get('bootstrap_timeout_sec')}")
print(f"{'NAT Probe':<18} {'ok' if probe.get('nat_ok') else 'fail'}")
if probe.get("nat_error"):
    print(f"{'NAT Error':<18} {probe.get('nat_error')}")
print(f"{'Filter Probe':<18} {'ok' if probe.get('filter_ok') else 'fail'}")
if probe.get("filter_error"):
    print(f"{'Filter Error':<18} {probe.get('filter_error')}")
print(f"{'IPv6 Probe':<18} {'ok' if probe.get('filter6_ok') else 'fail'}")
if probe.get("filter6_error"):
    print(f"{'IPv6 Error':<18} {probe.get('filter6_error')}")
print(f"{'Fallback v4':<18} {probe.get('effective_v4') or 'unsupported'}")
if probe.get("policy_v4_error"):
    print(f"{'Fallback v4 Err':<18} {probe.get('policy_v4_error')}")
print(f"{'Fallback v6':<18} {probe.get('effective_v6') or 'unsupported'}")
if probe.get("policy_v6_error"):
    print(f"{'Fallback v6 Err':<18} {probe.get('policy_v6_error')}")
PY
}

chroot_tor_logs() {
  local distro="$1"
  local tail_lines="${2:-120}"
  local log_file

  [[ "$tail_lines" =~ ^[0-9]+$ ]] || chroot_die "tor log tail must be a positive integer"
  (( tail_lines > 0 )) || chroot_die "tor log tail must be greater than zero"

  log_file="$(chroot_tor_rootfs_runtime_log_file "$distro")"
  [[ -f "$log_file" ]] || chroot_die "no tor log found for $distro"
  chroot_run_root tail -n "$tail_lines" "$log_file"
}
