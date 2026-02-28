chroot_session_remove() {
  local distro="$1"
  local session_id="$2"

  local sf lock_file
  sf="$(chroot_distro_session_file "$distro")"
  lock_file="$(chroot_session_lock_file "$distro")"
  [[ -f "$sf" ]] || return 0

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$sf" "$lock_file" "$session_id" <<'PY'
import os
import json
import sys
import tempfile

try:
    import fcntl
except Exception:
    fcntl = None

sf, lock_file, session_id = sys.argv[1:4]

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

    rows = [row for row in rows if str(row.get('session_id')) != session_id]

    fd, tmp = tempfile.mkstemp(prefix='.sessions.', suffix='.json', dir=os.path.dirname(sf))
    with os.fdopen(fd, 'w', encoding='utf-8') as out:
        json.dump(rows, out, indent=2, sort_keys=True)
        out.write('\n')
    os.replace(tmp, sf)
PY
}

