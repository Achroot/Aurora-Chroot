chroot_x11_socket_dir() {
  printf '%s/tmp/.X11-unix' "$CHROOT_TERMUX_PREFIX"
}

chroot_x11_socket_path_display0() {
  printf '%s/X0' "$(chroot_x11_socket_dir)"
}

chroot_x11_enabled() {
  chroot_is_true "$(chroot_setting_get x11 2>/dev/null || echo false)"
}

chroot_x11_bin_path() {
  if [[ -x "$CHROOT_TERMUX_BIN/termux-x11" ]]; then
    printf '%s\n' "$CHROOT_TERMUX_BIN/termux-x11"
    return 0
  fi
  local found
  found="$(command -v termux-x11 2>/dev/null || true)"
  [[ -n "$found" ]] || return 1
  printf '%s\n' "$found"
}

chroot_x11_shell_path() {
  if [[ -n "$CHROOT_HOST_SH" && -x "$CHROOT_HOST_SH" ]]; then
    printf '%s\n' "$CHROOT_HOST_SH"
    return 0
  fi
  if [[ -x "/bin/sh" ]]; then
    printf '%s\n' "/bin/sh"
    return 0
  fi
  if [[ -x "$CHROOT_TERMUX_BIN/sh" ]]; then
    printf '%s\n' "$CHROOT_TERMUX_BIN/sh"
    return 0
  fi
  local found
  found="$(command -v sh 2>/dev/null || true)"
  [[ -n "$found" ]] || return 1
  printf '%s\n' "$found"
}

chroot_x11_is_display_ready() {
  local sock
  sock="$(chroot_x11_socket_path_display0)"
  [[ -S "$sock" ]] || return 1
  chroot_x11_socket_has_listener "$sock"
}

chroot_x11_wait_ready() {
  local timeout_sec="${1:-12}"
  local loops
  loops=$(( timeout_sec * 10 ))
  while (( loops > 0 )); do
    if chroot_x11_is_display_ready; then
      return 0
    fi
    sleep 0.1
    loops=$((loops - 1))
  done
  return 1
}

chroot_x11_am_launcher() {
  if [[ -x "$CHROOT_TERMUX_BIN/termux-am" ]]; then
    printf '%s\n' "$CHROOT_TERMUX_BIN/termux-am"
    return 0
  fi

  local found
  found="$(command -v termux-am 2>/dev/null || true)"
  if [[ -n "$found" ]]; then
    printf '%s\n' "$found"
    return 0
  fi

  found="$(command -v am 2>/dev/null || true)"
  [[ -n "$found" ]] || return 1
  printf '%s\n' "$found"
}

chroot_x11_current_android_user() {
  local launcher out
  launcher="$(chroot_x11_am_launcher || true)"
  [[ -n "$launcher" ]] || return 1

  out="$("$launcher" get-current-user 2>/dev/null | tr -d '\r\n' || true)"
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$out"
}

chroot_x11_try_open_app() {
  local launcher user_id=""
  local -a base_args=()
  launcher="$(chroot_x11_am_launcher || true)"
  [[ -n "$launcher" ]] || return 1

  user_id="$(chroot_x11_current_android_user || true)"

  if [[ -n "$user_id" ]]; then
    base_args+=(--user "$user_id")
  fi
  base_args+=(start)

  if chroot_run_host_user "$launcher" "${base_args[@]}" -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1; then
    return 0
  fi
  chroot_run_root "$launcher" "${base_args[@]}" -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1 && return 0 || true

  if chroot_run_host_user "$launcher" "${base_args[@]}" -n com.termux.x11/.MainActivity >/dev/null 2>&1; then
    return 0
  fi
  chroot_run_root "$launcher" "${base_args[@]}" -n com.termux.x11/.MainActivity >/dev/null 2>&1 && return 0 || true

  if chroot_run_host_user "$launcher" "${base_args[@]}" -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -p com.termux.x11 >/dev/null 2>&1; then
    return 0
  fi
  chroot_run_root "$launcher" "${base_args[@]}" -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -p com.termux.x11 >/dev/null 2>&1 && return 0 || true

  if chroot_run_host_user "$launcher" "${base_args[@]}" -a android.intent.action.VIEW -p com.termux.x11 >/dev/null 2>&1; then
    return 0
  fi
  chroot_run_root "$launcher" "${base_args[@]}" -a android.intent.action.VIEW -p com.termux.x11 >/dev/null 2>&1 && return 0 || true

  if chroot_cmd_exists monkey; then
    chroot_run_host_user monkey -p com.termux.x11 -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 && return 0
    chroot_run_root monkey -p com.termux.x11 -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 && return 0 || true
  fi

  return 1
}

chroot_x11_try_open_app_retry() {
  local attempts="${1:-6}"
  local delay_sec="${2:-0.5}"
  local idx

  [[ "$attempts" =~ ^[0-9]+$ ]] || attempts=6
  if (( attempts < 1 )); then
    attempts=1
  fi

  for (( idx = 0; idx < attempts; idx++ )); do
    chroot_x11_try_open_app && return 0
    sleep "$delay_sec"
  done
  return 1
}

chroot_x11_spawn_display0() {
  local shell_bin x11_bin qcmd
  shell_bin="$(chroot_x11_shell_path)" || return 1
  x11_bin="$(chroot_x11_bin_path)" || return 1

  if chroot_cmd_exists nohup; then
    qcmd="$(chroot_quote_cmd nohup "$shell_bin" "$x11_bin" ":0")"
  else
    qcmd="$(chroot_quote_cmd "$shell_bin" "$x11_bin" ":0")"
  fi
  qcmd+=" >/dev/null 2>&1 </dev/null &"
  chroot_run_root_cmd "$qcmd"
}

chroot_x11_stop_existing() {
  local sock
  sock="$(chroot_x11_socket_path_display0)"

  if chroot_cmd_exists pkill; then
    chroot_run_root pkill -f "termux-x11" >/dev/null 2>&1 || true
    chroot_run_root pkill -f "com.termux.x11" >/dev/null 2>&1 || true
  fi
  chroot_run_root rm -f -- "$sock" >/dev/null 2>&1 || true
  sleep 0.2
}

chroot_x11_has_running_process() {
  if chroot_cmd_exists pgrep; then
    if chroot_run_root pgrep -af "termux-x11|com.termux.x11" >/dev/null 2>&1; then
      return 0
    fi
  fi
  return 1
}

chroot_x11_socket_accepts_connections() {
  local sock="${1:-}"
  local py_bin=""
  local probe_rc=0

  [[ -n "$sock" ]] || sock="$(chroot_x11_socket_path_display0)"
  [[ -S "$sock" ]] || return 1

  if [[ -n "${CHROOT_PYTHON_BIN:-}" && -x "${CHROOT_PYTHON_BIN:-}" ]]; then
    py_bin="$CHROOT_PYTHON_BIN"
  else
    py_bin="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)"
  fi
  [[ -n "$py_bin" ]] || return 2

  set +e
  "$py_bin" - "$sock" >/dev/null 2>&1 <<'PY'
import errno
import socket
import sys

path = sys.argv[1]
client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
client.settimeout(0.5)
try:
    client.connect(path)
except PermissionError:
    sys.exit(3)
except OSError as exc:
    if exc.errno in {
        errno.ECONNREFUSED,
        errno.ENOENT,
        errno.ENOTSOCK,
        errno.EAGAIN,
        errno.EWOULDBLOCK,
    }:
        sys.exit(1)
    sys.exit(2)
else:
    sys.exit(0)
finally:
    try:
        client.close()
    except Exception:
        pass
PY
  probe_rc=$?
  set -e

  case "$probe_rc" in
    0|3) return 0 ;;
    2) return 2 ;;
    *) return 1 ;;
  esac
}

chroot_x11_socket_has_listener() {
  local sock="${1:-}"
  local connect_rc=0
  [[ -n "$sock" ]] || sock="$(chroot_x11_socket_path_display0)"
  [[ -S "$sock" ]] || return 1

  chroot_x11_socket_accepts_connections "$sock"
  connect_rc=$?
  case "$connect_rc" in
    0) return 0 ;;
    1) return 1 ;;
  esac

  # Primary check: live UNIX socket entry in kernel table.
  if [[ -r "/proc/net/unix" ]]; then
    if awk -v s="$sock" 'NR > 1 && $NF == s {found=1; exit} END {exit(found ? 0 : 1)}' /proc/net/unix 2>/dev/null; then
      return 0
    fi
  fi

  # Fallback check for environments where /proc/net/unix is restricted.
  if chroot_cmd_exists ss; then
    if ss -xl 2>/dev/null | grep -F -- "$sock" >/dev/null 2>&1; then
      return 0
    fi
  fi

  # Last-resort heuristic: X11 process exists.
  chroot_x11_has_running_process
}

chroot_x11_cleanup_stale_socket() {
  local sock
  sock="$(chroot_x11_socket_path_display0)"
  [[ -S "$sock" ]] || return 0
  if chroot_x11_socket_has_listener "$sock"; then
    return 0
  fi
  if declare -F chroot_log_warn >/dev/null 2>&1; then
    chroot_log_warn x11 "stale socket detected at $sock; cleaning up"
  fi
  chroot_run_root rm -f -- "$sock" >/dev/null 2>&1 || true
}

chroot_x11_start_display0() {
  local timeout_sec="${1:-12}"

  chroot_x11_cleanup_stale_socket

  if chroot_x11_is_display_ready; then
    return 0
  fi

  chroot_x11_cleanup_stale_socket
  if ! chroot_x11_spawn_display0; then
    return 1
  fi
  chroot_x11_try_open_app_retry 3 0.5 >/dev/null 2>&1 || true
  chroot_x11_wait_ready "$timeout_sec"
}

chroot_x11_ensure_display0() {
  local timeout_sec="${1:-12}"
  if chroot_x11_is_display_ready; then
    return 0
  fi
  chroot_x11_start_display0 "$timeout_sec"
}

chroot_x11_restart_display0() {
  local timeout_sec="${1:-15}"
  chroot_x11_stop_existing
  chroot_x11_start_display0 "$timeout_sec"
}

chroot_x11_enable_display0() {
  local timeout_sec="${1:-15}"

  chroot_x11_cleanup_stale_socket

  # Healthy display already up; do not restart.
  if chroot_x11_is_display_ready; then
    return 0
  fi

  # First try non-destructive start.
  if chroot_x11_start_display0 "$timeout_sec"; then
    return 0
  fi

  # If startup still failed with stale process/socket state, recover by restart.
  if chroot_x11_has_running_process && ! chroot_x11_is_display_ready; then
    if chroot_x11_restart_display0 "$timeout_sec"; then
      return 0
    fi
  fi

  return 1
}
