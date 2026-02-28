chroot_service_is_ssh_like() {
  local name="${1:-}"
  local cmd_str="${2:-}"
  local probe_name probe_cmd
  probe_name="${name,,}"
  probe_cmd="${cmd_str,,}"
  [[ "$probe_name" == "ssh" || "$probe_name" == "sshd" ]] && return 0
  [[ "$probe_cmd" == *"sshd"* ]]
}

chroot_service_ssh_port_user() {
  local distro="$1"
  local cmd_str="${2:-}"
  local rootfs
  rootfs="$(chroot_distro_rootfs_dir "$distro")"
  [[ -d "$rootfs" ]] || return 1

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$rootfs" "$cmd_str" <<'PY'
import glob
import os
import shlex
import sys

rootfs, cmd_str = sys.argv[1:3]

def root_join(chroot_path):
    p = chroot_path if chroot_path.startswith("/") else "/" + chroot_path
    return os.path.join(rootfs, p.lstrip("/"))

def parse_cmd():
    cfg = "/etc/ssh/sshd_config"
    cli_port = None
    try:
        parts = shlex.split(cmd_str)
    except Exception:
        parts = cmd_str.split()
    i = 0
    while i < len(parts):
        token = parts[i]
        if token == "-f" and i + 1 < len(parts):
            cfg = parts[i + 1]
            i += 2
            continue
        if token.startswith("-f") and len(token) > 2:
            cfg = token[2:]
        if token == "-p" and i + 1 < len(parts):
            try:
                cli_port = int(parts[i + 1])
            except Exception:
                pass
            i += 2
            continue
        if token.startswith("-p") and len(token) > 2:
            try:
                cli_port = int(token[2:])
            except Exception:
                pass
        i += 1
    if not cfg.startswith("/"):
        cfg = "/" + cfg
    return cfg, cli_port

state = {"port": None, "permit_root": None, "password_auth": None}
visited = set()

def parse_cfg(chroot_path):
    if not chroot_path.startswith("/"):
        chroot_path = "/" + chroot_path
    host_path = os.path.realpath(root_join(chroot_path))
    if host_path in visited:
        return
    visited.add(host_path)

    try:
        with open(host_path, "r", encoding="utf-8") as fh:
            lines = fh.readlines()
    except Exception:
        return

    base_dir = os.path.dirname(chroot_path)
    for raw in lines:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "#" in line:
            line = line.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        key = parts[0].lower()
        vals = parts[1:]
        if key == "include" and vals:
            for pattern in vals:
                if not pattern.startswith("/"):
                    pattern = os.path.normpath(os.path.join(base_dir, pattern))
                host_pattern = root_join(pattern)
                for include_host_path in sorted(glob.glob(host_pattern)):
                    include_rel = "/" + os.path.relpath(include_host_path, rootfs).lstrip("./")
                    parse_cfg(include_rel)
            continue
        if key == "port" and vals:
            try:
                parsed = int(vals[0])
                if 1 <= parsed <= 65535:
                    state["port"] = parsed
            except Exception:
                pass
            continue
        if key == "permitrootlogin" and vals:
            state["permit_root"] = vals[0].strip().lower()
            continue
        if key == "passwordauthentication" and vals:
            state["password_auth"] = vals[0].strip().lower()

cfg_path, cli_port = parse_cmd()
parse_cfg(cfg_path)
port = cli_port if isinstance(cli_port, int) and 1 <= cli_port <= 65535 else (state["port"] or 22)

user = "<user>"
passwd_path = os.path.join(rootfs, "etc/passwd")
invalid_shells = {"/usr/bin/nologin", "/usr/sbin/nologin", "/sbin/nologin", "/bin/false"}
fallback_user = None
try:
    with open(passwd_path, "r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            parts = line.split(":")
            if len(parts) < 7:
                continue
            name = parts[0].strip()
            shell = parts[6].strip()
            try:
                uid = int(parts[2])
            except Exception:
                continue
            if uid >= 1000 and shell and shell not in invalid_shells:
                fallback_user = name
                break
except Exception:
    pass

permit_root = (state.get("permit_root") or "").lower()
password_auth = (state.get("password_auth") or "").lower()
root_password_allowed = (permit_root == "yes") and (password_auth != "no")
if root_password_allowed:
    user = "root"
elif fallback_user:
    user = fallback_user

print(f"{port}\t{user}")
PY
}

chroot_service_host_ipv4() {
  local ip="" dev="" key=""

  if command -v ip >/dev/null 2>&1; then
    ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i == "src") {print $(i+1); exit}}')"
    if chroot_service_ipv4_is_valid "$ip"; then
      printf '%s\n' "$ip"
      return 0
    fi

    dev="$(ip -4 route show default 2>/dev/null | awk '/^default/ {for (i=1; i<=NF; i++) if ($i == "dev") {print $(i+1); exit}}')"
    if [[ -n "$dev" ]]; then
      ip="$(ip -4 addr show dev "$dev" 2>/dev/null | awk '/inet /{sub(/\/.*/, "", $2); print $2; exit}')"
      if chroot_service_ipv4_is_valid "$ip"; then
        printf '%s\n' "$ip"
        return 0
      fi
    fi

    ip="$(ip -4 addr show scope global up 2>/dev/null | awk '/inet /{sub(/\/.*/, "", $2); print $2; exit}')"
    if chroot_service_ipv4_is_valid "$ip"; then
      printf '%s\n' "$ip"
      return 0
    fi
  fi

  if command -v getprop >/dev/null 2>&1; then
    for key in dhcp.wlan0.ipaddress dhcp.eth0.ipaddress dhcp.ap.br0.ipaddress dhcp.rmnet_data0.ipaddress wlan0.ipaddress; do
      ip="$(getprop "$key" 2>/dev/null | tr -d '\r\n' || true)"
      if chroot_service_ipv4_is_valid "$ip"; then
        printf '%s\n' "$ip"
        return 0
      fi
    done
  fi

  if command -v ifconfig >/dev/null 2>&1; then
    ip="$(ifconfig 2>/dev/null | awk '/inet / && $2 != "127.0.0.1" {print $2; exit}')"
    if [[ -z "$ip" ]]; then
      ip="$(ifconfig 2>/dev/null | awk -F'[: ]+' '/inet addr:/ {if ($4 != "127.0.0.1") {print $4; exit}}')"
    fi
    if chroot_service_ipv4_is_valid "$ip"; then
      printf '%s\n' "$ip"
      return 0
    fi
  fi

  if command -v hostname >/dev/null 2>&1; then
    ip="$(hostname -I 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i !~ /^127\./) {print $i; exit}}')"
    if chroot_service_ipv4_is_valid "$ip"; then
      printf '%s\n' "$ip"
      return 0
    fi
  fi

  ip=""
  printf '%s\n' "$ip"
}

chroot_service_ipv4_is_valid() {
  local ip="${1:-}"
  local a b c d
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS='.' read -r a b c d <<<"$ip"
  for octet in "$a" "$b" "$c" "$d"; do
    [[ "$octet" =~ ^[0-9]+$ ]] || return 1
    (( octet >= 0 && octet <= 255 )) || return 1
  done
  (( a != 0 )) || return 1
  (( a != 127 )) || return 1
  return 0
}

chroot_service_print_ssh_connect_help() {
  local distro="$1"
  local name="$2"
  local running="${3:-1}"
  local cmd_str="${4:-}"
  local info port user lan_ip

  [[ -n "$cmd_str" ]] || cmd_str="$(chroot_service_get_cmd "$distro" "$name" 2>/dev/null || true)"
  chroot_service_is_ssh_like "$name" "$cmd_str" || return 0

  info="$(chroot_service_ssh_port_user "$distro" "$cmd_str" 2>/dev/null || true)"
  port="22"
  user="<user>"
  if [[ -n "$info" ]]; then
    IFS=$'\t' read -r port user <<<"$info"
  fi
  [[ -n "$port" ]] || port="22"
  [[ -n "$user" ]] || user="<user>"
  lan_ip="$(chroot_service_host_ipv4)"

  chroot_info "SSH connect commands for '$name' on $distro:"
  chroot_info "Termux (same phone): ssh -p $port $user@127.0.0.1"
  if [[ -n "$lan_ip" ]]; then
    chroot_info "PC (same Wi-Fi): ssh -p $port $user@$lan_ip"
    chroot_info "Different Wi-Fi: after forwarding TCP $port -> $lan_ip:$port, use:"
    chroot_info "ssh -p $port $user@<public-ip-or-ddns>"
  else
    chroot_info "PC (same Wi-Fi): ssh -p $port $user@<phone-lan-ip>"
    chroot_info "Find phone LAN IP: ip -4 route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if(\$i==\"src\"){print \$(i+1); exit}}'"
    chroot_info "Different Wi-Fi: ssh -p $port $user@<public-ip-or-ddns> (requires tunnel/port-forward)"
  fi
  chroot_info "SSH has no separate password; it uses '$user' account password."
  if [[ "$user" == "<user>" ]]; then
    chroot_info "Set SSH login password: bash path/to/chroot exec $distro -- passwd <user>"
  else
    chroot_info "Change SSH login password: bash path/to/chroot exec $distro -- passwd $user"
  fi

  if (( running != 1 )); then
    chroot_warn "Service '$name' is stopped. Start it first: bash path/to/chroot service $distro start $name"
  fi
}

chroot_service_print_ssh_connect_help_for_distro() {
  local distro="$1"
  local active_only="${2:-0}"
  local svc cmd_str running
  while IFS= read -r svc; do
    [[ -n "$svc" ]] || continue
    cmd_str="$(chroot_service_get_cmd "$distro" "$svc" 2>/dev/null || true)"
    chroot_service_is_ssh_like "$svc" "$cmd_str" || continue
    running=0
    if chroot_service_get_pid "$distro" "$svc" >/dev/null 2>&1; then
      running=1
    fi
    if [[ "$active_only" == "1" && "$running" != "1" ]]; then
      continue
    fi
    chroot_service_print_ssh_connect_help "$distro" "$svc" "$running" "$cmd_str"
  done < <(chroot_service_list_defs "$distro")
}
