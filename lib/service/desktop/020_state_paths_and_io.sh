chroot_service_desktop_state_dir() {
  local distro="$1"
  printf '%s/desktop' "$(chroot_distro_state_dir "$distro")"
}

chroot_service_desktop_config_file() {
  local distro="$1"
  printf '%s/config.json' "$(chroot_service_desktop_state_dir "$distro")"
}

chroot_service_desktop_runtime_log_file() {
  local distro="$1"
  printf '%s/runtime.log' "$(chroot_service_desktop_state_dir "$distro")"
}

chroot_service_desktop_rootfs_config_dir() {
  local distro="$1"
  printf '%s/etc/aurora-desktop' "$(chroot_distro_rootfs_dir "$distro")"
}

chroot_service_desktop_rootfs_profile_env_file() {
  local distro="$1"
  printf '%s/profile.env' "$(chroot_service_desktop_rootfs_config_dir "$distro")"
}

chroot_service_desktop_rootfs_profile_json_file() {
  local distro="$1"
  printf '%s/profile.json' "$(chroot_service_desktop_rootfs_config_dir "$distro")"
}

chroot_service_desktop_rootfs_launcher_file() {
  local distro="$1"
  local launcher_rel
  launcher_rel="${CHROOT_SERVICE_DESKTOP_COMMAND#/}"
  printf '%s/%s' "$(chroot_distro_rootfs_dir "$distro")" "$launcher_rel"
}

chroot_service_desktop_runtime_log_clear() {
  local distro="$1"
  local log_file
  log_file="$(chroot_service_desktop_runtime_log_file "$distro")"
  mkdir -p "$(dirname "$log_file")"
  rm -f -- "$log_file"
}

chroot_service_desktop_runtime_log_excerpt() {
  local distro="$1"
  local log_file
  log_file="$(chroot_service_desktop_runtime_log_file "$distro")"
  [[ -s "$log_file" ]] || return 1

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$log_file" <<'PY'
import sys

path = sys.argv[1]

try:
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        lines = fh.readlines()[-40:]
except Exception:
    sys.exit(1)

for raw_line in reversed(lines):
    line = " ".join(raw_line.replace("\t", " ").split())
    if not line:
        continue
    print(line[:240])
    sys.exit(0)

sys.exit(1)
PY
}

chroot_service_desktop_config_exists() {
  local distro="$1"
  [[ -f "$(chroot_service_desktop_config_file "$distro")" ]]
}

chroot_service_desktop_config_get() {
  local distro="$1"
  local key="$2"
  local config_file
  config_file="$(chroot_service_desktop_config_file "$distro")"
  [[ -f "$config_file" ]] || return 1

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$config_file" "$key" <<'PY'
import json
import sys

config_path, key = sys.argv[1:3]
with open(config_path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
value = data.get(key)
if isinstance(value, bool):
    print("true" if value else "false")
elif value is None:
    print("")
else:
    print(value)
PY
}

chroot_service_desktop_config_set_fields() {
  local distro="$1"
  shift || true
  (( $# > 0 )) || chroot_die "desktop config fields are required"
  (( $# % 2 == 0 )) || chroot_die "desktop config update requires key/value pairs"

  local config_dir config_file tmp
  config_dir="$(chroot_service_desktop_state_dir "$distro")"
  config_file="$(chroot_service_desktop_config_file "$distro")"
  tmp="$config_file.tmp"

  mkdir -p "$config_dir"

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$config_file" "$tmp" "$CHROOT_SERVICE_DESKTOP_SCHEMA_VERSION" "$CHROOT_SERVICE_DESKTOP_SERVICE_NAME" "$@" <<'PY'
import json
import os
import sys

config_path, tmp_path, schema_version, service_name, *pairs = sys.argv[1:]

data = {
    "schema_version": int(schema_version),
    "service_name": service_name,
}

if os.path.exists(config_path):
    try:
        with open(config_path, "r", encoding="utf-8") as fh:
            loaded = json.load(fh)
        if isinstance(loaded, dict):
            data.update(loaded)
    except Exception:
        pass

for idx in range(0, len(pairs), 2):
    key = pairs[idx]
    value = pairs[idx + 1]
    if value in {"true", "false"}:
        parsed = value == "true"
    elif value.isdigit():
        parsed = int(value)
    else:
        parsed = value
    data[key] = parsed

data.setdefault("schema_version", int(schema_version))
data.setdefault("service_name", service_name)

with open(tmp_path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, sort_keys=True)
PY

  mv -f -- "$tmp" "$config_file"
}

chroot_service_desktop_config_remove() {
  local distro="$1"
  local config_file config_dir runtime_log
  config_file="$(chroot_service_desktop_config_file "$distro")"
  config_dir="$(chroot_service_desktop_state_dir "$distro")"
  runtime_log="$(chroot_service_desktop_runtime_log_file "$distro")"
  rm -f -- "$config_file"
  rm -f -- "$runtime_log"
  rmdir "$config_dir" >/dev/null 2>&1 || true
}
