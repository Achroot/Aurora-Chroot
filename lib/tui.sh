#!/usr/bin/env bash
set -euo pipefail

chroot_tui_python_parts_dir() {
  printf '%s/lib/tui/python' "$CHROOT_BASE_DIR"
}

chroot_tui_emit_python() {
  local parts_dir
  parts_dir="$(chroot_tui_python_parts_dir)"

  local -a parts=("$parts_dir"/[0-9][0-9][0-9]_*.py)
  if [[ -f "${parts[0]:-}" ]]; then
    local part
    for part in "${parts[@]}"; do
      cat "$part"
    done
    return 0
  fi

  if [[ -n "${CHROOT_TUI_PY_EMBEDDED:-}" ]]; then
    printf '%s\n' "$CHROOT_TUI_PY_EMBEDDED"
    return 0
  fi

  chroot_die "tui python payload missing (expected $parts_dir or CHROOT_TUI_PY_EMBEDDED)"
}

chroot_cmd_tui() {
  if [[ ! -t 1 ]]; then
    chroot_cmd_help
    return 0
  fi

  local python_bin=""
  if command -v python3 >/dev/null 2>&1; then
    python_bin="python3"
  elif command -v python >/dev/null 2>&1; then
    python_bin="python"
  fi

  if [[ -z "$python_bin" ]]; then
    chroot_cmd_help
    return 0
  fi

  local help_md=""
  if [[ -n "${CHROOT_EMBEDDED_HELP_MD:-}" ]]; then
    help_md="$CHROOT_EMBEDDED_HELP_MD"
  elif [[ -f "$CHROOT_BASE_DIR/HELP.md" ]]; then
    help_md="$(cat "$CHROOT_BASE_DIR/HELP.md")"
  elif [[ -f "$CHROOT_BASE_DIR/../HELP.md" ]]; then
    help_md="$(cat "$CHROOT_BASE_DIR/../HELP.md")"
  fi

  local runner="${CHROOT_INVOKED_PATH:-}"
  if [[ -n "$runner" && "$runner" != /* ]]; then
    local resolved=""
    resolved="$(command -v "$runner" 2>/dev/null || true)"
    if [[ -n "$resolved" ]]; then
      runner="$resolved"
    fi
  fi
  if [[ -z "$runner" || ! -x "$runner" ]]; then
    if [[ -x "$CHROOT_TERMUX_BIN/aurora" ]]; then
      runner="$CHROOT_TERMUX_BIN/aurora"
    elif [[ -x "$CHROOT_TERMUX_HOME_DEFAULT/bin/chroot" ]]; then
      runner="$CHROOT_TERMUX_HOME_DEFAULT/bin/chroot"
    elif command -v aurora >/dev/null 2>&1; then
      runner="$(command -v aurora)"
    elif command -v chroot >/dev/null 2>&1; then
      runner="$(command -v chroot)"
    else
      runner="$CHROOT_BASE_DIR/main.sh"
    fi
  fi

  CHROOT_HELP_TEXT="$(chroot_cmd_help)" \
  CHROOT_HELP_MD="$help_md" \
  CHROOT_TUI_RUNNER="$runner" \
  "$python_bin" - "$CHROOT_BASE_DIR" < <(chroot_tui_emit_python)
}
