chroot_setting_get() {
  local key="$1"
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$CHROOT_SETTINGS_FILE" "$key" <<'PY'
import json
import sys
p = sys.argv[1]
k = sys.argv[2]
with open(p, 'r', encoding='utf-8') as fh:
    data = json.load(fh)
v = data.get(k)
if isinstance(v, bool):
    print("true" if v else "false")
elif v is None:
    print("")
else:
    print(v)
PY
}

