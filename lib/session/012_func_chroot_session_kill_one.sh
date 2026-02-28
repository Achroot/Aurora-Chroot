chroot_session_kill_one() {
  local distro="$1"
  local session_id="$2"
  local grace_sec="${3:-3}"
  local sf lock_file
  sf="$(chroot_distro_session_file "$distro")"
  lock_file="$(chroot_session_lock_file "$distro")"

  [[ "$grace_sec" =~ ^[0-9]+$ ]] || grace_sec=3
  [[ -f "$sf" ]] || {
    printf '0\t0\t0\t0\t0\n'
    return 2
  }

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$sf" "$lock_file" "$session_id" "$grace_sec" <<'PY'
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

sf, lock_file, wanted_sid, grace_text = sys.argv[1:5]
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

with open(lock_file, "a+", encoding="utf-8") as lock_fh:
    if fcntl is not None:
        fcntl.flock(lock_fh.fileno(), fcntl.LOCK_EX)

    rows = load_rows()
    found = 0
    targeted = 0
    term_sent = 0
    kill_sent = 0
    still_alive = 0

    target_row = None
    for row in rows:
        if str(row.get("session_id", "")) == wanted_sid:
            target_row = row
            break

    if target_row is None:
        print("0\t0\t0\t0\t0")
        sys.exit(2)

    found = 1
    pid = target_row.get("pid")
    expected_start = target_row.get("pid_starttime")
    pgid = target_row.get("pgid")
    expected_pgid_start = target_row.get("pgid_starttime")
    use_group = same_process_group(pgid, expected_pgid_start)
    use_pid = same_process(pid, expected_start)

    if use_group:
        targeted = 1
        try:
            os.killpg(pgid, signal.SIGTERM)
            term_sent += 1
        except Exception:
            pass
    elif use_pid:
        targeted = 1
        try:
            os.kill(pid, signal.SIGTERM)
            term_sent += 1
        except Exception:
            pass

    if targeted == 1:
        deadline = time.time() + grace
        while time.time() < deadline:
            if use_group:
                if not same_process_group(pgid, expected_pgid_start):
                    break
            elif not same_process(pid, expected_start):
                break
            time.sleep(0.2)

        if use_group:
            if same_process_group(pgid, expected_pgid_start):
                try:
                    os.killpg(pgid, signal.SIGKILL)
                    kill_sent += 1
                except Exception:
                    pass
                time.sleep(0.2)
        elif same_process(pid, expected_start):
            try:
                os.kill(pid, signal.SIGKILL)
                kill_sent += 1
            except Exception:
                pass
            time.sleep(0.2)

    if use_group:
        if same_process_group(pgid, expected_pgid_start):
            still_alive = 1
    elif same_process(pid, expected_start):
        still_alive = 1

    if still_alive == 0:
        rows = [row for row in rows if str(row.get("session_id", "")) != wanted_sid]
        write_rows(rows)

print(f"{found}\t{targeted}\t{term_sent}\t{kill_sent}\t{still_alive}")
sys.exit(0 if still_alive == 0 else 1)
PY
}
