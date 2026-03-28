chroot_session_count() {
  local distro="$1"
  local sf
  sf="$(chroot_distro_session_file "$distro")"
  [[ -f "$sf" ]] || {
    printf '0\n'
    return 0
  }

  chroot_session_prune_stale "$distro" >/dev/null 2>&1 || true

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$sf" <<'PY'
import json
import sys
try:
    with open(sys.argv[1], 'r', encoding='utf-8') as fh:
        arr = json.load(fh)
    if not isinstance(arr, list):
        arr = []
except Exception:
    arr = []
print(len(arr))
PY
}

