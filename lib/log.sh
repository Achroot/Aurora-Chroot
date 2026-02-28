#!/usr/bin/env bash

CHROOT_LOG_FILE=""

chroot_log_init() {
  mkdir -p "$CHROOT_LOG_DIR"
  CHROOT_LOG_FILE="$CHROOT_LOG_DIR/actions-$(date -u +%Y%m%d).log"
  touch "$CHROOT_LOG_FILE"
}

chroot_log_write() {
  local level="$1"
  local action="$2"
  shift 2
  local msg="$*"
  local ts
  ts="$(chroot_now_ts)"

  [[ -n "$CHROOT_LOG_FILE" ]] || chroot_log_init
  printf '%s level=%s action=%s msg=%s\n' "$ts" "$level" "$action" "$msg" >>"$CHROOT_LOG_FILE"
}

chroot_log_info() {
  chroot_log_write "INFO" "$1" "${*:2}"
}

chroot_log_warn() {
  chroot_log_write "WARN" "$1" "${*:2}"
}

chroot_log_error() {
  chroot_log_write "ERROR" "$1" "${*:2}"
}

chroot_rotate_logs() {
  local keep_days
  keep_days="$(chroot_setting_get log_retention_days 2>/dev/null || true)"
  [[ -n "$keep_days" ]] || keep_days="$CHROOT_LOG_RETENTION_DAYS_DEFAULT"

  find "$CHROOT_LOG_DIR" -type f -name 'actions-*.log' -mtime "+$keep_days" -delete 2>/dev/null || true
}

chroot_cmd_logs() {
  local tail_lines=120

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tail)
        shift
        [[ $# -gt 0 ]] || chroot_die "--tail requires a number"
        tail_lines="$1"
        [[ "$tail_lines" =~ ^[0-9]+$ ]] || chroot_die "--tail must be a positive integer"
        (( tail_lines > 0 )) || chroot_die "--tail must be greater than zero"
        ;;
      *) chroot_die "unknown logs arg: $1" ;;
    esac
    shift
  done

  local latest
  latest="$(ls -1 "$CHROOT_LOG_DIR"/actions-*.log 2>/dev/null | sort | tail -n 1 || true)"
  [[ -n "$latest" ]] || chroot_die "no logs found"
  tail -n "$tail_lines" "$latest"
}
