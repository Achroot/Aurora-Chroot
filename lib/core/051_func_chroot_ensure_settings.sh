chroot_ensure_settings() {
  chroot_require_python
  local tmp defaults_file
  tmp="$CHROOT_TMP_DIR/settings.$$.json"
  defaults_file="$CHROOT_TMP_DIR/settings-defaults.$$.json"

  chroot_default_settings_json >"$defaults_file"

  if [[ ! -f "$CHROOT_SETTINGS_FILE" ]]; then
    cat "$defaults_file" >"$tmp"
    mv -f -- "$tmp" "$CHROOT_SETTINGS_FILE"
    rm -f -- "$defaults_file"
    return 0
  fi

  "$CHROOT_PYTHON_BIN" - "$CHROOT_SETTINGS_FILE" "$defaults_file" >"$tmp" <<'PY'
import json
import sys
p = sys.argv[1]
defaults_path = sys.argv[2]
with open(defaults_path, 'r', encoding='utf-8') as fh:
    defaults = json.load(fh)
try:
    with open(p, 'r', encoding='utf-8') as fh:
        data = json.load(fh)
    if not isinstance(data, dict):
        data = {}
except Exception:
    data = {}
for k, v in defaults.items():
    if k not in data:
        data[k] = v
print(json.dumps(data, indent=2, sort_keys=True))
PY

  rm -f -- "$defaults_file"
  mv -f -- "$tmp" "$CHROOT_SETTINGS_FILE"
}

