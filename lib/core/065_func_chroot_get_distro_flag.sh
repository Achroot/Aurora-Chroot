chroot_get_distro_flag() {
  local distro="$1"
  local key="$2"
  local state_file
  state_file="$(chroot_distro_state_file "$distro")"
  [[ -f "$state_file" ]] || return 1
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$state_file" "$key" <<'PY'
import json
import sys
p, key = sys.argv[1:3]
with open(p, 'r', encoding='utf-8') as fh:
    data = json.load(fh)
v = data.get(key)
if isinstance(v, bool):
    print("true" if v else "false")
elif v is None:
    print("")
else:
    print(v)
PY
}

