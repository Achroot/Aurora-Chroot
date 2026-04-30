#!/usr/bin/env bash

if ! declare -p CHROOT_LOG_PENDING_ERROR_DETAILS >/dev/null 2>&1; then
  declare -ag CHROOT_LOG_PENDING_ERROR_DETAILS=()
fi
if ! declare -p CHROOT_LOG_INTERNAL_STACK >/dev/null 2>&1; then
  declare -ag CHROOT_LOG_INTERNAL_STACK=()
fi

chroot_log_skip_enabled() {
  case "${CHROOT_LOG_SKIP:-0}" in
    1|true|TRUE|yes|YES|on|ON)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

chroot_log_source_value() {
  local source="${CHROOT_LOG_SOURCE:-cli}"
  case "$source" in
    cli|tui|internal) ;;
    *) source="cli" ;;
  esac
  printf '%s\n' "$source"
}

chroot_log_sanitize_key() {
  local key="${1:-detail}"
  key="${key//$'\r'/}"
  key="${key//$'\n'/}"
  key="${key//$'\t'/}"
  key="${key,,}"
  key="$(printf '%s' "$key" | tr -cs 'a-z0-9._-' '_')"
  key="${key#_}"
  key="${key%_}"
  [[ -n "$key" ]] || key="detail"
  printf '%s\n' "$key"
}

chroot_log_sanitize_value() {
  local value="${1:-}"
  value="${value//$'\r'/ }"
  value="${value//$'\n'/ }"
  value="${value//$'\t'/ }"
  value="$(printf '%s' "$value" | tr -s '[:space:]' ' ' | sed 's/^ *//; s/ *$//')"
  printf '%s\n' "$value"
}

chroot_log_join_args() {
  local delim="$1"
  shift || true

  local out=""
  local arg=""
  for arg in "$@"; do
    arg="$(chroot_log_sanitize_value "$arg")"
    if [[ -n "$out" ]]; then
      out+="$delim"
    fi
    out+="$arg"
  done
  printf '%s\n' "$out"
}

chroot_log_current_effective_source() {
  if (( ${#CHROOT_LOG_INTERNAL_STACK[@]} > 0 )); then
    printf 'internal\n'
    return 0
  fi
  printf '%s\n' "${CHROOT_LOG_SOURCE_EFFECTIVE:-$(chroot_log_source_value)}"
}

chroot_log_current_effective_action_path() {
  if (( ${#CHROOT_LOG_INTERNAL_STACK[@]} > 0 )); then
    local idx=$(( ${#CHROOT_LOG_INTERNAL_STACK[@]} - 1 ))
    local record="${CHROOT_LOG_INTERNAL_STACK[$idx]}"
    printf '%s\n' "${record%%$'\t'*}"
    return 0
  fi
  printf '%s\n' "${CHROOT_LOG_ACTION_PATH:-}"
}

chroot_log_current_effective_command_text() {
  if (( ${#CHROOT_LOG_INTERNAL_STACK[@]} > 0 )); then
    local idx=$(( ${#CHROOT_LOG_INTERNAL_STACK[@]} - 1 ))
    local record="${CHROOT_LOG_INTERNAL_STACK[$idx]}"
    record="${record#*$'\t'}"
    record="${record#*$'\t'}"
    printf '%s\n' "${record%%$'\t'*}"
    return 0
  fi
  printf '%s\n' "${CHROOT_LOG_COMMAND_TEXT:-}"
}

chroot_log_current_effective_distro() {
  if (( ${#CHROOT_LOG_INTERNAL_STACK[@]} > 0 )); then
    local idx=$(( ${#CHROOT_LOG_INTERNAL_STACK[@]} - 1 ))
    local record="${CHROOT_LOG_INTERNAL_STACK[$idx]}"
    record="${record#*$'\t'}"
    printf '%s\n' "${record%%$'\t'*}"
    return 0
  fi
  printf '%s\n' "${CHROOT_LOG_DISTRO:-}"
}

chroot_log_current_effective_family() {
  if (( ${#CHROOT_LOG_INTERNAL_STACK[@]} > 0 )); then
    local idx=$(( ${#CHROOT_LOG_INTERNAL_STACK[@]} - 1 ))
    local record="${CHROOT_LOG_INTERNAL_STACK[$idx]}"
    record="${record#*$'\t'}"
    record="${record#*$'\t'}"
    record="${record#*$'\t'}"
    record="${record#*$'\t'}"
    printf '%s\n' "${record%%$'\t'*}"
    return 0
  fi
  printf '%s\n' "${CHROOT_LOG_FAMILY:-core}"
}

chroot_log_current_effective_argv_text() {
  if (( ${#CHROOT_LOG_INTERNAL_STACK[@]} > 0 )); then
    local idx=$(( ${#CHROOT_LOG_INTERNAL_STACK[@]} - 1 ))
    local record="${CHROOT_LOG_INTERNAL_STACK[$idx]}"
    record="${record#*$'\t'}"
    record="${record#*$'\t'}"
    record="${record#*$'\t'}"
    printf '%s\n' "${record%%$'\t'*}"
    return 0
  fi
  printf '%s\n' "${CHROOT_LOG_ARGV_TEXT:-}"
}

chroot_log_build_command_text() {
  local prefix="${CHROOT_SCRIPT_NAME:-chroot}"
  if [[ $# -eq 0 ]]; then
    printf '%s\n' "$prefix"
    return 0
  fi
  printf '%s %s\n' "$prefix" "$(chroot_quote_cmd "$@")"
}

chroot_log_now_ms() {
  local now
  now="$(date -u +%s%3N 2>/dev/null || true)"
  if [[ "$now" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$now"
    return 0
  fi

  now="$(date -u +%s 2>/dev/null || echo 0)"
  if [[ "$now" =~ ^[0-9]+$ ]]; then
    printf '%s000\n' "$now"
    return 0
  fi

  printf '0\n'
}

chroot_log_make_invocation_id() {
  local ts rand_hex
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  rand_hex="$(printf '%04x' "$(( RANDOM % 65536 ))")"
  printf '%s-%s-%s\n' "$ts" "$$" "$rand_hex"
}

chroot_log_normalize_action_name() {
  local value
  value="$(chroot_log_sanitize_value "$1")"
  value="${value,,}"
  value="${value// /-}"
  value="$(printf '%s' "$value" | tr -cs 'a-z0-9._-' '-')"
  value="${value#-}"
  value="${value%-}"
  printf '%s\n' "$value"
}

chroot_log_infer_core_action() {
  chroot_commands_log_infer_core_action "$@"
}

chroot_log_infer_core_distro() {
  local cmd="${1:-}"
  shift || true

  case "$cmd" in
    distros)
      while [[ $# -gt 0 ]]; do
        if [[ "$1" == "--install" || "$1" == "--download" ]]; then
          shift || true
          if [[ -n "${1:-}" && "${1:-}" != -* ]]; then
            printf '%s\n' "$1"
          fi
          return 0
        fi
        shift || true
      done
      ;;
    install-local|login|exec)
      if [[ -n "${1:-}" && "${1:-}" != -* ]]; then
        printf '%s\n' "$1"
      fi
      ;;
    mount|unmount|backup|restore|remove)
      if [[ -n "${1:-}" && "${1:-}" != -* ]]; then
        printf '%s\n' "$1"
      fi
      ;;
    status)
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --distro)
            shift || true
            printf '%s\n' "${1:-}"
            return 0
            ;;
        esac
        shift || true
      done
      ;;
  esac
}

chroot_log_infer_scoped_action() {
  chroot_commands_log_infer_scoped_action "$@"
}

chroot_log_infer_zero_arg_action() {
  if [[ -n "${CHROOT_LOG_ZERO_ARG_ACTION:-}" ]]; then
    printf '%s\n' "${CHROOT_LOG_ZERO_ARG_ACTION:-help}"
    return 0
  fi

  if [[ ! -t 1 ]]; then
    printf 'help\n'
    return 0
  fi

  if [[ -n "${CHROOT_PYTHON_BIN:-}" && -x "${CHROOT_PYTHON_BIN:-}" ]]; then
    printf 'tui\n'
    return 0
  fi
  if command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
    printf 'tui\n'
    return 0
  fi

  printf 'help\n'
}

chroot_log_infer_invocation_context() {
  if [[ $# -eq 0 ]]; then
    printf 'core\t%s\t\n' "$(chroot_log_infer_zero_arg_action)"
    return 0
  fi

  local first="${1:-help}"
  local second="${2:-}"
  local family="core"
  local action=""
  local distro=""

  if [[ $# -ge 2 ]]; then
    case "$second" in
      service|sessions|tor)
        family="$second"
        distro="$first"
        action="$(chroot_log_infer_scoped_action "$family" "${3:-}" "${4:-}" "${5:-}")"
        printf '%s\t%s\t%s\n' "$family" "$action" "$distro"
        return 0
        ;;
    esac
  fi

  action="$(chroot_log_infer_core_action "$first" "${@:2}")"
  distro="$(chroot_log_infer_core_distro "$first" "${@:2}")"
  printf '%s\t%s\t%s\n' "$family" "$action" "$distro"
}

chroot_log_refresh_file_path() {
  CHROOT_LOG_FILE="$CHROOT_LOG_DIR/events-$(date -u +%Y%m%d).log"
}

chroot_log_current_file_path() {
  chroot_log_refresh_file_path
  printf '%s\n' "$CHROOT_LOG_FILE"
}

chroot_log_latest_file_path() {
  [[ -d "$CHROOT_LOG_DIR" ]] || return 1
  ls -1 "$CHROOT_LOG_DIR"/events-*.log 2>/dev/null | sort | tail -n 1 || true
}

chroot_log_pending_dir() {
  printf '%s/pending' "$CHROOT_LOG_DIR"
}

chroot_log_pending_file_path() {
  [[ -n "${CHROOT_LOG_INVOCATION_ID:-}" ]] || return 1
  printf '%s/%s.spool' "$(chroot_log_pending_dir)" "$CHROOT_LOG_INVOCATION_ID"
}

chroot_log_target_file_path() {
  if [[ -n "${CHROOT_LOG_GROUP_FILE:-}" ]]; then
    printf '%s\n' "$CHROOT_LOG_GROUP_FILE"
    return 0
  fi
  chroot_log_current_file_path
}

chroot_log_reset_context() {
  CHROOT_LOG_INVOCATION_ID=""
  CHROOT_LOG_EVENT_SEQ=0
  CHROOT_LOG_LAST_EVENT_ID=""
  CHROOT_LOG_SOURCE_EFFECTIVE=""
  CHROOT_LOG_RUNNER_EFFECTIVE=""
  CHROOT_LOG_COMMAND_TEXT=""
  CHROOT_LOG_ARGV_TEXT=""
  CHROOT_LOG_FAMILY=""
  CHROOT_LOG_ACTION_PATH=""
  CHROOT_LOG_DISTRO=""
  CHROOT_LOG_START_MS=""
  CHROOT_LOG_COMMAND_END_WRITTEN=0
  CHROOT_LOG_ACTIVE_INTERNAL_COMMAND=""
  CHROOT_LOG_GROUP_FILE=""
  CHROOT_LOG_IMPLICIT_CONTEXT=0
  CHROOT_LOG_INTERNAL_STACK=()
  chroot_log_clear_pending_error_details
}

chroot_log_detect_python_bin() {
  if [[ -n "${CHROOT_PYTHON_BIN:-}" && -x "${CHROOT_PYTHON_BIN:-}" ]]; then
    printf '%s\n' "$CHROOT_PYTHON_BIN"
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    command -v python3
    return 0
  fi
  if command -v python >/dev/null 2>&1; then
    command -v python
    return 0
  fi
  return 1
}

chroot_log_append_stream() {
  local log_file="$1"
  local python_bin=""
  local py_script=""
  python_bin="$(chroot_log_detect_python_bin 2>/dev/null || true)"

  if [[ -n "$python_bin" ]]; then
    py_script="$(cat <<'PY'
import os
import sys

try:
    import fcntl
except Exception:  # pragma: no cover - platform fallback
    fcntl = None

path = sys.argv[1]
payload = sys.stdin.buffer.read()
if not payload:
    raise SystemExit(0)

fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
try:
    if fcntl is not None:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX)
        except OSError:
            pass
    try:
        os.fchmod(fd, 0o600)
    except OSError:
        pass

    view = memoryview(payload)
    offset = 0
    while offset < len(view):
        written = os.write(fd, view[offset:])
        if written <= 0:
            raise OSError("short log write")
        offset += written
finally:
    os.close(fd)
PY
)"
    "$python_bin" -c "$py_script" "$log_file"
    return $?
  fi

  cat >>"$log_file"
  chmod 0600 "$log_file" >/dev/null 2>&1 || true
}

chroot_log_init() {
  chroot_log_skip_enabled && return 0
  [[ -n "$CHROOT_LOG_DIR" ]] || return 1
  mkdir -p "$CHROOT_LOG_DIR" >/dev/null 2>&1 || return 1
  mkdir -p "$(chroot_log_pending_dir)" >/dev/null 2>&1 || return 1
  chmod 0700 "$CHROOT_LOG_DIR" >/dev/null 2>&1 || true
  chmod 0700 "$(chroot_log_pending_dir)" >/dev/null 2>&1 || true
  chroot_log_refresh_file_path
  touch "$CHROOT_LOG_FILE" >/dev/null 2>&1 || return 1
  chmod 0600 "$CHROOT_LOG_FILE" >/dev/null 2>&1 || true
}

chroot_log_flush_invocation_group() {
  local invocation_id="${1:-${CHROOT_LOG_INVOCATION_ID:-}}"
  [[ -n "$invocation_id" ]] || return 0

  local spool_file target_file outer_sep inner_sep
  spool_file="$(chroot_log_pending_dir)/$invocation_id.spool"
  [[ -s "$spool_file" ]] || return 0

  target_file="$(chroot_log_target_file_path)"
  [[ -n "$target_file" ]] || return 1
  mkdir -p "$(dirname "$target_file")" >/dev/null 2>&1 || return 1

  outer_sep="================================================================"
  inner_sep="****************************************************************"

  if {
    printf '%s\n' "$outer_sep"
    awk -v entry_sep="$outer_sep" -v section_sep="$inner_sep" '
      $0 == entry_sep {
        print section_sep
        next
      }
      { print }
    ' "$spool_file"
    printf '%s\n\n\n\n' "$outer_sep"
  } | chroot_log_append_stream "$target_file"; then
    rm -f -- "$spool_file" >/dev/null 2>&1 || true
    return 0
  fi

  return 1
}

chroot_log_set_pending_error_detail() {
  local key
  key="$(chroot_log_sanitize_key "${1:-detail}")"
  CHROOT_LOG_PENDING_ERROR_DETAILS+=("$key"$'\t'"${2:-}")
}

chroot_log_clear_pending_error_details() {
  CHROOT_LOG_PENDING_ERROR_DETAILS=()
}

chroot_log_resolve_action_path() {
  local action_hint="${1:-}"
  local normalized=""
  local base="${CHROOT_LOG_ACTION_PATH:-}"
  local family="${CHROOT_LOG_FAMILY:-core}"

  if [[ -n "$action_hint" ]]; then
    normalized="$(chroot_log_normalize_action_name "$action_hint")"
  fi

  if [[ -z "$normalized" ]]; then
    if [[ -n "$base" ]]; then
      printf '%s\n' "$base"
    else
      printf '%s\n' "$family"
    fi
    return 0
  fi

  if [[ -n "$base" ]]; then
    if [[ "$normalized" == "$base" || "$normalized" == "$family" || "$base" == "$family.$normalized" ]]; then
      printf '%s\n' "$base"
      return 0
    fi
  fi

  if [[ "$family" != "core" && "$normalized" != *.* ]]; then
    printf '%s.%s\n' "$family" "$normalized"
    return 0
  fi

  printf '%s\n' "$normalized"
}

chroot_log_ensure_context() {
  local action_hint="${1:-}"
  [[ -n "${CHROOT_LOG_INVOCATION_ID:-}" ]] && return 0

  CHROOT_LOG_INVOCATION_ID="$(chroot_log_make_invocation_id)"
  CHROOT_LOG_EVENT_SEQ=0
  CHROOT_LOG_SOURCE_EFFECTIVE="internal"
  CHROOT_LOG_RUNNER_EFFECTIVE="$(chroot_resolve_self_path 2>/dev/null || printf '%s\n' "${CHROOT_INVOKED_PATH:-$CHROOT_SCRIPT_NAME}")"
  CHROOT_LOG_COMMAND_TEXT="$(chroot_log_build_command_text)"
  CHROOT_LOG_ARGV_TEXT=""
  CHROOT_LOG_FAMILY="core"
  CHROOT_LOG_ACTION_PATH="$(chroot_log_resolve_action_path "$action_hint")"
  CHROOT_LOG_DISTRO=""
  CHROOT_LOG_START_MS="$(chroot_log_now_ms)"
  CHROOT_LOG_GROUP_FILE="$(chroot_log_current_file_path)"
  CHROOT_LOG_COMMAND_END_WRITTEN=1
  CHROOT_LOG_IMPLICIT_CONTEXT=1
}

chroot_log_internal_parent_action() {
  if (( ${#CHROOT_LOG_INTERNAL_STACK[@]} > 0 )); then
    local idx=$(( ${#CHROOT_LOG_INTERNAL_STACK[@]} - 1 ))
    local parent="${CHROOT_LOG_INTERNAL_STACK[$idx]}"
    printf '%s\n' "${parent%%$'\t'*}"
    return 0
  fi
  printf '%s\n' "${CHROOT_LOG_ACTION_PATH:-}"
}

chroot_log_internal_parent_source() {
  if (( ${#CHROOT_LOG_INTERNAL_STACK[@]} > 0 )); then
    printf 'internal\n'
    return 0
  fi
  printf '%s\n' "${CHROOT_LOG_SOURCE_EFFECTIVE:-$(chroot_log_source_value)}"
}

chroot_log_internal_enclosing_action() {
  if (( ${#CHROOT_LOG_INTERNAL_STACK[@]} > 1 )); then
    local idx=$(( ${#CHROOT_LOG_INTERNAL_STACK[@]} - 2 ))
    local record="${CHROOT_LOG_INTERNAL_STACK[$idx]}"
    printf '%s\n' "${record%%$'\t'*}"
    return 0
  fi
  printf '%s\n' "${CHROOT_LOG_ACTION_PATH:-}"
}

chroot_log_internal_enclosing_source() {
  if (( ${#CHROOT_LOG_INTERNAL_STACK[@]} > 1 )); then
    printf 'internal\n'
    return 0
  fi
  printf '%s\n' "${CHROOT_LOG_SOURCE_EFFECTIVE:-$(chroot_log_source_value)}"
}

chroot_log_next_event_id() {
  [[ -n "${CHROOT_LOG_INVOCATION_ID:-}" ]] || CHROOT_LOG_INVOCATION_ID="$(chroot_log_make_invocation_id)"
  [[ "${CHROOT_LOG_EVENT_SEQ:-0}" =~ ^[0-9]+$ ]] || CHROOT_LOG_EVENT_SEQ=0
  CHROOT_LOG_EVENT_SEQ=$(( CHROOT_LOG_EVENT_SEQ + 1 ))
  printf -v CHROOT_LOG_LAST_EVENT_ID '%s-%04d' "$CHROOT_LOG_INVOCATION_ID" "$CHROOT_LOG_EVENT_SEQ"
}

chroot_log_write_entry() {
  local level="$1"
  local kind="$2"
  local action_hint="$3"
  local message="$4"
  local exit_code="${5:-}"
  local duration_ms="${6:-}"
  shift 6 || true
  local -a detail_pairs=("$@")

  chroot_log_skip_enabled && return 0
  chroot_log_init || return 0
  chroot_log_ensure_context "$action_hint"

  local ts event_id action_path uid cwd detail key value source_value runner_value family_value distro_value command_value argv_value spool_file
  ts="$(chroot_now_ts)"
  chroot_log_next_event_id
  event_id="$CHROOT_LOG_LAST_EVENT_ID"
  source_value="${CHROOT_LOG_ENTRY_SOURCE:-$(chroot_log_current_effective_source)}"
  runner_value="$(chroot_log_sanitize_value "${CHROOT_LOG_ENTRY_RUNNER:-${CHROOT_LOG_RUNNER_EFFECTIVE:-}}")"
  family_value="$(chroot_log_sanitize_value "${CHROOT_LOG_ENTRY_FAMILY:-$(chroot_log_current_effective_family)}")"
  action_path="$(chroot_log_sanitize_value "${CHROOT_LOG_ENTRY_ACTION_PATH:-$(chroot_log_current_effective_action_path)}")"
  if [[ -z "$action_path" ]]; then
    action_path="$(chroot_log_sanitize_value "$(chroot_log_resolve_action_path "$action_hint")")"
  fi
  distro_value="$(chroot_log_sanitize_value "${CHROOT_LOG_ENTRY_DISTRO:-$(chroot_log_current_effective_distro)}")"
  command_value="$(chroot_log_sanitize_value "${CHROOT_LOG_ENTRY_COMMAND_TEXT:-$(chroot_log_current_effective_command_text)}")"
  argv_value="$(chroot_log_sanitize_value "${CHROOT_LOG_ENTRY_ARGV_TEXT:-$(chroot_log_current_effective_argv_text)}")"
  uid="$(id -u 2>/dev/null || echo '')"
  cwd="$(pwd -P 2>/dev/null || pwd 2>/dev/null || echo '')"
  message="$(chroot_log_sanitize_value "$message")"

  spool_file="$(chroot_log_pending_file_path 2>/dev/null || true)"
  [[ -n "$spool_file" ]] || return 0

  if ! {
    printf '================================================================\n'
    printf 'ts: %s\n' "$ts"
    printf 'level: %s\n' "$level"
    printf 'kind: %s\n' "$kind"
    printf 'event_id: %s\n' "$event_id"
    printf 'invocation_id: %s\n' "${CHROOT_LOG_INVOCATION_ID:-}"
    printf 'source: %s\n' "$source_value"
    printf 'runner: %s\n' "$runner_value"
    printf 'family: %s\n' "$family_value"
    printf 'action_path: %s\n' "$action_path"
    printf 'distro: %s\n' "$distro_value"
    printf 'pid: %s\n' "$$"
    printf 'uid: %s\n' "$(chroot_log_sanitize_value "$uid")"
    printf 'cwd: %s\n' "$(chroot_log_sanitize_value "$cwd")"
    printf 'command: %s\n' "$command_value"
    printf 'argv: %s\n' "$argv_value"
    printf 'message: %s\n' "$message"
    if [[ -n "$exit_code" ]]; then
      printf 'exit_code: %s\n' "$(chroot_log_sanitize_value "$exit_code")"
    fi
    if [[ -n "$duration_ms" ]]; then
      printf 'duration_ms: %s\n' "$(chroot_log_sanitize_value "$duration_ms")"
    fi
    for detail in "${detail_pairs[@]}"; do
      if [[ "$detail" == *$'\t'* ]]; then
        key="${detail%%$'\t'*}"
        value="${detail#*$'\t'}"
      else
        key="${detail%%=*}"
        value="${detail#*=}"
      fi
      key="$(chroot_log_sanitize_key "$key")"
      value="$(chroot_log_sanitize_value "$value")"
      [[ -n "$value" ]] || continue
      printf 'detail.%s: %s\n' "$key" "$value"
    done
    printf '================================================================\n'
  } | chroot_log_append_stream "$spool_file"; then
    return 0
  fi

  if [[ "${CHROOT_LOG_IMPLICIT_CONTEXT:-0}" == "1" ]]; then
    chroot_log_flush_invocation_group "${CHROOT_LOG_INVOCATION_ID:-}" >/dev/null 2>&1 || true
    chroot_log_reset_context
  fi

  return 0
}

chroot_log_begin_invocation() {
  local -a argv=("$@")

  chroot_log_skip_enabled && return 0
  CHROOT_LOG_INVOCATION_ID="$(chroot_log_make_invocation_id)"
  CHROOT_LOG_EVENT_SEQ=0
  IFS=$'\t' read -r CHROOT_LOG_FAMILY CHROOT_LOG_ACTION_PATH CHROOT_LOG_DISTRO <<<"$(chroot_log_infer_invocation_context "${argv[@]}")"
  CHROOT_LOG_SOURCE_EFFECTIVE="$(chroot_log_source_value)"
  CHROOT_LOG_RUNNER_EFFECTIVE="$(chroot_resolve_self_path 2>/dev/null || printf '%s\n' "${CHROOT_INVOKED_PATH:-$CHROOT_SCRIPT_NAME}")"
  CHROOT_LOG_COMMAND_TEXT="$(chroot_log_build_command_text "${argv[@]}")"
  CHROOT_LOG_ARGV_TEXT="$(chroot_log_join_args ' | ' "${argv[@]}")"
  CHROOT_LOG_START_MS="$(chroot_log_now_ms)"
  CHROOT_LOG_GROUP_FILE="$(chroot_log_current_file_path)"
  CHROOT_LOG_COMMAND_END_WRITTEN=0
  CHROOT_LOG_IMPLICIT_CONTEXT=0
  CHROOT_LOG_INTERNAL_STACK=()
  CHROOT_LOG_ACTIVE_INTERNAL_COMMAND=""
  chroot_log_clear_pending_error_details
}

chroot_log_command_start() {
  CHROOT_LOG_ENTRY_SOURCE="${CHROOT_LOG_SOURCE_EFFECTIVE:-$(chroot_log_source_value)}" \
  CHROOT_LOG_ENTRY_FAMILY="${CHROOT_LOG_FAMILY:-core}" \
  CHROOT_LOG_ENTRY_ACTION_PATH="${CHROOT_LOG_ACTION_PATH:-}" \
  CHROOT_LOG_ENTRY_DISTRO="${CHROOT_LOG_DISTRO:-}" \
  CHROOT_LOG_ENTRY_COMMAND_TEXT="${CHROOT_LOG_COMMAND_TEXT:-}" \
  CHROOT_LOG_ENTRY_ARGV_TEXT="${CHROOT_LOG_ARGV_TEXT:-}" \
    chroot_log_write_entry "INFO" "command.start" "${CHROOT_LOG_ACTION_PATH:-}" "command started" "" ""
}

chroot_log_command_error() {
  local message="${1:-command failed}"
  local -a detail_pairs=("${CHROOT_LOG_PENDING_ERROR_DETAILS[@]}")
  shift || true
  if [[ $# -gt 0 ]]; then
    detail_pairs+=("$@")
  fi
  CHROOT_LOG_ENTRY_SOURCE="${CHROOT_LOG_SOURCE_EFFECTIVE:-$(chroot_log_source_value)}" \
  CHROOT_LOG_ENTRY_FAMILY="${CHROOT_LOG_FAMILY:-core}" \
  CHROOT_LOG_ENTRY_ACTION_PATH="${CHROOT_LOG_ACTION_PATH:-}" \
  CHROOT_LOG_ENTRY_DISTRO="${CHROOT_LOG_DISTRO:-}" \
  CHROOT_LOG_ENTRY_COMMAND_TEXT="${CHROOT_LOG_COMMAND_TEXT:-}" \
  CHROOT_LOG_ENTRY_ARGV_TEXT="${CHROOT_LOG_ARGV_TEXT:-}" \
    chroot_log_write_entry "ERROR" "command.error" "${CHROOT_LOG_ACTION_PATH:-}" "$message" "" "" "${detail_pairs[@]}"
  chroot_log_clear_pending_error_details
}

chroot_log_finalize_invocation() {
  local rc="${1:-0}"
  local duration_ms=""
  local end_ms=""
  local level="INFO"
  local message="command completed"

  chroot_log_skip_enabled && return 0
  [[ -n "${CHROOT_LOG_INVOCATION_ID:-}" ]] || return 0
  [[ "${CHROOT_LOG_COMMAND_END_WRITTEN:-0}" != "1" ]] || return 0

  if [[ "${CHROOT_LOG_START_MS:-}" =~ ^[0-9]+$ ]]; then
    end_ms="$(chroot_log_now_ms)"
    if [[ "$end_ms" =~ ^[0-9]+$ && "$end_ms" -ge "$CHROOT_LOG_START_MS" ]]; then
      duration_ms="$(( end_ms - CHROOT_LOG_START_MS ))"
    fi
  fi

  if [[ "$rc" != "0" ]]; then
    level="ERROR"
    message="command failed"
  fi

  CHROOT_LOG_ENTRY_SOURCE="${CHROOT_LOG_SOURCE_EFFECTIVE:-$(chroot_log_source_value)}" \
  CHROOT_LOG_ENTRY_FAMILY="${CHROOT_LOG_FAMILY:-core}" \
  CHROOT_LOG_ENTRY_ACTION_PATH="${CHROOT_LOG_ACTION_PATH:-}" \
  CHROOT_LOG_ENTRY_DISTRO="${CHROOT_LOG_DISTRO:-}" \
  CHROOT_LOG_ENTRY_COMMAND_TEXT="${CHROOT_LOG_COMMAND_TEXT:-}" \
  CHROOT_LOG_ENTRY_ARGV_TEXT="${CHROOT_LOG_ARGV_TEXT:-}" \
    chroot_log_write_entry "$level" "command.end" "${CHROOT_LOG_ACTION_PATH:-}" "$message" "$rc" "$duration_ms"
  CHROOT_LOG_COMMAND_END_WRITTEN=1
  chroot_log_flush_invocation_group "${CHROOT_LOG_INVOCATION_ID:-}" >/dev/null 2>&1 || true
}

chroot_log_internal_command_push() {
  local family="$1"
  local action_path="$2"
  local distro="$3"
  shift 3 || true
  local -a log_argv=("$@")
  local command_text argv_text start_ms parent_action parent_source
  command_text="$(chroot_log_build_command_text "${log_argv[@]}")"
  argv_text="$(chroot_log_join_args ' | ' "${log_argv[@]}")"
  start_ms="$(chroot_log_now_ms)"
  parent_action="$(chroot_log_internal_enclosing_action)"
  parent_source="$(chroot_log_internal_enclosing_source)"
  CHROOT_LOG_INTERNAL_STACK+=("${action_path}"$'\t'"${distro}"$'\t'"${command_text}"$'\t'"${argv_text}"$'\t'"${family}"$'\t'"${start_ms}")
  CHROOT_LOG_ACTIVE_INTERNAL_COMMAND="${action_path}"
  CHROOT_LOG_ENTRY_SOURCE=internal \
  CHROOT_LOG_ENTRY_FAMILY="$family" \
  CHROOT_LOG_ENTRY_ACTION_PATH="$action_path" \
  CHROOT_LOG_ENTRY_DISTRO="$distro" \
  CHROOT_LOG_ENTRY_COMMAND_TEXT="$command_text" \
  CHROOT_LOG_ENTRY_ARGV_TEXT="$argv_text" \
    chroot_log_write_entry "INFO" "command.start" "$action_path" "internal command started" "" "" \
      "triggered_by_action"$'\t'"$parent_action" \
      "triggered_by_source"$'\t'"$parent_source" \
      "triggered_by_invocation_id"$'\t'"${CHROOT_LOG_INVOCATION_ID:-}"
}

chroot_log_internal_command_pop() {
  local rc="${1:-0}"
  (( ${#CHROOT_LOG_INTERNAL_STACK[@]} > 0 )) || return 0
  local idx=$(( ${#CHROOT_LOG_INTERNAL_STACK[@]} - 1 ))
  local record="${CHROOT_LOG_INTERNAL_STACK[$idx]}"
  unset 'CHROOT_LOG_INTERNAL_STACK[$idx]'
  CHROOT_LOG_INTERNAL_STACK=("${CHROOT_LOG_INTERNAL_STACK[@]}")

  local action_path distro command_text argv_text family start_ms end_ms duration_ms="" parent_action parent_source level message
  action_path="${record%%$'\t'*}"
  record="${record#*$'\t'}"
  distro="${record%%$'\t'*}"
  record="${record#*$'\t'}"
  command_text="${record%%$'\t'*}"
  record="${record#*$'\t'}"
  argv_text="${record%%$'\t'*}"
  record="${record#*$'\t'}"
  family="${record%%$'\t'*}"
  record="${record#*$'\t'}"
  start_ms="${record%%$'\t'*}"
  parent_action="$(chroot_log_internal_parent_action)"
  parent_source="$(chroot_log_internal_parent_source)"
  if [[ "$start_ms" =~ ^[0-9]+$ ]]; then
    end_ms="$(chroot_log_now_ms)"
    if [[ "$end_ms" =~ ^[0-9]+$ && "$end_ms" -ge "$start_ms" ]]; then
      duration_ms="$(( end_ms - start_ms ))"
    fi
  fi
  if [[ "$rc" == "0" ]]; then
    level="INFO"
    message="internal command completed"
  else
    level="ERROR"
    message="internal command failed"
  fi
  CHROOT_LOG_ENTRY_SOURCE=internal \
  CHROOT_LOG_ENTRY_FAMILY="$family" \
  CHROOT_LOG_ENTRY_ACTION_PATH="$action_path" \
  CHROOT_LOG_ENTRY_DISTRO="$distro" \
  CHROOT_LOG_ENTRY_COMMAND_TEXT="$command_text" \
  CHROOT_LOG_ENTRY_ARGV_TEXT="$argv_text" \
    chroot_log_write_entry "$level" "command.end" "$action_path" "$message" "$rc" "$duration_ms" \
      "triggered_by_action"$'\t'"$parent_action" \
      "triggered_by_source"$'\t'"$parent_source" \
      "triggered_by_invocation_id"$'\t'"${CHROOT_LOG_INVOCATION_ID:-}"
  if (( ${#CHROOT_LOG_INTERNAL_STACK[@]} > 0 )); then
    idx=$(( ${#CHROOT_LOG_INTERNAL_STACK[@]} - 1 ))
    CHROOT_LOG_ACTIVE_INTERNAL_COMMAND="${CHROOT_LOG_INTERNAL_STACK[$idx]%%$'\t'*}"
  else
    CHROOT_LOG_ACTIVE_INTERNAL_COMMAND=""
  fi
}

chroot_log_internal_command_fail() {
  local message="${1:-internal command failed}"
  (( ${#CHROOT_LOG_INTERNAL_STACK[@]} > 0 )) || return 0
  local idx=$(( ${#CHROOT_LOG_INTERNAL_STACK[@]} - 1 ))
  local record="${CHROOT_LOG_INTERNAL_STACK[$idx]}"
  local action_path distro command_text argv_text family parent_action parent_source
  action_path="${record%%$'\t'*}"
  record="${record#*$'\t'}"
  distro="${record%%$'\t'*}"
  record="${record#*$'\t'}"
  command_text="${record%%$'\t'*}"
  record="${record#*$'\t'}"
  argv_text="${record%%$'\t'*}"
  record="${record#*$'\t'}"
  family="${record%%$'\t'*}"
  parent_action="$(chroot_log_internal_enclosing_action)"
  parent_source="$(chroot_log_internal_enclosing_source)"
  CHROOT_LOG_ENTRY_SOURCE=internal \
  CHROOT_LOG_ENTRY_FAMILY="$family" \
  CHROOT_LOG_ENTRY_ACTION_PATH="$action_path" \
  CHROOT_LOG_ENTRY_DISTRO="$distro" \
  CHROOT_LOG_ENTRY_COMMAND_TEXT="$command_text" \
  CHROOT_LOG_ENTRY_ARGV_TEXT="$argv_text" \
    chroot_log_write_entry "ERROR" "command.error" "$action_path" "$message" "" "" \
      "triggered_by_action"$'\t'"$parent_action" \
      "triggered_by_source"$'\t'"$parent_source" \
      "triggered_by_invocation_id"$'\t'"${CHROOT_LOG_INVOCATION_ID:-}"
}

chroot_log_run_internal_command() {
  local family="$1"
  local action_path="$2"
  local distro="$3"
  shift 3 || true
  local -a log_argv=()
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--" ]]; then
      shift
      break
    fi
    log_argv+=("$1")
    shift
  done
  local -a call_argv=("$@")
  (( ${#call_argv[@]} > 0 )) || return 1

  chroot_log_internal_command_push "$family" "$action_path" "$distro" "${log_argv[@]}"
  local rc=0
  set +e
  "${call_argv[@]}"
  rc=$?
  set -e
  chroot_log_internal_command_pop "$rc"
  return "$rc"
}

chroot_rotate_logs() {
  local keep_days
  keep_days="$(chroot_setting_get log_retention_days 2>/dev/null || true)"
  [[ -n "$keep_days" ]] || keep_days="$CHROOT_LOG_RETENTION_DAYS_DEFAULT"
  [[ -d "$CHROOT_LOG_DIR" ]] || return 0

  find "$CHROOT_LOG_DIR" -type f -name 'events-*.log' -mtime "+$keep_days" -delete 2>/dev/null || true
  find "$(chroot_log_pending_dir)" -type f -name '*.spool' -mtime +2 -delete 2>/dev/null || true
}

chroot_log_emit_operation() {
  local level="$1"
  local kind="$2"
  local action="$3"
  shift 3 || true
  chroot_log_write_entry "$level" "$kind" "$action" "$*" "" ""
}

chroot_log_info() {
  chroot_log_emit_operation "INFO" "op.info" "$1" "${*:2}"
}

chroot_log_warn() {
  chroot_log_emit_operation "WARN" "op.warn" "$1" "${*:2}"
}

chroot_log_error() {
  chroot_log_emit_operation "ERROR" "op.error" "$1" "${*:2}"
}

chroot_logs_render_entries() {
  local count="$1"
  local exclude_invocation_id="${2:-}"

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$CHROOT_LOG_DIR" "$count" "$exclude_invocation_id" <<'PY'
import glob
import os
import sys
import textwrap

try:
    import fcntl
except Exception:  # pragma: no cover - platform fallback
    fcntl = None

log_dir, count_text, exclude_invocation_id = sys.argv[1:4]

try:
    wanted = int(count_text)
except Exception:
    raise SystemExit(2)

group_separator = "=" * 64
entry_separator = "*" * 64
required = ("ts", "level", "kind", "event_id", "invocation_id", "source", "action_path", "command")


def valid_entry(entry):
    return all(str(entry.get(key, "") or "").strip() for key in required)


def parse_grouped_file(path):
    groups = []
    entries = []
    current = None
    in_group = False
    in_entry = False
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            if fcntl is not None:
                try:
                    fcntl.flock(fh.fileno(), fcntl.LOCK_SH)
                except OSError:
                    pass
            for raw in fh:
                line = raw.rstrip("\n")
                if line == group_separator:
                    if not in_group:
                        in_group = True
                        in_entry = False
                        current = None
                        entries = []
                    else:
                        if in_entry and current:
                            if valid_entry(current):
                                entries.append(current)
                        if entries:
                            groups.append(entries)
                        in_group = False
                        in_entry = False
                        current = None
                        entries = []
                    continue
                if not in_group:
                    continue
                if line == entry_separator:
                    if not in_entry:
                        current = {"_details": []}
                        in_entry = True
                    else:
                        if current and valid_entry(current):
                            entries.append(current)
                        current = None
                        in_entry = False
                    continue
                if not in_entry or current is None or ":" not in line:
                    continue
                key, value = line.split(":", 1)
                key = key.strip()
                value = value.strip()
                if key.startswith("detail."):
                    current["_details"].append((key[7:], value))
                else:
                    current[key] = value
    except FileNotFoundError:
        return []
    return groups


def parse_legacy_entries(path):
    entries = []
    current = None
    in_entry = False
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            if fcntl is not None:
                try:
                    fcntl.flock(fh.fileno(), fcntl.LOCK_SH)
                except OSError:
                    pass
            for raw in fh:
                line = raw.rstrip("\n")
                if line == group_separator:
                    if not in_entry:
                        current = {"_details": []}
                        in_entry = True
                    else:
                        if current and valid_entry(current):
                            entries.append(current)
                        current = None
                        in_entry = False
                    continue
                if not in_entry or current is None or ":" not in line:
                    continue
                key, value = line.split(":", 1)
                key = key.strip()
                value = value.strip()
                if key.startswith("detail."):
                    current["_details"].append((key[7:], value))
                else:
                    current[key] = value
    except FileNotFoundError:
        return []
    return entries


def group_legacy_entries(entries):
    groups = []
    by_invocation = {}
    for entry in entries:
        invocation_id = str(entry.get("invocation_id", "") or entry.get("event_id", "") or "").strip()
        if not invocation_id:
            groups.append([entry])
            continue
        if invocation_id in by_invocation:
            by_invocation[invocation_id].append(entry)
            continue
        group = [entry]
        groups.append(group)
        by_invocation[invocation_id] = group
    return groups


def display_ts(raw):
    text = str(raw or "").strip()
    if not text:
        return "-"
    if "T" in text and text.endswith("Z"):
        date_part, time_part = text.split("T", 1)
        return f"{date_part} {time_part}"
    return text


def first_nonempty(group, key, default=""):
    for entry in group:
        value = str(entry.get(key, "") or "").strip()
        if value:
            return value
    return default


def root_entry(group):
    for entry in group:
        if str(entry.get("source", "") or "").strip() in {"cli", "tui"}:
            return entry
    return group[0]


def final_entry(group):
    root = root_entry(group)
    root_source = str(root.get("source", "") or "").strip()
    root_command = str(root.get("command", "") or "").strip()
    for entry in reversed(group):
        if root_source and str(entry.get("source", "") or "").strip() != root_source:
            continue
        if root_command and str(entry.get("command", "") or "").strip() != root_command:
            continue
        kind = str(entry.get("kind", "") or "").strip()
        if kind in {"command.end", "command.error"}:
            return entry
    return group[-1]


def group_status(group):
    final = final_entry(group)
    for entry in group:
        kind = str(entry.get("kind", "") or "").strip()
        level = str(entry.get("level", "") or "").strip()
        exit_code = str(entry.get("exit_code", "") or "").strip()
        if kind.endswith(".error") or level == "ERROR" or (kind == "command.end" and exit_code not in {"", "0"}):
            return "failed"
    for entry in group:
        kind = str(entry.get("kind", "") or "").strip()
        level = str(entry.get("level", "") or "").strip()
        if kind.endswith(".warn") or level == "WARN":
            return "warning"
    if str(final.get("kind", "") or "").strip() == "command.end":
        exit_code = str(final.get("exit_code", "") or "").strip()
        return "ok" if exit_code in {"", "0"} else "failed"
    if str(final.get("kind", "") or "").strip() == "command.start":
        return "started"
    return "info"


def display_level_for_status(status):
    if status == "failed":
        return "ERROR"
    if status == "warning":
        return "WARN"
    return "INFO"


def internal_summaries(group):
    ordered = []
    state = {}
    for entry in group:
        if str(entry.get("source", "") or "").strip() != "internal":
            continue
        action = str(entry.get("action_path", "") or "").strip()
        if not action:
            continue
        if action not in state:
            ordered.append(action)
            state[action] = "info"
        kind = str(entry.get("kind", "") or "").strip()
        level = str(entry.get("level", "") or "").strip()
        exit_code = str(entry.get("exit_code", "") or "").strip()
        next_status = state[action]
        if kind.endswith(".error") or level == "ERROR" or (kind == "command.end" and exit_code not in {"", "0"}):
            next_status = "failed"
        elif next_status != "failed" and (kind.endswith(".warn") or level == "WARN"):
            next_status = "warning"
        elif next_status not in {"failed", "warning"} and kind == "command.end":
            next_status = "ok" if exit_code in {"", "0"} else "failed"
        elif next_status == "info" and kind == "command.start":
            next_status = "started"
        state[action] = next_status
    return [f"{action} {state[action]}" for action in ordered]


def wrap_field(label, value, width):
    prefix = f"{label:<8}: "
    text = str(value or "").strip() or "-"
    available = max(12, width - len(prefix))
    chunks = textwrap.wrap(
        text,
        width=available,
        break_long_words=False,
        replace_whitespace=False,
    ) or [text]
    lines = [prefix + chunks[0]]
    indent = " " * len(prefix)
    for chunk in chunks[1:]:
        lines.append(indent + chunk)
    return lines


def render_card(lines):
    inner_width = max(len(line) for line in lines) if lines else 20
    border = "+" + ("-" * (inner_width + 2)) + "+"
    rendered = [border]
    for line in lines:
        rendered.append(f"| {line.ljust(inner_width)} |")
    rendered.append(border)
    return rendered


files = sorted(glob.glob(os.path.join(log_dir, "events-*.log")))
groups = []
for path in files:
    parsed_groups = parse_grouped_file(path)
    if parsed_groups:
        groups.extend(parsed_groups)
        continue
    legacy_entries = parse_legacy_entries(path)
    if legacy_entries:
        groups.extend(group_legacy_entries(legacy_entries))

if exclude_invocation_id:
    groups = [
        group for group in groups
        if str(first_nonempty(group, "invocation_id", "")) != exclude_invocation_id
    ]

if not groups:
    raise SystemExit(3)

selected = groups[-wanted:]
for index, group in enumerate(selected):
    root = root_entry(group)
    final = final_entry(group)
    status = group_status(group)
    ts = display_ts(final.get("ts", "") or root.get("ts", ""))
    source = str(root.get("source", "") or "-")
    action = str(root.get("action_path", "") or first_nonempty(group, "action_path", "-"))
    distro = str(root.get("distro", "") or first_nonempty(group, "distro", "-")) or "-"
    command = str(root.get("command", "") or first_nonempty(group, "command", "-")).strip() or "-"
    invocation_id = str(root.get('invocation_id', '') or first_nonempty(group, 'invocation_id', '-'))
    exit_code = str(final.get("exit_code", "") or "").strip()
    duration_ms = str(final.get("duration_ms", "") or "").strip()
    internals = internal_summaries(group)
    message = str(final.get("message", "") or "").strip()

    card_lines = [f"{action} | {status}"]
    wrap_width = 52
    card_lines.extend(wrap_field("distro", distro, wrap_width))
    card_lines.extend(wrap_field("source", source, wrap_width))
    card_lines.extend(wrap_field("time", ts, wrap_width))
    card_lines.extend(wrap_field("command", command, wrap_width))
    card_lines.extend(wrap_field("id", invocation_id, wrap_width))
    result_parts = []
    if exit_code:
        result_parts.append(f"exit={exit_code}")
    if duration_ms:
        result_parts.append(f"duration={duration_ms}ms")
    result_parts.append(f"events={len(group)}")
    card_lines.extend(wrap_field("result", " ".join(result_parts), wrap_width))
    for item in internals:
        card_lines.extend(wrap_field("internal", item, wrap_width))
    if message and message not in {"command started", "command completed", "command failed", "internal command completed", "internal command failed"}:
        card_lines.extend(wrap_field("message", message, wrap_width))

    for line in render_card(card_lines):
        print(line)

    if index != len(selected) - 1:
        print()
PY
}

chroot_cmd_logs() {
  local count=10
  local output=""
  local render_rc=0
  local exclude_invocation_id="${CHROOT_LOG_INVOCATION_ID:-}"

  case "$#" in
    0) ;;
    1)
      [[ "$1" =~ ^[0-9]+$ ]] || chroot_die "usage: bash path/to/chroot logs [<count>]"
      count="$1"
      ;;
    *)
      chroot_die "usage: bash path/to/chroot logs [<count>]"
      ;;
  esac

  (( count > 0 )) || chroot_die "logs count must be greater than zero"
  if (( count > 50 )); then
    chroot_die "logs supports at most 50 command groups. Open the grouped log files under $CHROOT_LOG_DIR directly."
  fi

  set +e
  output="$(chroot_logs_render_entries "$count" "$exclude_invocation_id")"
  render_rc=$?
  set -e

  case "$render_rc" in
    0)
      printf '%s\n' "$output"
      printf '\nGo to this log directory for full view: %s\n' "$CHROOT_LOG_DIR"
      ;;
    3)
      chroot_die "no logs found"
      ;;
    *)
      chroot_die "failed to render logs"
      ;;
  esac
}
