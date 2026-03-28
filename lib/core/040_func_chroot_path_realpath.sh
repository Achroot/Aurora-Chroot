chroot_path_realpath() {
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$1" <<'PY'
import os
import sys
print(os.path.realpath(sys.argv[1]))
PY
}

