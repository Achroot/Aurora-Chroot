chroot_service_is_pcbridge() {
  local name="${1:-}"
  [[ "${name,,}" == "pcbridge" ]]
}

chroot_service_pcbridge_state_file() {
  local _distro="$1"
  printf '/etc/aurora-pcbridge/state.json'
}

chroot_service_pcbridge_token_file() {
  local _distro="$1"
  printf '/etc/aurora-pcbridge/token'
}

chroot_service_pcbridge_token_event_file() {
  local _distro="$1"
  printf '/etc/aurora-pcbridge/token_event'
}

chroot_service_pcbridge_token_control_file() {
  local _distro="$1"
  printf '/etc/aurora-pcbridge/token_control'
}

chroot_service_pcbridge_raw_read() {
  local distro="$1"
  local target_path="$2"
  local rootfs raw host_path

  rootfs="$(chroot_distro_rootfs_dir "$distro")"
  [[ -d "$rootfs" ]] || return 1

  raw="$(chroot_run_chroot_cmd "$rootfs" /bin/sh -c "cat '$target_path'" 2>/dev/null || true)"
  if [[ -z "$raw" ]]; then
    host_path="$rootfs$target_path"
    raw="$(chroot_run_root /bin/sh -c "cat '$host_path'" 2>/dev/null || true)"
  fi

  [[ -n "$raw" ]] || return 1
  printf '%s\n' "$raw"
}

chroot_service_pcbridge_default_http_port() {
  local distro="$1"
  local cmd_str parsed port
  cmd_str="$(chroot_service_get_cmd "$distro" "pcbridge" 2>/dev/null || true)"
  port="47077"
  if [[ "$cmd_str" =~ AURORA_PCBRIDGE_HTTP_PORT=([0-9]{1,5}) ]]; then
    parsed="${BASH_REMATCH[1]}"
    if (( parsed >= 1 && parsed <= 65535 )); then
      port="$parsed"
    fi
  fi
  printf '%s\n' "$port"
}

chroot_service_pcbridge_token_value() {
  local distro="$1"
  local token_file raw token

  token_file="$(chroot_service_pcbridge_token_file "$distro")"
  raw="$(chroot_service_pcbridge_raw_read "$distro" "$token_file" 2>/dev/null || true)"
  [[ -n "$raw" ]] || return 1

  token="$(printf '%s\n' "$raw" | tr -d '\r' | awk 'NF {print $1; exit}')"
  [[ "$token" =~ ^[A-Za-z0-9._-]{8,128}$ ]] || return 1
  printf '%s\n' "$token"
}

chroot_service_pcbridge_state_fields() {
  local distro="$1"
  local state_file raw
  state_file="$(chroot_service_pcbridge_state_file "$distro")"

  raw="$(chroot_service_pcbridge_raw_read "$distro" "$state_file" 2>/dev/null || true)"
  [[ -n "$raw" ]] || return 1

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$raw" <<'PY'
import json
import sys

try:
    data = json.loads(sys.argv[1])
except Exception:
    raise SystemExit(1)

if not isinstance(data, dict):
    raise SystemExit(1)

token = str(data.get("token", "")).strip()
http_port = int(data.get("http_port", 0) or 0)
ssh_port = int(data.get("ssh_port", 0) or 0)
ttl = int(data.get("token_ttl_sec", 0) or 0)

if not token or http_port <= 0:
    raise SystemExit(1)

print(f"{token}\t{http_port}\t{ssh_port}\t{ttl}")
PY
}

chroot_service_pcbridge_bootstrap_command() {
  chroot_service_pcbridge_command_for_path "$1" "bootstrap.sh"
}

chroot_service_pcbridge_cleanup_command() {
  chroot_service_pcbridge_command_for_path "$1" "cleanup.sh"
}

chroot_service_pcbridge_command_for_path() {
  local distro="$1"
  local endpoint="$2"
  local token="" http_port="" ssh_port="" ttl=""
  local retries=24
  local retry_delay=0.25
  local i

  for (( i=0; i<retries; i++ )); do
    if IFS=$'\t' read -r token http_port ssh_port ttl < <(chroot_service_pcbridge_state_fields "$distro" || true); then
      if [[ -n "$token" && -n "$http_port" ]]; then
        break
      fi
    fi
    token=""
    http_port=""
    ssh_port=""
    ttl=""
    sleep "$retry_delay"
  done

  if [[ -z "$token" ]]; then
    token="$(chroot_service_pcbridge_token_value "$distro" || true)"
  fi
  if [[ -n "$token" && -z "$http_port" ]]; then
    http_port="$(chroot_service_pcbridge_default_http_port "$distro" || true)"
  fi

  [[ -n "$token" && -n "$http_port" ]] || return 1
  [[ -n "$endpoint" ]] || return 1

  local lan_ip
  lan_ip="$(chroot_service_host_ipv4)"
  if ! chroot_service_ipv4_is_valid "$lan_ip"; then
    lan_ip="<phone-lan-ip>"
  fi

  printf 'bash -lc "$(curl -fsSL '\''http://%s:%s/%s?token=%s'\'')"\n' "$lan_ip" "$http_port" "$endpoint" "$token"
}

chroot_service_pcbridge_token_event_value() {
  local distro="$1"
  local event_file raw event

  event_file="$(chroot_service_pcbridge_token_event_file "$distro")"
  raw="$(chroot_service_pcbridge_raw_read "$distro" "$event_file" 2>/dev/null || true)"
  [[ -n "$raw" ]] || return 1

  event="$(printf '%s\n' "$raw" | tr -d '\r' | awk 'NF {print $1; exit}')"
  case "$event" in
    ready|bootstrap_command_used|cleanup_command_used|paired|expired|manually_expired)
      printf '%s\n' "$event"
      ;;
    *)
      return 1
      ;;
  esac
}

chroot_service_pcbridge_token_seconds_left() {
  local distro="$1"
  local state_file raw
  state_file="$(chroot_service_pcbridge_state_file "$distro")"
  raw="$(chroot_service_pcbridge_raw_read "$distro" "$state_file" 2>/dev/null || true)"
  [[ -n "$raw" ]] || return 1

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$raw" <<'PY'
import datetime
import json
import time
import sys

try:
    data = json.loads(sys.argv[1])
except Exception:
    raise SystemExit(1)

if not isinstance(data, dict):
    raise SystemExit(1)

ttl = int(data.get("token_ttl_sec", 0) or 0)
started_at = str(data.get("started_at", "")).strip()
if ttl <= 0 or not started_at:
    raise SystemExit(1)

try:
    started = datetime.datetime.strptime(started_at, "%Y-%m-%dT%H:%M:%SZ")
    started = started.replace(tzinfo=datetime.timezone.utc)
    started_epoch = int(started.timestamp())
except Exception:
    raise SystemExit(1)

left = ttl - int(time.time() - started_epoch)
if left < 0:
    left = 0
print(left)
PY
}

chroot_service_pcbridge_expire_token_now() {
  local distro="$1"
  local control_file rootfs
  control_file="$(chroot_service_pcbridge_token_control_file "$distro")"
  rootfs="$(chroot_distro_rootfs_dir "$distro")"
  [[ -d "$rootfs" ]] || return 1

  chroot_run_chroot_cmd "$rootfs" /bin/sh -c "umask 077; printf '%s\\n' 'expire' > '$control_file'"
}

chroot_service_pcbridge_wait_for_pairing_task() {
  local distro="$1"
  local action="${2:-bootstrap}"
  local action_event=""
  local event=""
  local input=""
  local seconds_left=""
  local tick=0

  case "$action" in
    bootstrap)
      action_event="bootstrap_command_used"
      ;;
    cleanup)
      action_event="cleanup_command_used"
      ;;
  esac

  seconds_left="$(chroot_service_pcbridge_token_seconds_left "$distro" 2>/dev/null || true)"
  if [[ ! -t 0 || ! -t 1 ]]; then
    if [[ "$seconds_left" =~ ^[0-9]+$ ]]; then
      chroot_info "pcbridge pairing token active (auto-expires in ~${seconds_left}s)."
    else
      chroot_info "pcbridge pairing token active."
    fi
    return 0
  fi

  chroot_info "Waiting for pcbridge token event."
  if [[ "$seconds_left" =~ ^[0-9]+$ ]]; then
    chroot_info "Type 'e' then Enter to expire token now and end task (token automatically expires in ~${seconds_left}s)."
  else
    chroot_info "Type 'e' then Enter to expire token now and end task (token auto-expires by TTL)."
  fi

  while true; do
    event="$(chroot_service_pcbridge_token_event_value "$distro" 2>/dev/null || true)"
    case "$event" in
      "$action_event")
        if [[ "$action" == "cleanup" ]]; then
          chroot_info "Detected cleanup command use from a PC. Ending task."
        else
          chroot_info "Detected setup command use from a PC. Ending task."
        fi
        return 0
        ;;
      paired)
        chroot_info "Detected successful PC key pairing. Ending task."
        return 0
        ;;
      expired)
        chroot_info "Token expired automatically. Ending task."
        return 0
        ;;
      manually_expired)
        chroot_info "Token was expired manually. Ending task."
        return 0
        ;;
    esac

    if ! chroot_service_get_pid "$distro" "pcbridge" >/dev/null 2>&1; then
      chroot_warn "pcbridge is no longer running; ending task."
      return 0
    fi

    seconds_left="$(chroot_service_pcbridge_token_seconds_left "$distro" 2>/dev/null || true)"
    if [[ "$seconds_left" =~ ^[0-9]+$ ]] && (( seconds_left <= 0 )); then
      chroot_info "Token expired automatically. Ending task."
      return 0
    fi

    if (( tick % 15 == 0 )); then
      if [[ "$seconds_left" =~ ^[0-9]+$ ]]; then
        chroot_info "Waiting... type 'e' + Enter to expire token now (auto-expires in ~${seconds_left}s)."
      else
        chroot_info "Waiting... type 'e' + Enter to expire token now."
      fi
    fi
    tick=$((tick + 1))

    if read -r -t 1 input; then
      case "${input,,}" in
        e|expire|x)
          if chroot_service_pcbridge_expire_token_now "$distro" >/dev/null 2>&1; then
            chroot_info "Expire request sent. Ending task now."
          else
            chroot_warn "Failed to send expire request. Stop/restart pcbridge to rotate token."
          fi
          return 0
          ;;
        '')
          ;;
        *)
          chroot_info "Unknown input: '$input' (use 'e' to expire token now, or wait)."
          ;;
      esac
    fi
  done
}

chroot_service_pcbridge_has_paired_keys() {
  local distro="$1"
  local keys_path raw
  keys_path="/etc/aurora-pcbridge/authorized_keys"

  raw="$(chroot_service_pcbridge_raw_read "$distro" "$keys_path" 2>/dev/null || true)"
  [[ -n "$raw" ]] || return 1

  printf '%s\n' "$raw" | awk '
    /^[[:space:]]*$/ {next}
    /^[[:space:]]*ssh-(ed25519|rsa)[[:space:]]+[A-Za-z0-9+\/=]+([[:space:]].*)?$/ {ok=1; exit}
    END {exit ok ? 0 : 1}
  '
}

chroot_service_pcbridge_supervisor_pid() {
  local distro="$1"
  local rootfs out pid
  rootfs="$(chroot_distro_rootfs_dir "$distro")"
  [[ -d "$rootfs" ]] || return 1

  out="$(
    chroot_run_chroot_cmd "$rootfs" /bin/sh -s <<'SH'
set -eu

is_uint() {
  case "${1:-}" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

read_cmdline() {
  tr '\0' ' ' <"/proc/$1/cmdline" 2>/dev/null || true
}

is_pcbridge_cmdline() {
  case "${1:-}" in
    *aurora-pcbridge-start*) return 0 ;;
    *) return 1 ;;
  esac
}

pid_file="/run/aurora-pcbridge/sshd.pid"
[ -r "$pid_file" ] || exit 1

sshd_pid="$(awk 'NF {print $1; exit}' "$pid_file" 2>/dev/null || true)"
is_uint "$sshd_pid" || exit 1
kill -0 "$sshd_pid" >/dev/null 2>&1 || exit 1

cur="$sshd_pid"
i=0
while [ "$i" -lt 16 ]; do
  ppid="$(awk '/^PPid:[[:space:]]*/ {print $2; exit}' "/proc/$cur/status" 2>/dev/null || true)"
  is_uint "$ppid" || break
  [ "$ppid" -gt 1 ] || break
  kill -0 "$ppid" >/dev/null 2>&1 || break
  cmdline="$(read_cmdline "$ppid")"
  if is_pcbridge_cmdline "$cmdline"; then
    printf '%s\n' "$ppid"
    exit 0
  fi
  cur="$ppid"
  i=$((i + 1))
done

exit 1
SH
  )"
  pid="$(printf '%s\n' "$out" | tr -d '\r' | awk 'NF {print $1; exit}')"
  [[ -n "$pid" && "$pid" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$pid"
}

chroot_service_pcbridge_select_start_mode() {
  local _distro="$1"
  local answer
  local in_fd=0
  local out_fd=2
  local tty_fallback=0

  if [[ ! -t 0 || ! -t 1 ]]; then
    if { exec 3<>/dev/tty; } 2>/dev/null; then
      in_fd=3
      out_fd=3
      tty_fallback=1
    else
      printf 'pcbridge options:\n' >&2
      printf '  [f] First-run PC setup (starts SSH + bootstrap HTTP, then prints setup command)\n' >&2
      printf '  [c] Clean PC-side aurorafs files (starts SSH + bootstrap HTTP, then prints cleanup command)\n' >&2
      printf '  [s] Start service normally (SSH/SFTP only; no bootstrap HTTP/token)\n' >&2
      printf 'Non-interactive terminal detected; defaulting to [s] normal mode.\n' >&2
      printf 'normal\t\n'
      return 0
    fi
  fi

  while true; do
    printf 'pcbridge options:\n' >&"$out_fd"
    printf '  [f] First-run PC setup (starts SSH + bootstrap HTTP, then prints setup command)\n' >&"$out_fd"
    printf '  [c] Clean PC-side aurorafs files (starts SSH + bootstrap HTTP, then prints cleanup command)\n' >&"$out_fd"
    printf '  [s] Start service normally (SSH/SFTP only; no bootstrap HTTP/token)\n' >&"$out_fd"
    printf 'Choose option [f/c/s]: ' >&"$out_fd"
    read -r -u "$in_fd" answer || {
      if [[ "$tty_fallback" == "1" ]]; then
        exec 3>&-
      fi
      printf 'normal\t\n'
      return 0
    }
    case "${answer,,}" in
      f|first|setup|y|yes)
        if [[ "$tty_fallback" == "1" ]]; then
          exec 3>&-
        fi
        printf 'pairing\tbootstrap\n'
        return 0
        ;;
      c|clean|cleanup)
        if [[ "$tty_fallback" == "1" ]]; then
          exec 3>&-
        fi
        printf 'pairing\tcleanup\n'
        return 0
        ;;
      s|start|normal|n|no|'')
        if [[ "$tty_fallback" == "1" ]]; then
          exec 3>&-
        fi
        printf 'normal\t\n'
        return 0
        ;;
      *)
        printf 'Please choose f, c, or s.\n' >&"$out_fd"
        ;;
    esac
  done
}

chroot_service_pcbridge_print_after_start() {
  local distro="$1"
  local mode="${2:-normal}"
  local action="${3:-}"
  local cmd=""

  case "$mode" in
    pairing)
      case "$action" in
        bootstrap)
          cmd="$(chroot_service_pcbridge_bootstrap_command "$distro" || true)"
          if [[ -z "$cmd" ]]; then
            chroot_warn "pcbridge bootstrap command is not ready yet; wait a few seconds and retry start/restart."
            chroot_warn "If pcbridge is already running in normal mode, run restart and choose [f]."
            return 0
          fi
          chroot_info "First-run setup command (paste in WSL):"
          printf '%s\n' "$cmd"
          chroot_info "After setup completes, use alias on PC: aurorafs"
          chroot_service_pcbridge_wait_for_pairing_task "$distro" "bootstrap"
          ;;
        cleanup)
          cmd="$(chroot_service_pcbridge_cleanup_command "$distro" || true)"
          if [[ -z "$cmd" ]]; then
            chroot_warn "pcbridge cleanup command is not ready yet; wait a few seconds and retry start/restart."
            chroot_warn "If pcbridge is already running in normal mode, run restart and choose [c]."
            return 0
          fi
          chroot_info "PC cleanup command (paste in WSL):"
          printf '%s\n' "$cmd"
          chroot_info "Cleanup removes aurorafs files/aliases only. Packages stay installed."
          chroot_service_pcbridge_wait_for_pairing_task "$distro" "cleanup"
          ;;
        *)
          chroot_info "pcbridge started in pairing mode."
          ;;
      esac
      ;;
    *)
      chroot_info "pcbridge started in normal mode (SSH/SFTP only). Use alias on PC: aurorafs"
      ;;
  esac
}
