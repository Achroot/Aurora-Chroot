#!/usr/bin/env bash
set -euo pipefail

chroot_tui_python_parts_dir() {
  printf '%s/lib/tui/python' "$CHROOT_BASE_DIR"
}

chroot_tui_resolve_runner() {
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
  printf '%s\n' "$runner"
}

chroot_tui_prepare_env() {
  local runner=""
  if [[ "${CHROOT_RUNTIME_ROOT_FROM_ENV:-0}" != "1" ]]; then
    chroot_info_resolve_existing_runtime_root || {
      if [[ "${CHROOT_RUNTIME_ROOT_RESOLVED:-0}" != "1" ]]; then
        chroot_resolve_runtime_root
      fi
    }
  fi
  runner="$(chroot_tui_resolve_runner)"
  export CHROOT_HELP_TEXT="$(chroot_help_full_text)"
  export CHROOT_HELP_RENDERED_TEXT="$(chroot_help_render_full_text)"
  export CHROOT_HELP_RAW_TEXT="$(chroot_help_raw_text)"
  export CHROOT_HELP_RAW_RENDERED_TEXT="$(chroot_help_render_raw_text)"
  export CHROOT_TUI_COMMANDS_JSON="$(chroot_commands_registry_tui_json)"
  export CHROOT_TUI_SPECS_JSON="$(chroot_commands_registry_tui_specs_json)"
  export CHROOT_TUI_RUNNER="$runner"
  export CHROOT_TUI_RUNTIME_ROOT="$CHROOT_RUNTIME_ROOT"
  export CHROOT_TUI_CACHE_DIR="$CHROOT_CACHE_DIR"
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

  chroot_tui_prepare_env
  "$python_bin" - "$CHROOT_BASE_DIR" < <(chroot_tui_emit_python)
}
