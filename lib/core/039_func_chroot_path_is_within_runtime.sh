chroot_path_is_within_runtime() {
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$1" "$CHROOT_RUNTIME_ROOT" <<'PY'
import os
import sys
candidate = os.path.realpath(sys.argv[1])
root = os.path.realpath(sys.argv[2])
if candidate == root or candidate.startswith(root + os.sep):
    print("yes")
else:
    print("no")
PY
}

