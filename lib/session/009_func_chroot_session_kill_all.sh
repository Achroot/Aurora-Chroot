chroot_session_kill_all() {
  local distro="$1"
  local grace_sec="${2:-3}"
  local sf lock_file
  sf="$(chroot_distro_session_file "$distro")"
  lock_file="$(chroot_session_lock_file "$distro")"

  [[ "$grace_sec" =~ ^[0-9]+$ ]] || grace_sec=3
  [[ -f "$sf" ]] || {
    printf '0\t0\t0\t0\t0\t0\n'
    return 0
  }

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$sf" "$lock_file" "$grace_sec" <<'PY'
import json
import os
import signal
import sys
import tempfile
import time

try:
    import fcntl
except Exception:
    fcntl = None

sf, lock_file, grace_text = sys.argv[1:4]
try:
    grace = int(grace_text)
except Exception:
    grace = 3
if grace < 0:
    grace = 0

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

def load_rows():
    try:
        with open(sf, "r", encoding="utf-8") as fh:
            rows = json.load(fh)
        if isinstance(rows, list):
            return rows
    except Exception:
        pass
    return []

def write_rows(rows):
    fd, tmp = tempfile.mkstemp(prefix=".sessions.", suffix=".json", dir=os.path.dirname(sf))
    with os.fdopen(fd, "w", encoding="utf-8") as out:
        json.dump(rows, out, indent=2, sort_keys=True)
        out.write("\n")
    os.replace(tmp, sf)

def same_process(pid, expected_start):
    if not isinstance(pid, int) or pid <= 0:
        return False
    if not isinstance(expected_start, int):
        return False
    if not pid_is_live(pid):
        return False
    current = pid_starttime(pid)
    if current is None:
        return False
    return current == expected_start

def same_process_group(pgid, expected_start):
    if not isinstance(pgid, int) or pgid <= 0:
        return False
    if not isinstance(expected_start, int):
        return False
    try:
        if pgid == os.getpgrp():
            return False
    except Exception:
        pass
    if not pid_is_live(pgid):
        return False
    current = pid_starttime(pgid)
    if current is None:
        return False
    return current == expected_start

def row_live_without_identity(row):
    pgid = row.get("pgid")
    pgid_start = row.get("pgid_starttime")
    if isinstance(pgid, int) and pgid > 0 and pid_is_live(pgid) and not isinstance(pgid_start, int):
        return True
    pid = row.get("pid")
    pid_start = row.get("pid_starttime")
    if isinstance(pid, int) and pid > 0 and pid_is_live(pid) and not isinstance(pid_start, int):
        return True
    return False

with open(lock_file, "a+", encoding="utf-8") as lock_fh:
    if fcntl is not None:
        fcntl.flock(lock_fh.fileno(), fcntl.LOCK_EX)

    rows = load_rows()
    original_len = len(rows)

    group_targets = {}
    pid_targets = {}
    skipped_identity = 0
    for row in rows:
        pgid = row.get("pgid")
        expected_pgid_start = row.get("pgid_starttime")
        if same_process_group(pgid, expected_pgid_start):
            group_targets[pgid] = expected_pgid_start
            continue

        pid = row.get("pid")
        expected_start = row.get("pid_starttime")
        if same_process(pid, expected_start):
            pid_targets[pid] = expected_start
            continue

        if row_live_without_identity(row):
            skipped_identity += 1

    targeted = len(group_targets) + len(pid_targets)
    term_sent = 0
    kill_sent = 0

    for pgid, expected_start in group_targets.items():
        if not same_process_group(pgid, expected_start):
            continue
        try:
            os.killpg(pgid, signal.SIGTERM)
            term_sent += 1
        except ProcessLookupError:
            pass
        except PermissionError:
            pass
        except OSError:
            pass

    for pid, expected_start in pid_targets.items():
        if not same_process(pid, expected_start):
            continue
        try:
            os.kill(pid, signal.SIGTERM)
            term_sent += 1
        except ProcessLookupError:
            pass
        except PermissionError:
            pass
        except OSError:
            pass

    deadline = time.time() + grace
    while time.time() < deadline:
        alive = 0
        for pgid, expected_start in group_targets.items():
            if same_process_group(pgid, expected_start):
                alive += 1
        for pid, expected_start in pid_targets.items():
            if same_process(pid, expected_start):
                alive += 1
        if alive == 0:
            break
        time.sleep(0.2)

    for pgid, expected_start in group_targets.items():
        if not same_process_group(pgid, expected_start):
            continue
        try:
            os.killpg(pgid, signal.SIGKILL)
            kill_sent += 1
        except ProcessLookupError:
            pass
        except PermissionError:
            pass
        except OSError:
            pass

    for pid, expected_start in pid_targets.items():
        if not same_process(pid, expected_start):
            continue
        try:
            os.kill(pid, signal.SIGKILL)
            kill_sent += 1
        except ProcessLookupError:
            pass
        except PermissionError:
            pass
        except OSError:
            pass

    time.sleep(0.2)

    kept = []
    for row in rows:
        pgid = row.get("pgid")
        expected_pgid_start = row.get("pgid_starttime")
        if same_process_group(pgid, expected_pgid_start):
            kept.append(row)
            continue

        pid = row.get("pid")
        expected_start = row.get("pid_starttime")
        if same_process(pid, expected_start):
            kept.append(row)
            continue

        if row_live_without_identity(row):
            kept.append(row)
            continue

    remaining = len(kept)
    cleaned = original_len - remaining
    if kept != rows:
        write_rows(kept)

print(f"{targeted}\t{term_sent}\t{kill_sent}\t{remaining}\t{cleaned}\t{skipped_identity}")
sys.exit(0 if remaining == 0 else 1)
PY
}
