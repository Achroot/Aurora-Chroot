chroot_setting_set() {
  local key="$1"
  local value="$2"
  local tmp
  tmp="$CHROOT_SETTINGS_FILE.tmp"
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$CHROOT_SETTINGS_FILE" "$key" "$value" >"$tmp" <<'PY'
import json
import sys

p, key, value = sys.argv[1:4]
with open(p, 'r', encoding='utf-8') as fh:
    data = json.load(fh)

if value in ('true', 'false'):
    parsed = value == 'true'
elif value.isdigit():
    parsed = int(value)
else:
    parsed = value
data[key] = parsed
print(json.dumps(data, indent=2, sort_keys=True))
PY
  mv -f -- "$tmp" "$CHROOT_SETTINGS_FILE"
}

