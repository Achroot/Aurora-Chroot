chroot_session_list_json() {
  local distro="$1"
  local sf lock_file
  sf="$(chroot_distro_session_file "$distro")"
  lock_file="$(chroot_session_lock_file "$distro")"
  [[ -f "$sf" ]] || {
    printf '[]\n'
    return 0
  }

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$sf" "$lock_file" <<'PY'
import json
import os
import sys

try:
    import fcntl
except Exception:
    fcntl = None

sf, lock_file = sys.argv[1:3]

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

def same_process(pid, expected_start):
    if not isinstance(pid, int) or pid <= 0:
        return False
    if not pid_is_live(pid):
        return False
    if not isinstance(expected_start, int):
        return False
    current = pid_starttime(pid)
    if current is None:
        return False
    return current == expected_start

def same_process_group(pgid, expected_start):
    if not isinstance(pgid, int) or pgid <= 0:
        return False
    if not pid_is_live(pgid):
        return False
    if not isinstance(expected_start, int):
        return False
    current = pid_starttime(pgid)
    if current is None:
        return False
    return current == expected_start

with open(lock_file, "a+", encoding="utf-8") as lock_fh:
    if fcntl is not None:
        fcntl.flock(lock_fh.fileno(), fcntl.LOCK_SH)

    try:
        with open(sf, "r", encoding="utf-8") as fh:
            rows = json.load(fh)
        if not isinstance(rows, list):
            rows = []
    except Exception:
        rows = []

    out = []
    for row in rows:
        sid = str(row.get("session_id", "")).strip()
        if not sid:
            continue
        mode = str(row.get("mode", "")).strip() or "-"
        started = str(row.get("started_at", "")).strip() or "-"
        cmd = str(row.get("command", "")).strip() or "-"
        pid = row.get("pid")
        expected_start = row.get("pid_starttime")
        pgid = row.get("pgid")
        expected_group_start = row.get("pgid_starttime")

        pid_out = None
        pgid_out = None
        state = "no-pid"
        if same_process_group(pgid, expected_group_start):
            if isinstance(pid, int) and pid > 0:
                pid_out = pid
            pgid_out = pgid
            state = "live-group"
        elif isinstance(pid, int) and pid > 0:
            pid_out = pid
            if same_process(pid, expected_start):
                state = "live"
            elif pid_is_live(pid):
                state = "live-unknown-start"
            else:
                state = "dead"

        out.append(
            {
                "session_id": sid,
                "pid": pid_out,
                "pgid": pgid_out,
                "mode": mode,
                "started_at": started,
                "state": state,
                "command": cmd,
            }
        )

print(json.dumps(out))
PY
}
