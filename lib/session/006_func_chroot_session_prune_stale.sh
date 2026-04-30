chroot_session_prune_stale() {
  local distro="$1"
  local sf lock_file
  sf="$(chroot_distro_session_file "$distro")"
  lock_file="$(chroot_session_lock_file "$distro")"
  [[ -f "$sf" ]] || {
    printf '0\n'
    return 0
  }

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$sf" "$lock_file" <<'PY'
import os
import json
import sys
import tempfile

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

with open(lock_file, 'a+', encoding='utf-8') as lock_fh:
    if fcntl is not None:
        fcntl.flock(lock_fh.fileno(), fcntl.LOCK_EX)

    try:
        with open(sf, 'r', encoding='utf-8') as fh:
            rows = json.load(fh)
        if not isinstance(rows, list):
            rows = []
    except Exception:
        rows = []

    kept = []
    stale = 0
    for row in rows:
        pgid = row.get('pgid')
        expected_group_start = row.get('pgid_starttime')
        if same_process_group(pgid, expected_group_start):
            kept.append(row)
            continue

        pid = row.get('pid')
        expected_start = row.get('pid_starttime')
        if same_process(pid, expected_start):
            kept.append(row)
            continue

        stale += 1

    if stale > 0:
        fd, tmp = tempfile.mkstemp(prefix='.sessions.', suffix='.json', dir=os.path.dirname(sf))
        with os.fdopen(fd, 'w', encoding='utf-8') as out:
            json.dump(kept, out, indent=2, sort_keys=True)
            out.write('\n')
        os.replace(tmp, sf)

    print(stale)
PY
}
