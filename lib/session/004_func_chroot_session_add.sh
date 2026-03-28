chroot_session_add() {
  local distro="$1"
  local session_id="$2"
  local mode="$3"
  local command_str="$4"
  local pid="${5:-}"
  local sf lock_file
  sf="$(chroot_distro_session_file "$distro")"
  lock_file="$(chroot_session_lock_file "$distro")"
  chroot_session_init_file "$distro"

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$sf" "$lock_file" "$session_id" "$mode" "$command_str" "$pid" <<'PY'
import os
import json
import sys
import tempfile
from datetime import datetime, timezone

try:
    import fcntl
except Exception:
    fcntl = None

sf, lock_file, session_id, mode, command_str, pid_text = sys.argv[1:7]

pid = None
pid_starttime = None
pgid = None
pgid_starttime = None
try:
    parsed = int(str(pid_text).strip())
    if parsed > 0:
        pid = parsed
except Exception:
    pid = None

def read_pid_starttime(candidate):
    if candidate is None:
        return None
    try:
        with open(f"/proc/{candidate}/stat", "r", encoding="utf-8") as fh:
            parts = fh.read().split()
        if len(parts) >= 22:
            return int(parts[21])
    except Exception:
        return None
    return None

pid_starttime = read_pid_starttime(pid)
if pid is not None:
    try:
        candidate = os.getpgid(pid)
        if isinstance(candidate, int) and candidate > 0:
            pgid = candidate
            pgid_starttime = read_pid_starttime(candidate)
    except Exception:
        pgid = None
        pgid_starttime = None

def load_rows(path):
    try:
        with open(path, 'r', encoding='utf-8') as fh:
            arr = json.load(fh)
        if not isinstance(arr, list):
            return []
        return arr
    except Exception:
        return []

os.makedirs(os.path.dirname(sf), exist_ok=True)
if not os.path.exists(sf):
    with open(sf, 'w', encoding='utf-8') as fh:
        fh.write('[]\n')

with open(lock_file, 'a+', encoding='utf-8') as lock_fh:
    if fcntl is not None:
        fcntl.flock(lock_fh.fileno(), fcntl.LOCK_EX)

    rows = load_rows(sf)
    rows.append({
        "session_id": session_id,
        "pid": pid,
        "pid_starttime": pid_starttime,
        "pgid": pgid,
        "pgid_starttime": pgid_starttime,
        "mode": mode,
        "command": command_str,
        "started_at": datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z'),
    })

    fd, tmp = tempfile.mkstemp(prefix='.sessions.', suffix='.json', dir=os.path.dirname(sf))
    with os.fdopen(fd, 'w', encoding='utf-8') as out:
        json.dump(rows, out, indent=2, sort_keys=True)
        out.write('\n')
    os.replace(tmp, sf)
PY
}
