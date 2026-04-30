chroot_service_add_def() {
  local distro="$1"
  local name="$2"
  local cmd_str="$3"
  local def_file tmp

  chroot_require_service_name "$name"
  [[ -n "$cmd_str" ]] || chroot_die "service command is required"

  def_file="$(chroot_service_def_file "$distro" "$name")"
  mkdir -p "$(dirname "$def_file")"
  tmp="$def_file.tmp"

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$tmp" "$name" "$cmd_str" <<'PY'
import json
import sys
tmp_file, svc_name, svc_cmd = sys.argv[1:4]
data = {
    "name": svc_name,
    "command": svc_cmd
}
with open(tmp_file, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, sort_keys=True)
PY
  mv -f -- "$tmp" "$def_file"
  chroot_info "Service '$name' added to $distro"
}

chroot_service_remove_def() {
  local distro="$1"
  local name="$2"
  local def_file
  chroot_require_service_name "$name"
  def_file="$(chroot_service_def_file "$distro" "$name")"
  if [[ -f "$def_file" ]]; then
    rm -f -- "$def_file"
    chroot_info "Service '$name' removed from $distro (definition: $def_file)"
    return 0
  else
    chroot_err "Service '$name' not found in $distro"
    return 1
  fi
}

chroot_service_get_cmd() {
  local distro="$1"
  local name="$2"
  local def_file
  chroot_require_service_name "$name"
  def_file="$(chroot_service_def_file "$distro" "$name")"
  [[ -f "$def_file" ]] || return 1
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$def_file" <<'PY'
import json
import sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as fh:
        data = json.load(fh)
    print(data.get("command", ""))
except Exception:
    pass
PY
}

chroot_service_get_pid() {
  local distro="$1"
  local name="$2"
  local sf lock_file
  chroot_require_service_name "$name"
  sf="$(chroot_distro_session_file "$distro")"
  lock_file="$(chroot_session_lock_file "$distro")"
  [[ -f "$sf" ]] || return 1

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$sf" "$lock_file" "svc-$name" <<'PY'
import json
import os
import sys

try:
    import fcntl
except Exception:
    fcntl = None

sf_path, lock_path, sid = sys.argv[1:4]

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

with open(lock_path, "a+", encoding="utf-8") as lock_fh:
    if fcntl is not None:
        fcntl.flock(lock_fh.fileno(), fcntl.LOCK_SH)
    try:
        with open(sf_path, "r", encoding="utf-8") as fh:
            rows = json.load(fh)
        if not isinstance(rows, list):
            rows = []
    except Exception:
        rows = []

    for row in rows:
        if row.get("session_id") == sid:
            pid = row.get("pid")
            expected_start = row.get("pid_starttime")
            if not isinstance(pid, int) or pid <= 0:
                continue
            if not isinstance(expected_start, int):
                if pid_is_live(pid):
                    print(pid)
                    sys.exit(0)
                continue
            if not pid_is_live(pid):
                continue
            current_start = pid_starttime(pid)
            if current_start is None:
                continue
            if current_start != expected_start:
                continue
            if isinstance(pid, int) and pid > 0:
                print(pid)
                sys.exit(0)
    sys.exit(1)
PY
}

chroot_service_verify_running() {
  local distro="$1"
  local name="$2"
  local checks="${3:-10}"
  local interval="${4:-0.1}"
  local i

  [[ "$checks" =~ ^[0-9]+$ ]] || checks=10
  if (( checks < 1 )); then
    checks=1
  fi

  for (( i=0; i<checks; i++ )); do
    chroot_service_get_pid "$distro" "$name" >/dev/null 2>&1 || return 1
    sleep "$interval"
  done
  return 0
}
