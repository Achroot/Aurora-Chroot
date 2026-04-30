chroot_device_timezone_name() {
  local override="${CHROOT_DEVICE_TIMEZONE:-}"
  local cached="${CHROOT_DEVICE_TIMEZONE_CACHE:-}"
  local prop_file="/dev/__properties__/u:object_r:timezone_prop:s0"
  local getprop_bin=""
  local detected="UTC"
  local tz_pattern='^[A-Za-z0-9._+-]+(/[A-Za-z0-9._+-]+)+$'

  if [[ -n "$override" && "$override" =~ $tz_pattern ]]; then
    printf '%s\n' "$override"
    return 0
  fi

  if [[ -n "$cached" ]]; then
    printf '%s\n' "$cached"
    return 0
  fi

  if [[ -n "${TZ:-}" && "${TZ:-}" =~ $tz_pattern ]]; then
    detected="$TZ"
  fi

  if [[ ! "$detected" =~ $tz_pattern ]]; then
    if [[ -x "${CHROOT_SYSTEM_BIN_DEFAULT:-/system/bin}/getprop" ]]; then
      getprop_bin="${CHROOT_SYSTEM_BIN_DEFAULT:-/system/bin}/getprop"
    elif chroot_cmd_exists getprop; then
      getprop_bin="$(command -v getprop 2>/dev/null || true)"
    fi
    if [[ -n "$getprop_bin" ]]; then
      detected="$("$getprop_bin" persist.sys.timezone 2>/dev/null | tr -d '\r\n' || true)"
    fi
  fi

  if [[ ! "$detected" =~ $tz_pattern && -r "$prop_file" ]]; then
    chroot_require_python
    detected="$("$CHROOT_PYTHON_BIN" - "$prop_file" <<'PY'
import re
import sys

path = sys.argv[1]
value = ""

try:
    with open(path, "rb") as fh:
        data = fh.read(256)
    if data[8:12] == b"PROP":
        value = data[0x94:0x94 + 128].split(b"\x00", 1)[0].decode("utf-8", "ignore").strip()
except Exception:
    value = ""

if not re.match(r"^[A-Za-z0-9._+-]+(?:/[A-Za-z0-9._+-]+)+$", value or ""):
    value = "UTC"

print(value)
PY
)"
  fi

  if [[ ! "$detected" =~ $tz_pattern ]]; then
    detected="UTC"
  fi

  CHROOT_DEVICE_TIMEZONE_CACHE="$detected"
  printf '%s\n' "$detected"
}
