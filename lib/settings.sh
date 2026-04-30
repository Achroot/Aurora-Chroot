#!/usr/bin/env bash

chroot_settings_schema_json() {
  cat <<'JSON'
{
  "keys": [
    {
      "key": "termux_home_bind",
      "type": "bool",
      "default": false,
      "status": "active",
      "description": "Bind Termux home into each mounted distro."
    },
    {
      "key": "android_storage_bind",
      "type": "bool",
      "default": false,
      "status": "active",
      "description": "Bind /storage into each mounted distro."
    },
    {
      "key": "data_bind",
      "type": "bool",
      "default": false,
      "status": "active",
      "description": "Bind /data into each mounted distro."
    },
    {
      "key": "android_full_bind",
      "type": "bool",
      "default": false,
      "status": "active",
      "description": "Bind core Android partitions (/apex, /system, /vendor, /product, /system_ext, /odm), detected *_dlkm mounts, and common vendor top-level partitions for deeper Android access."
    },
    {
      "key": "x11",
      "type": "bool",
      "default": false,
      "status": "active",
      "description": "Enable Termux-X11 socket bind and DISPLAY=:0 injection for GUI apps."
    },
    {
      "key": "x11_dpi",
      "type": "int",
      "min": 96,
      "max": 480,
      "default": 160,
      "status": "active",
      "description": "Preferred X11 DPI exported to GUI sessions as QT_FONT_DPI."
    },
    {
      "key": "download_retries",
      "type": "int",
      "min": 1,
      "max": 10,
      "default": 3,
      "status": "active",
      "description": "Retry count for manifest and rootfs downloads."
    },
    {
      "key": "download_timeout_sec",
      "type": "int",
      "min": 5,
      "max": 300,
      "default": 20,
      "status": "active",
      "description": "Per-request network timeout in seconds."
    },
    {
      "key": "log_retention_days",
      "type": "int",
      "min": 1,
      "max": 365,
      "default": 14,
      "status": "active",
      "description": "Delete unified Aurora log files older than this many days."
    },
    {
      "key": "tor_rotation_min",
      "type": "int",
      "min": 1,
      "max": 120,
      "default": 5,
      "status": "active",
      "description": "Approximate Tor circuit rotation window in minutes for new connections (maps to MaxCircuitDirtiness; does not forcibly switch active connections)."
    },
    {
      "key": "tor_bootstrap_timeout_sec",
      "type": "int",
      "min": 10,
      "max": 600,
      "default": 45,
      "status": "active",
      "description": "How long Tor enable waits for bootstrap completion before failing and cleaning up."
    }
  ]
}
JSON
}

chroot_settings_defaults_json() {
  chroot_require_python
  local schema_file
  schema_file="$CHROOT_TMP_DIR/settings-schema.$$.json"
  chroot_settings_schema_json >"$schema_file"
  "$CHROOT_PYTHON_BIN" - "$schema_file" <<'PY'
import json
import sys

schema_path = sys.argv[1]
with open(schema_path, "r", encoding="utf-8") as fh:
    doc = json.load(fh)

defaults = {}
for spec in doc.get("keys", []):
    key = spec.get("key")
    if not key:
        continue
    defaults[key] = spec.get("default")
print(json.dumps(defaults, indent=2, sort_keys=True))
PY
  rm -f -- "$schema_file"
}

chroot_settings_snapshot_json() {
  chroot_require_python
  local schema_file
  schema_file="$CHROOT_TMP_DIR/settings-schema.$$.json"
  chroot_settings_schema_json >"$schema_file"

  "$CHROOT_PYTHON_BIN" - "$CHROOT_SETTINGS_FILE" "$schema_file" <<'PY'
import json
import sys

settings_path, schema_path = sys.argv[1:3]

with open(schema_path, "r", encoding="utf-8") as fh:
    schema_doc = json.load(fh)

try:
    with open(settings_path, "r", encoding="utf-8") as fh:
        settings_data = json.load(fh)
    if not isinstance(settings_data, dict):
        settings_data = {}
except Exception:
    settings_data = {}


def bool_parse(value):
    if isinstance(value, bool):
        return value
    if isinstance(value, int):
        return bool(value)
    if isinstance(value, str):
        lowered = value.strip().lower()
        if lowered in {"true", "1", "yes", "on"}:
            return True
        if lowered in {"false", "0", "no", "off"}:
            return False
    raise ValueError("invalid bool")


def allowed_text(spec):
    stype = spec.get("type")
    if stype == "bool":
        return "true|false"
    if stype == "int":
        min_v = spec.get("min")
        max_v = spec.get("max")
        if min_v is not None and max_v is not None:
            return f"{min_v}..{max_v}"
        if min_v is not None:
            return f">={min_v}"
        if max_v is not None:
            return f"<={max_v}"
        return "integer"
    if stype == "enum":
        return "|".join(str(x) for x in spec.get("choices", []))
    return ""


def normalize_for_type(value, spec):
    stype = spec.get("type")
    if stype == "bool":
        parsed = bool_parse(value)
        return parsed, "true" if parsed else "false", True
    if stype == "int":
        try:
            if isinstance(value, bool):
                raise ValueError("bool is not int")
            parsed = int(str(value).strip())
        except Exception:
            return value, str(value), False
        min_v = spec.get("min")
        max_v = spec.get("max")
        if min_v is not None and parsed < int(min_v):
            return parsed, str(parsed), False
        if max_v is not None and parsed > int(max_v):
            return parsed, str(parsed), False
        return parsed, str(parsed), True
    if stype == "enum":
        choices = [str(x) for x in spec.get("choices", [])]
        parsed = str(value)
        return parsed, parsed, parsed in choices
    parsed = value
    return parsed, str(parsed), True


rows = []
for spec in schema_doc.get("keys", []):
    key = spec.get("key")
    if not key:
        continue
    default = spec.get("default")
    current = settings_data.get(key, default)

    current_native, current_text, current_valid = normalize_for_type(current, spec)
    default_native, default_text, _ = normalize_for_type(default, spec)

    rows.append(
        {
            "key": key,
            "type": spec.get("type"),
            "status": spec.get("status", "active"),
            "description": spec.get("description", ""),
            "allowed_text": allowed_text(spec),
            "choices": [str(x) for x in spec.get("choices", [])],
            "min": spec.get("min"),
            "max": spec.get("max"),
            "default": default_native,
            "default_text": default_text,
            "current": current_native,
            "current_text": current_text,
            "current_valid": bool(current_valid),
        }
    )

print(json.dumps({"settings": rows}, indent=2))
PY

  rm -f -- "$schema_file"
}

chroot_settings_render_width() {
  local cols="${COLUMNS:-}"
  if [[ ! "$cols" =~ ^[0-9]+$ ]] || (( cols <= 0 )); then
    if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
      cols="$(tput cols 2>/dev/null || true)"
    fi
  fi
  if [[ ! "$cols" =~ ^[0-9]+$ ]] || (( cols <= 0 )); then
    cols=96
  fi
  if (( cols > 8 )); then
    cols=$((cols - 6))
  fi
  if (( cols < 54 )); then
    cols=54
  elif (( cols > 96 )); then
    cols=96
  fi
  printf '%s\n' "$cols"
}

chroot_cmd_settings_show() {
  local snapshot_json width
  snapshot_json="$(chroot_settings_snapshot_json)"
  width="$(chroot_settings_render_width)"
  "$CHROOT_PYTHON_BIN" - "$snapshot_json" "$width" <<'PY'
import json
import sys
import textwrap

try:
    data = json.loads(sys.argv[1])
except Exception:
    print("failed to read settings")
    sys.exit(1)

try:
    render_width = int(sys.argv[2])
except Exception:
    render_width = 96
render_width = max(54, min(96, render_width))

rows = data.get("settings", [])
if not rows:
    print("No settings found")
    sys.exit(0)


def wrap_words(text, width):
    text = str(text or "")
    width = max(1, int(width))
    wrapped = textwrap.wrap(
        text,
        width=width,
        break_long_words=True,
        break_on_hyphens=False,
        replace_whitespace=False,
    )
    return wrapped or [""]


def wrap_field(label, value, width):
    prefix = f"{label}: "
    available = max(12, width - len(prefix))
    chunks = wrap_words(value, available)
    lines = [prefix + chunks[0]]
    indent = " " * len(prefix)
    for chunk in chunks[1:]:
        lines.append(indent + chunk)
    return lines


def render_card(lines, width):
    max_width = max(20, width - 4)
    normalized = []
    for line in lines:
        text = str(line or "")
        if len(text) <= max_width:
            normalized.append(text)
        else:
            normalized.extend(wrap_words(text, max_width))
    if not normalized:
        normalized = [""]
    inner_width = max(20, min(max(len(line) for line in normalized), max_width))
    border = "+" + ("-" * (inner_width + 2)) + "+"
    rendered = [border]
    for line in normalized:
        rendered.append(f"| {line.ljust(inner_width)} |")
    rendered.append(border)
    return rendered


out = []
out.extend(
    render_card(
        [
            "Aurora settings",
            "current values, allowed values, status, and descriptions",
        ],
        render_width,
    )
)

invalid_seen = False
for row in rows:
    key = str(row.get("key", ""))
    current = str(row.get("current_text", ""))
    if not row.get("current_valid", True):
        current = f"{current}*"
        invalid_seen = True
    allowed = str(row.get("allowed_text", ""))
    status = str(row.get("status", ""))
    desc = str(row.get("description", ""))
    card_lines = [key]
    card_lines.extend(wrap_field("current", current, render_width - 4))
    card_lines.extend(wrap_field("allowed", allowed, render_width - 4))
    card_lines.extend(wrap_field("status", status, render_width - 4))
    card_lines.extend(wrap_field("description", desc, render_width - 4))
    card_lines.extend(wrap_field("command", f"aurora settings set {key}", render_width - 4))
    out.append("")
    out.extend(render_card(card_lines, render_width))

if invalid_seen:
    out.append("")
    out.append("* current value is outside allowed range/choices")

print("\n".join(out))
PY
}

chroot_cmd_settings_json() {
  chroot_settings_snapshot_json
}

chroot_settings_normalize_value() {
  local key="$1"
  local value="$2"
  chroot_require_python

  local schema_file
  schema_file="$CHROOT_TMP_DIR/settings-schema.$$.json"
  chroot_settings_schema_json >"$schema_file"

  "$CHROOT_PYTHON_BIN" - "$schema_file" "$key" "$value" <<'PY'
import json
import sys

schema_path, key, raw_value = sys.argv[1:4]
with open(schema_path, "r", encoding="utf-8") as fh:
    schema_doc = json.load(fh)

spec = None
for row in schema_doc.get("keys", []):
    if row.get("key") == key:
        spec = row
        break

if spec is None:
    print(f"unknown setting key: {key}", file=sys.stderr)
    sys.exit(2)

stype = spec.get("type")

if stype == "bool":
    lowered = raw_value.strip().lower()
    if lowered in {"true", "1", "yes", "on"}:
        print("true")
        sys.exit(0)
    if lowered in {"false", "0", "no", "off"}:
        print("false")
        sys.exit(0)
    print(f"invalid value for {key}; allowed: true|false", file=sys.stderr)
    sys.exit(1)

if stype == "int":
    try:
        parsed = int(raw_value.strip())
    except Exception:
        print(f"invalid value for {key}; allowed: integer", file=sys.stderr)
        sys.exit(1)
    min_v = spec.get("min")
    max_v = spec.get("max")
    if min_v is not None and parsed < int(min_v):
        print(f"invalid value for {key}; allowed range: {min_v}..{max_v}", file=sys.stderr)
        sys.exit(1)
    if max_v is not None and parsed > int(max_v):
        print(f"invalid value for {key}; allowed range: {min_v}..{max_v}", file=sys.stderr)
        sys.exit(1)
    print(str(parsed))
    sys.exit(0)

if stype == "enum":
    choices = [str(x) for x in spec.get("choices", [])]
    parsed = raw_value.strip()
    if parsed not in choices:
        print(f"invalid value for {key}; allowed: {'|'.join(choices)}", file=sys.stderr)
        sys.exit(1)
    print(parsed)
    sys.exit(0)

print(raw_value)
PY

  local rc=$?
  rm -f -- "$schema_file"
  return "$rc"
}

chroot_cmd_settings() {
  local sub="${1:-show}"

  case "$sub" in
    show|list)
      chroot_cmd_settings_show
      ;;
    --json)
      chroot_cmd_settings_json
      ;;
    set)
      shift || true
      local key="${1:-}"
      local value="${2:-}"
      [[ -n "$key" && -n "$value" ]] || chroot_die "usage: bash path/to/chroot settings set <key> <value>"

      local normalized
      if ! normalized="$(chroot_settings_normalize_value "$key" "$value")"; then
        chroot_die "settings update failed"
      fi

      chroot_setting_set "$key" "$normalized"
      if [[ "$key" == "x11" && "$normalized" == "true" ]]; then
        if chroot_x11_enable_display0 18; then
          chroot_info "x11 display :0 is ready"
        else
          chroot_warn "x11 is enabled but display :0 is not ready yet; open Termux:X11 and retry your GUI command"
        fi
      fi
      chroot_info "set $key=$normalized"
      ;;
    *)
      chroot_die "usage: bash path/to/chroot settings [show|set <key> <value>|--json]"
      ;;
  esac
}
