chroot_service_find_pid_in_distro() {
  local distro="$1"
  local pattern="$2"
  local rootfs out pid

  rootfs="$(chroot_distro_rootfs_dir "$distro")"
  [[ -d "$rootfs" ]] || return 1

  out="$(
    chroot_run_chroot_cmd "$rootfs" /bin/sh -c '
      patt="$1"
      if command -v pgrep >/dev/null 2>&1; then
        pgrep -f "$patt" | head -n 1
      else
        ps -eo pid=,args= | awk -v p="$patt" "$0 ~ p {print \$1; exit}"
      fi
    ' -- "$pattern" 2>/dev/null || true
  )"
  pid="$(printf '%s\n' "$out" | tr -d '\r' | awk 'NF {print $1; exit}')"
  [[ -n "$pid" && "$pid" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$pid"
}

chroot_service_maybe_mark_desktop_start_error() {
  local distro="$1"
  local name="$2"
  local message="$3"
  local excerpt=""

  if [[ "${name,,}" != "${CHROOT_SERVICE_DESKTOP_SERVICE_NAME:-desktop}" ]]; then
    return 0
  fi
  declare -F chroot_service_desktop_mark_error >/dev/null 2>&1 || return 0

  if declare -F chroot_service_desktop_runtime_log_excerpt >/dev/null 2>&1; then
    excerpt="$(chroot_service_desktop_runtime_log_excerpt "$distro" 2>/dev/null || true)"
  fi
  if [[ -n "$excerpt" ]]; then
    message="$message: $excerpt"
  fi

  chroot_service_desktop_mark_error "$distro" "$message"
}

chroot_service_start() {
  local distro="$1"
  local name="$2"
  local cmd_prefix="${3:-}"
  local log_file="${4:-}"

  chroot_require_service_name "$name"

  local cmd_str runtime_cmd
  cmd_str="$(chroot_service_get_cmd "$distro" "$name")"
  [[ -n "$cmd_str" ]] || chroot_die "Service '$name' not found or has no command."

  runtime_cmd="$cmd_str"
  if [[ -n "$cmd_prefix" ]]; then
    runtime_cmd="$cmd_prefix $cmd_str"
  fi

  local existing_pid
  if existing_pid="$(chroot_service_get_pid "$distro" "$name")"; then
    chroot_info "Service '$name' is already running (PID: $existing_pid)"
    return 0
  fi

  if [[ -n "$log_file" ]]; then
    mkdir -p "$(dirname "$log_file")"
    rm -f -- "$log_file"
  fi

  # Remove stale service entries before attempting a fresh start.
  chroot_session_remove "$distro" "svc-$name"

  chroot_cmd_mount "$distro"

  local rootfs
  rootfs="$(chroot_distro_rootfs_dir "$distro")"

  local chroot_backend_bin chroot_backend_subcmd
  IFS=$'\t' read -r chroot_backend_bin chroot_backend_subcmd <<<"$(chroot_chroot_backend_parts_tsv || true)"
  [[ -n "$chroot_backend_bin" ]] || chroot_die "chroot backend unavailable; run doctor for diagnostics"

  local tmp_script
  tmp_script="$CHROOT_TMP_DIR/start_svc_$$.py"

  cat > "$tmp_script" <<'EOF_PY'
import os
import sys

chroot_bin = sys.argv[1]
chroot_subcmd = sys.argv[2]
rootfs = sys.argv[3]
cmd_str = sys.argv[4]
default_path = sys.argv[5]
display_value = sys.argv[6] if len(sys.argv) > 6 else ""
dpi_value = sys.argv[7] if len(sys.argv) > 7 else ""
log_path = sys.argv[8] if len(sys.argv) > 8 else ""

pid = os.fork()
if pid > 0:
    # Parent: wait for first child to print the daemon's PID
    _, status = os.waitpid(pid, 0)
    sys.exit(0)

os.setsid()
pid = os.fork()
if pid > 0:
    # First child: print the daemon's PID to original stdout, then exit
    print(pid)
    sys.exit(0)

devnull = os.open("/dev/null", os.O_RDWR)
os.dup2(devnull, 0)

log_fd = None
if log_path:
    try:
        log_dir = os.path.dirname(log_path)
        if log_dir:
            os.makedirs(log_dir, exist_ok=True)
        log_fd = os.open(log_path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o644)
    except Exception:
        log_fd = None

if log_fd is None:
    os.dup2(devnull, 1)
    os.dup2(devnull, 2)
else:
    os.dup2(log_fd, 1)
    os.dup2(log_fd, 2)
    os.close(log_fd)

os.close(devnull)

env = {
    "HOME": "/root",
    "TERM": os.environ.get("TERM", "xterm-256color"),
    "PATH": default_path,
    "LANG": os.environ.get("LANG", "C.UTF-8")
}
if display_value:
    env["DISPLAY"] = display_value
if dpi_value:
    env["AURORA_X11_DPI"] = dpi_value
    env["QT_FONT_DPI"] = dpi_value

args = [chroot_bin]
if chroot_subcmd:
    args.append(chroot_subcmd)
args.extend([rootfs, "/bin/sh", "-c", cmd_str])
os.execvpe(chroot_bin, args, env)
EOF_PY

  local path_value
  path_value="$(chroot_chroot_default_path)"
  local display_value dpi_value
  display_value="$(chroot_gui_display_value || true)"
  dpi_value="$(chroot_x11_dpi_value || true)"

  local svc_pid
  local start_rc=0
  set +e
  svc_pid="$(chroot_run_root "$CHROOT_PYTHON_BIN" "$tmp_script" "$chroot_backend_bin" "$chroot_backend_subcmd" "$rootfs" "$runtime_cmd" "$path_value" "$display_value" "$dpi_value" "$log_file")"
  start_rc=$?
  set -e
  rm -f -- "$tmp_script"

  if (( start_rc == 0 )) && [[ -n "$svc_pid" && "$svc_pid" =~ ^[0-9]+$ ]]; then
    chroot_session_remove "$distro" "svc-$name"
    chroot_session_add "$distro" "svc-$name" "service" "$cmd_str" "$svc_pid"

    # Service command is expected to stay in foreground; treat quick exit as start failure.
    if ! chroot_service_verify_running "$distro" "$name" 10 0.1; then
      if chroot_service_is_pcbridge "$name"; then
        local pcbridge_pid
        pcbridge_pid="$(chroot_service_pcbridge_supervisor_pid "$distro" || true)"
        if [[ -n "$pcbridge_pid" && "$pcbridge_pid" =~ ^[0-9]+$ ]]; then
          chroot_session_remove "$distro" "svc-$name"
          chroot_session_add "$distro" "svc-$name" "service" "$cmd_str" "$pcbridge_pid"
          if chroot_service_verify_running "$distro" "$name" 10 0.1; then
            chroot_log_info service "start-fallback distro=$distro service=$name pid=$pcbridge_pid cmd=$runtime_cmd"
            chroot_info "Service '$name' started (PID: $pcbridge_pid)"
            return 0
          fi
        fi
      fi

      chroot_run_root kill -TERM "$svc_pid" 2>/dev/null || true
      sleep 1
      chroot_run_root kill -KILL "$svc_pid" 2>/dev/null || true
      chroot_session_remove "$distro" "svc-$name"
      chroot_service_maybe_mark_desktop_start_error "$distro" "$name" "desktop session exited immediately after start"
      chroot_log_error service "start-check-failed distro=$distro service=$name pid=$svc_pid cmd=$runtime_cmd"
      chroot_die "Service '$name' exited immediately after start"
    fi

    chroot_log_info service "start distro=$distro service=$name pid=$svc_pid cmd=$runtime_cmd"
    chroot_info "Service '$name' started (PID: $svc_pid)"
  else
    chroot_service_maybe_mark_desktop_start_error "$distro" "$name" "failed to launch desktop session"
    chroot_log_error service "failed to start distro=$distro service=$name cmd=$runtime_cmd"
    chroot_die "Failed to start service '$name'"
  fi
}

chroot_service_stop() {
  local distro="$1"
  local name="$2"
  local still_pid=""

  chroot_require_service_name "$name"

  local svc_pid
  if ! svc_pid="$(chroot_service_get_pid "$distro" "$name")"; then
    chroot_session_remove "$distro" "svc-$name"
    chroot_info "Service '$name' is not running."
    return 0
  fi

  chroot_run_root kill -TERM "$svc_pid" 2>/dev/null || true
  sleep 1
  if still_pid="$(chroot_service_get_pid "$distro" "$name")" && [[ "$still_pid" == "$svc_pid" ]]; then
    chroot_run_root kill -KILL "$svc_pid" 2>/dev/null || true
  fi

  chroot_session_remove "$distro" "svc-$name"
  chroot_log_info service "stop distro=$distro service=$name pid=$svc_pid"
  chroot_info "Service '$name' stopped."
}

chroot_service_status_json() {
  local distro="$1"
  local sdir
  sdir="$(chroot_service_dir "$distro")"

  local sf lock_file
  sf="$(chroot_distro_session_file "$distro")"
  lock_file="$(chroot_session_lock_file "$distro")"

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$sdir" "$sf" "$lock_file" <<'PY'
import json, os, sys, glob

sdir, sf, lock_file = sys.argv[1:4]

try:
    import fcntl
except Exception:
    fcntl = None

def pid_is_live(pid):
    try:
        os.kill(pid, 0)
        return True
    except PermissionError:
        return True
    except OSError:
        return False

def pid_starttime(pid):
    try:
        with open(f"/proc/{pid}/stat", "r", encoding="utf-8") as fh:
            parts = fh.read().split()
        if len(parts) >= 22:
            return int(parts[21])
    except Exception:
        return None
    return None

sessions = []
if os.path.exists(lock_file) and os.path.exists(sf):
    with open(lock_file, "a+", encoding="utf-8") as lock_fh:
        if fcntl is not None:
            fcntl.flock(lock_fh.fileno(), fcntl.LOCK_SH)
        try:
            with open(sf, "r", encoding="utf-8") as fh:
                sessions = json.load(fh)
        except Exception:
            sessions = []
        if not isinstance(sessions, list):
            sessions = []

svcs = []
if os.path.isdir(sdir):
    for f in sorted(glob.glob(os.path.join(sdir, "*.json"))):
        name = os.path.basename(f)
        if name.endswith(".json"):
            name = name[:-5]
        else:
            continue
            
        try:
            with open(f, "r", encoding="utf-8") as fh:
                data = json.load(fh)
            cmd = data.get("command", "")
        except Exception:
            continue
        
        pid_str = ""
        state = "Stopped"
        for row in sessions:
            if row.get("session_id") == f"svc-{name}":
                pid = row.get("pid")
                expected_start = row.get("pid_starttime")
                if not isinstance(pid, int) or pid <= 0: continue
                if not isinstance(expected_start, int):
                    if pid_is_live(pid):
                        pid_str = str(pid)
                        state = "Running"
                        break
                    continue
                if not pid_is_live(pid): continue
                current_start = pid_starttime(pid)
                if current_start is None: continue
                if current_start != expected_start: continue
                pid_str = str(pid)
                state = "Running"
                break
        
        svcs.append({
            "name": name,
            "state": state,
            "pid": pid_str,
            "command": cmd
        })

print(json.dumps(svcs))
PY
}
