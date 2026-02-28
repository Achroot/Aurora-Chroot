chroot_url_extract_port() {
  local url="$1"
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$url" <<'PY'
import sys
from urllib.parse import urlparse
u = urlparse(sys.argv[1])
if u.port:
    print(u.port)
elif u.scheme == "https":
    print(443)
else:
    print(80)
PY
}

