chroot_set_distro_flag() {
  local distro="$1"
  local key="$2"
  local value="$3"
  local state_file tmp

  state_file="$(chroot_distro_state_file "$distro")"
  mkdir -p "$(dirname "$state_file")"
  tmp="$state_file.tmp"

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$state_file" "$key" "$value" >"$tmp" <<'PY'
import json
import os
import sys
state_file, key, value = sys.argv[1:4]
if os.path.exists(state_file):
    try:
        with open(state_file, 'r', encoding='utf-8') as fh:
            data = json.load(fh)
    except Exception:
        data = {}
else:
    data = {}
if value in ("true", "false"):
    parsed = value == "true"
elif value.isdigit():
    parsed = int(value)
else:
    parsed = value
data[key] = parsed
print(json.dumps(data, indent=2, sort_keys=True))
PY

  mv -f -- "$tmp" "$state_file"
}

