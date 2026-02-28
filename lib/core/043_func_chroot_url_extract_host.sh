chroot_url_extract_host() {
  local url="$1"
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$url" <<'PY'
import sys
from urllib.parse import urlparse
u = urlparse(sys.argv[1])
print(u.hostname or "")
PY
}

