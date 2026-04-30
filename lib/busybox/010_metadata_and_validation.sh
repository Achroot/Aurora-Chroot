#!/usr/bin/env bash

chroot_busybox_sanitize_line() {
  local value="${1:-}"
  value="${value//$'\r'/ }"
  value="${value//$'\n'/ }"
  value="${value//$'\t'/ }"
  printf '%s\n' "$value"
}

chroot_busybox_binary_version_line() {
  local bin="$1"
  "$bin" --help 2>&1 | head -n 1 | tr -d '\r' || true
}

chroot_busybox_sha256_file() {
  local file="$1"
  if [[ -z "${CHROOT_SHA256_BIN:-}" ]]; then
    CHROOT_SHA256_BIN="$(command -v sha256sum 2>/dev/null || true)"
  fi
  [[ -n "$CHROOT_SHA256_BIN" ]] || chroot_die "sha256sum is required to register BusyBox"
  chroot_sha256_file "$file"
}

chroot_busybox_validate_binary_tsv() {
  local bin="$1"
  local ok=0
  local tool applet

  if [[ ! -e "$bin" ]]; then
    printf '%s\t%s\t%s\n' "__binary__" "fail" "file does not exist"
    return 1
  fi
  if [[ ! -f "$bin" ]]; then
    printf '%s\t%s\t%s\n' "__binary__" "fail" "path is not a regular file"
    return 1
  fi
  if [[ ! -x "$bin" ]]; then
    printf '%s\t%s\t%s\n' "__binary__" "fail" "file is not executable; Aurora cannot use a non-executable BusyBox binary"
    return 1
  fi
  if chroot_detect_command_runs "$bin" --help; then
    printf '%s\t%s\t%s\n' "__binary__" "pass" "binary runs"
  else
    printf '%s\t%s\t%s\n' "__binary__" "fail" "binary could not run --help"
    return 1
  fi

  while IFS= read -r tool; do
    [[ -n "$tool" ]] || continue
    applet="$(chroot_busybox_tool_busybox_applet "$tool" || true)"
    applet="${applet:-$tool}"
    if "$bin" "$applet" --help >/dev/null 2>&1; then
      printf '%s\t%s\t%s\n' "$tool" "pass" "applet '$applet' is available"
    else
      printf '%s\t%s\t%s\n' "$tool" "fail" "applet '$applet' failed validation"
      ok=1
    fi
  done < <(chroot_busybox_required_tool_ids)

  return "$ok"
}

chroot_busybox_validate_applet_dir_tsv() {
  local dir="$1"
  local ok=0
  local tool tool_path

  if [[ ! -d "$dir" ]]; then
    printf '%s\t%s\t%s\n' "__directory__" "fail" "path is not a directory"
    return 1
  fi
  printf '%s\t%s\t%s\n' "__directory__" "pass" "directory exists"

  while IFS= read -r tool; do
    [[ -n "$tool" ]] || continue
    tool_path="$dir/$tool"
    if [[ ! -e "$tool_path" ]]; then
      printf '%s\t%s\t%s\n' "$tool" "fail" "missing required applet path: $tool_path"
      ok=1
      continue
    fi
    if [[ ! -x "$tool_path" ]]; then
      printf '%s\t%s\t%s\n' "$tool" "fail" "required applet is not executable: $tool_path"
      ok=1
      continue
    fi
    if "$tool_path" --help >/dev/null 2>&1; then
      printf '%s\t%s\t%s\n' "$tool" "pass" "managed applet runs"
    else
      printf '%s\t%s\t%s\n' "$tool" "fail" "applet failed --help probe: $tool_path"
      ok=1
    fi
  done < <(chroot_busybox_required_tool_ids)

  return "$ok"
}

chroot_busybox_validation_failed_lines() {
  awk -F'\t' '$2 != "pass" {print "  - " $1 ": " $3}'
}

chroot_busybox_metadata_json() {
  local cache
  cache="$(chroot_busybox_cache_file)"
  if [[ -r "$cache" ]]; then
    cat "$cache"
  else
    printf '{}\n'
  fi
}

chroot_busybox_metadata_field() {
  local field="$1"
  local cache
  cache="$(chroot_busybox_cache_file)"
  [[ -r "$cache" ]] || return 1
  chroot_detect_python
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$cache" "$field" <<'PY'
import json
import sys

path, field = sys.argv[1:3]
try:
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    raise SystemExit(1)

value = data
for part in field.split("."):
    if isinstance(value, dict):
        value = value.get(part, "")
    else:
        value = ""
if isinstance(value, (dict, list)):
    print(json.dumps(value, sort_keys=True))
elif value is None:
    print("")
else:
    print(str(value))
PY
}

chroot_busybox_metadata_summary_tsv() {
  local cache
  cache="$(chroot_busybox_cache_file)"
  [[ -r "$cache" ]] || return 1
  chroot_detect_python
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$cache" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    raise SystemExit(1)

fields = [
    "source_type",
    "original_path",
    "active_binary_path",
    "active_applets_dir",
    "fetch_url",
    "repository_binary_name",
    "detected_architecture",
    "version_line",
    "file_size",
    "sha256",
    "validation_status",
    "validation_time",
]
print("|".join(str(data.get(field, "") or "").replace("|", " ").replace("\t", " ").replace("\n", " ") for field in fields))
PY
}

chroot_busybox_metadata_tool_path() {
  local tool="$1"
  local cache
  cache="$(chroot_busybox_cache_file)"
  [[ -r "$cache" ]] || return 1
  chroot_detect_python
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$cache" "$tool" <<'PY'
import json
import sys

path, tool = sys.argv[1:3]
try:
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    raise SystemExit(1)
tool_paths = data.get("tool_paths", {})
value = tool_paths.get(tool, "")
if value:
    print(value)
PY
}

chroot_busybox_write_metadata() {
  local source_type="$1"
  local original_path="$2"
  local active_binary="$3"
  local active_applets_dir="$4"
  local fetch_url="$5"
  local repo_binary="$6"
  local detected_arch="$7"
  local version_line="$8"
  local file_size="$9"
  local sha256="${10}"
  local validation_status="${11}"
  local validation_tsv_file="${12}"
  local tool_paths_tsv_file="${13:-}"
  local cache tmp

  chroot_detect_python
  chroot_require_python
  cache="$(chroot_busybox_cache_file)"
  tmp="$cache.tmp.$$"
  CHROOT_BUSYBOX_META_SCHEMA="$CHROOT_BUSYBOX_CACHE_SCHEMA" \
  CHROOT_BUSYBOX_META_SOURCE_TYPE="$source_type" \
  CHROOT_BUSYBOX_META_ORIGINAL_PATH="$original_path" \
  CHROOT_BUSYBOX_META_ACTIVE_BINARY="$active_binary" \
  CHROOT_BUSYBOX_META_ACTIVE_APPLETS="$active_applets_dir" \
  CHROOT_BUSYBOX_META_FETCH_URL="$fetch_url" \
  CHROOT_BUSYBOX_META_REPO_BINARY="$repo_binary" \
  CHROOT_BUSYBOX_META_ARCH="$detected_arch" \
  CHROOT_BUSYBOX_META_VERSION_LINE="$version_line" \
  CHROOT_BUSYBOX_META_FILE_SIZE="$file_size" \
  CHROOT_BUSYBOX_META_SHA256="$sha256" \
  CHROOT_BUSYBOX_META_VALIDATION_STATUS="$validation_status" \
  CHROOT_BUSYBOX_META_VALIDATION_TIME="$(chroot_busybox_now)" \
  "$CHROOT_PYTHON_BIN" - "$validation_tsv_file" "${tool_paths_tsv_file:-}" >"$tmp" <<'PY'
import json
import os
import sys

validation_file = sys.argv[1]
tool_paths_file = sys.argv[2] if len(sys.argv) > 2 else ""

applet_results = {}
try:
    with open(validation_file, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line:
                continue
            parts = line.split("\t", 2)
            while len(parts) < 3:
                parts.append("")
            tool, status, detail = parts
            applet_results[tool] = {"status": status, "detail": detail}
except Exception:
    applet_results = {}

tool_paths = {}
if tool_paths_file:
    try:
        with open(tool_paths_file, "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.rstrip("\n")
                if not line:
                    continue
                parts = line.split("\t", 1)
                if len(parts) == 2:
                    tool_paths[parts[0]] = parts[1]
    except Exception:
        tool_paths = {}

required_tools = [tool for tool in applet_results if not tool.startswith("__")]
doc = {
    "schema_version": int(os.environ.get("CHROOT_BUSYBOX_META_SCHEMA", "1") or "1"),
    "source_type": os.environ.get("CHROOT_BUSYBOX_META_SOURCE_TYPE", ""),
    "original_path": os.environ.get("CHROOT_BUSYBOX_META_ORIGINAL_PATH", ""),
    "active_binary_path": os.environ.get("CHROOT_BUSYBOX_META_ACTIVE_BINARY", ""),
    "active_applets_dir": os.environ.get("CHROOT_BUSYBOX_META_ACTIVE_APPLETS", ""),
    "tool_paths": tool_paths,
    "fetch_url": os.environ.get("CHROOT_BUSYBOX_META_FETCH_URL", ""),
    "repository_binary_name": os.environ.get("CHROOT_BUSYBOX_META_REPO_BINARY", ""),
    "detected_architecture": os.environ.get("CHROOT_BUSYBOX_META_ARCH", ""),
    "version_line": os.environ.get("CHROOT_BUSYBOX_META_VERSION_LINE", ""),
    "file_size": int(os.environ.get("CHROOT_BUSYBOX_META_FILE_SIZE", "0") or "0"),
    "sha256": os.environ.get("CHROOT_BUSYBOX_META_SHA256", ""),
    "validation_time": os.environ.get("CHROOT_BUSYBOX_META_VALIDATION_TIME", ""),
    "validation_status": os.environ.get("CHROOT_BUSYBOX_META_VALIDATION_STATUS", ""),
    "applet_validation_results": applet_results,
    "required_tools": required_tools,
}
print(json.dumps(doc, indent=2, sort_keys=True))
PY
  mv -f -- "$tmp" "$cache"
}

chroot_managed_busybox_source_type() {
  chroot_busybox_metadata_field source_type 2>/dev/null || true
}

chroot_managed_busybox_supports_tool() {
  local tool="$1"
  local source_type active_binary active_applets_dir tool_path
  source_type="$(chroot_managed_busybox_source_type)"
  [[ -n "$source_type" ]] || return 1

  case "$source_type" in
    fetch|path_file)
      active_binary="$(chroot_busybox_metadata_field active_binary_path 2>/dev/null || true)"
      [[ -n "$active_binary" && -x "$active_binary" ]] || return 1
      "$active_binary" "$tool" --help >/dev/null 2>&1
      ;;
    path_dir)
      tool_path="$(chroot_busybox_metadata_tool_path "$tool" 2>/dev/null || true)"
      if [[ -z "$tool_path" ]]; then
        active_applets_dir="$(chroot_busybox_metadata_field active_applets_dir 2>/dev/null || true)"
        tool_path="$active_applets_dir/$tool"
      fi
      [[ -n "$tool_path" && -x "$tool_path" ]] || return 1
      "$tool_path" --help >/dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

chroot_managed_busybox_tool_backend_parts_tsv() {
  local tool="$1"
  local source_type active_binary active_applets_dir tool_path
  source_type="$(chroot_managed_busybox_source_type)"
  [[ -n "$source_type" ]] || return 1

  case "$source_type" in
    fetch|path_file)
      active_binary="$(chroot_busybox_metadata_field active_binary_path 2>/dev/null || true)"
      if [[ -n "$active_binary" && -x "$active_binary" ]] && "$active_binary" "$tool" --help >/dev/null 2>&1; then
        printf '%s\t%s\n' "$active_binary" "$tool"
        return 0
      fi
      ;;
    path_dir)
      tool_path="$(chroot_busybox_metadata_tool_path "$tool" 2>/dev/null || true)"
      if [[ -z "$tool_path" ]]; then
        active_applets_dir="$(chroot_busybox_metadata_field active_applets_dir 2>/dev/null || true)"
        tool_path="$active_applets_dir/$tool"
      fi
      if [[ -n "$tool_path" && -x "$tool_path" ]] && "$tool_path" --help >/dev/null 2>&1; then
        printf '%s\t%s\n' "$tool_path" ""
        return 0
      fi
      ;;
  esac
  return 1
}

chroot_busybox_active_validation_tsv() {
  local source_type active_binary active_applets_dir
  source_type="$(chroot_managed_busybox_source_type)"
  case "$source_type" in
    fetch|path_file)
      active_binary="$(chroot_busybox_metadata_field active_binary_path 2>/dev/null || true)"
      chroot_busybox_validate_binary_tsv "$active_binary"
      ;;
    path_dir)
      active_applets_dir="$(chroot_busybox_metadata_field active_applets_dir 2>/dev/null || true)"
      chroot_busybox_validate_applet_dir_tsv "$active_applets_dir"
      ;;
    *)
      printf '%s\t%s\t%s\n' "__configured__" "fail" "no managed BusyBox configured"
      return 1
      ;;
  esac
}
