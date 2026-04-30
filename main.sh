#!/usr/bin/env bash
set -euo pipefail

CHROOT_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHROOT_INVOKED_PATH="${CHROOT_INVOKED_PATH:-${BASH_SOURCE[0]}}"

if [[ -z "${CHROOT_LIBS_LOADED:-}" ]]; then
  :
  # shellcheck source=lib/core.sh
  source "$CHROOT_BASE_DIR/lib/core.sh"
  # shellcheck source=lib/log.sh
  source "$CHROOT_BASE_DIR/lib/log.sh"
  # shellcheck source=lib/commands.sh
  source "$CHROOT_BASE_DIR/lib/commands.sh"
  # shellcheck source=lib/help.sh
  source "$CHROOT_BASE_DIR/lib/help.sh"
  # shellcheck source=lib/settings.sh
  source "$CHROOT_BASE_DIR/lib/settings.sh"
  # shellcheck source=lib/init.sh
  source "$CHROOT_BASE_DIR/lib/init.sh"
  # shellcheck source=lib/busybox.sh
  source "$CHROOT_BASE_DIR/lib/busybox.sh"
  # shellcheck source=lib/lock.sh
  source "$CHROOT_BASE_DIR/lib/lock.sh"
  # shellcheck source=lib/preflight.sh
  source "$CHROOT_BASE_DIR/lib/preflight.sh"
  # shellcheck source=lib/info.sh
  source "$CHROOT_BASE_DIR/lib/info.sh"
  # shellcheck source=lib/manifest.sh
  source "$CHROOT_BASE_DIR/lib/manifest.sh"
  # shellcheck source=lib/install.sh
  source "$CHROOT_BASE_DIR/lib/install.sh"
  # shellcheck source=lib/aliases.sh
  source "$CHROOT_BASE_DIR/lib/aliases.sh"
  # shellcheck source=lib/mount.sh
  source "$CHROOT_BASE_DIR/lib/mount.sh"
  # shellcheck source=lib/session.sh
  source "$CHROOT_BASE_DIR/lib/session.sh"
  # shellcheck source=lib/service.sh
  source "$CHROOT_BASE_DIR/lib/service.sh"
  # shellcheck source=lib/status.sh
  source "$CHROOT_BASE_DIR/lib/status.sh"
  # shellcheck source=lib/tor.sh
  source "$CHROOT_BASE_DIR/lib/tor.sh"
  # shellcheck source=lib/backup.sh
  source "$CHROOT_BASE_DIR/lib/backup.sh"
  # shellcheck source=lib/remove.sh
  source "$CHROOT_BASE_DIR/lib/remove.sh"
  # shellcheck source=lib/nuke.sh
  source "$CHROOT_BASE_DIR/lib/nuke.sh"
  # shellcheck source=lib/cache.sh
  source "$CHROOT_BASE_DIR/lib/cache.sh"
  # shellcheck source=lib/tui.sh
  source "$CHROOT_BASE_DIR/lib/tui.sh"
fi

chroot_guess_scoped_feature() {
  local token="${1:-}"
  local lower="${token,,}"
  case "$lower" in
    session|sessions|sessions*|session-*|session_*)
      printf 'sessions\n'
      ;;
    service|services|servic*|service-*|service_*)
      printf 'service\n'
      ;;
    tor|tors|tor*)
      printf 'tor\n'
      ;;
    *)
      return 1
      ;;
  esac
}

chroot_is_installed_distro_token() {
  local distro="${1:-}"
  [[ "$distro" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || return 1
  [[ -d "$(chroot_distro_rootfs_dir "$distro")" ]]
}

chroot_main_exit_trap() {
  local rc=$?
  if declare -F chroot_log_internal_command_pop >/dev/null 2>&1 && declare -p CHROOT_LOG_INTERNAL_STACK >/dev/null 2>&1; then
    while (( ${#CHROOT_LOG_INTERNAL_STACK[@]} > 0 )); do
      chroot_log_internal_command_pop "$rc" >/dev/null 2>&1 || true
    done
  fi
  if declare -F chroot_log_finalize_invocation >/dev/null 2>&1; then
    chroot_log_finalize_invocation "$rc" >/dev/null 2>&1 || true
  fi
  if declare -F chroot_lock_release_held >/dev/null 2>&1; then
    chroot_lock_release_held >/dev/null 2>&1 || true
  fi
}

chroot_main() {
  local args_provided=0
  local should_reexec=1
  if [[ $# -gt 0 ]]; then
    args_provided=1
  fi
  local -a original_argv=("$@")
  local cmd="${1:-help}"
  local scoped_distro=""
  local scoped_feature=0
  if [[ $# -gt 0 ]]; then
    shift
  fi

  if [[ $# -gt 0 ]]; then
    case "$1" in
      service|sessions|tor)
        scoped_distro="$cmd"
        cmd="$1"
        scoped_feature=1
        shift
        set -- "$scoped_distro" "$@"
        ;;
    esac
  fi

  chroot_detect_inside_chroot
  chroot_set_runtime_root "$CHROOT_RUNTIME_ROOT"
  chroot_prepend_termux_path
  chroot_detect_bins
  chroot_ensure_aurora_launcher >/dev/null 2>&1 || true

  if [[ "$args_provided" == "0" ]]; then
    if [[ -t 1 ]] && { command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; }; then
      CHROOT_LOG_ZERO_ARG_ACTION="tui"
    else
      CHROOT_LOG_ZERO_ARG_ACTION="help"
    fi
  fi

  # Zero-arg TUI launches run before any privileged command flow and otherwise
  # create orphan fallback-home log spools that never reach the real log root.
  if [[ "$args_provided" == "0" && "${CHROOT_LOG_ZERO_ARG_ACTION:-}" == "tui" ]]; then
    CHROOT_LOG_SKIP=1
  fi

  if [[ "$cmd" == "logs" && "$scoped_feature" != "1" ]]; then
    CHROOT_LOG_SKIP=1
  fi

  # Help/init are read-only guidance commands. Are keptout of the logging
  # pipeline so they do not create fallback-home log trees or fail when the
  # real runtime root exists but is not writable from the current shell.
  if [[ "$cmd" == "help" || "$cmd" == "-h" || "$cmd" == "--help" || "$cmd" == "init" ]]; then
    CHROOT_LOG_SKIP=1
  fi

  case "$cmd" in
    help|-h|--help|init)
      should_reexec=0
      ;;
    info)
      if ! chroot_is_root_available >/dev/null 2>&1; then
        should_reexec=0
      fi
      ;;
  esac

  case "$cmd" in
    service)
      if [[ "$scoped_feature" != "1" ]]; then
        should_reexec=0
      fi
      ;;
    sessions)
      if [[ "$scoped_feature" != "1" ]]; then
        should_reexec=0
      fi
      ;;
    tor)
      if [[ "$scoped_feature" != "1" ]]; then
        should_reexec=0
      fi
      ;;
  esac

  case "$cmd" in
    service)
      if [[ "$scoped_feature" != "1" ]]; then
        CHROOT_LOG_SKIP=1
        chroot_die "use: $(chroot_commands_usage_service)"
      fi
      ;;
    sessions)
      if [[ "$scoped_feature" != "1" ]]; then
        CHROOT_LOG_SKIP=1
        chroot_die "use: $(chroot_commands_usage_sessions)"
      fi
      ;;
    tor)
      if [[ "$scoped_feature" != "1" ]]; then
        CHROOT_LOG_SKIP=1
        chroot_die "use: $(chroot_commands_usage_tor)"
      fi
      ;;
  esac

  if [[ "$should_reexec" == "1" ]]; then
    chroot_maybe_reexec_root_context "${original_argv[@]}"
  fi

  local prefer_existing_runtime=0
  if [[ "$cmd" == "info" ]]; then
    prefer_existing_runtime=1
  fi
  if [[ "$args_provided" == "0" && "${CHROOT_LOG_ZERO_ARG_ACTION:-}" == "tui" ]]; then
    prefer_existing_runtime=1
  fi

  if [[ "$prefer_existing_runtime" == "1" ]]; then
    chroot_info_resolve_existing_runtime_root || chroot_resolve_runtime_root
  else
    chroot_resolve_runtime_root
  fi
  chroot_log_init
  chroot_rotate_logs
  chroot_log_begin_invocation "${original_argv[@]}"
  trap 'chroot_main_exit_trap' EXIT
  chroot_log_command_start

  case "$cmd" in
    help|-h|--help)
      if [[ $# -gt 0 ]]; then
        case "${1:-}" in
          raw)
            shift
            [[ $# -eq 0 ]] || chroot_die "help raw does not accept extra arguments"
            chroot_cmd_help_raw
            return 0
            ;;
          *)
            chroot_die "unknown help arg: ${1:-} (expected: raw)"
            ;;
        esac
      fi
      if [[ "$args_provided" == "1" ]]; then
        chroot_cmd_help
      else
        chroot_cmd_tui
      fi
      return 0
      ;;
    init)
      chroot_cmd_init "$@"
      return 0
      ;;
  esac

  if [[ "$cmd" != "info" ]]; then
    chroot_bootstrap
  fi

  if [[ "$scoped_feature" != "1" ]]; then
    local scoped_guess=""
    if [[ $# -gt 0 ]]; then
      scoped_guess="$(chroot_guess_scoped_feature "${1:-}" 2>/dev/null || true)"
      if [[ -n "$scoped_guess" ]]; then
        chroot_die "unknown command after distro '$cmd': ${1:-}. use: $(chroot_commands_usage_for_scoped_feature "$scoped_guess")"
      fi
    fi
    if chroot_is_installed_distro_token "$cmd"; then
      if [[ $# -gt 0 ]]; then
        chroot_die "unknown command after distro '$cmd': ${1:-} (expected: service|sessions|tor)"
      fi
      chroot_die "expected a command after distro '$cmd' (expected: service|sessions|tor)"
    fi
  fi

  case "$cmd" in
    doctor)
      chroot_cmd_doctor "$@"
      ;;
    status)
      chroot_cmd_status "$@"
      ;;
    tor)
      chroot_cmd_tor "$@"
      ;;
    distros)
      chroot_cmd_distros "$@"
      ;;
    settings)
      chroot_cmd_settings "$@"
      ;;
    info)
      chroot_cmd_info "$@"
      ;;
    busybox)
      chroot_cmd_busybox "$@"
      ;;
    logs)
      chroot_cmd_logs "$@"
      ;;
    install-local)
      chroot_cmd_install_local "$@"
      ;;
    login)
      [[ $# -gt 0 ]] || chroot_die "login requires distro"
      chroot_cmd_login "$@"
      ;;
    exec)
      [[ $# -gt 0 ]] || chroot_die "exec requires distro"
      chroot_cmd_exec "$@"
      ;;
    service)
      chroot_cmd_service "$@"
      ;;
    sessions)
      chroot_cmd_sessions "$@"
      ;;
    mount)
      chroot_cmd_mount "$@"
      ;;
    unmount)
      chroot_cmd_unmount "$@"
      ;;
    backup)
      chroot_cmd_backup "$@"
      ;;
    restore)
      chroot_cmd_restore "$@"
      ;;
    remove)
      chroot_cmd_remove "$@"
      ;;
    nuke)
      chroot_cmd_nuke "$@"
      ;;
    clear-cache)
      chroot_cmd_clear_cache "$@"
      ;;
    *)
      chroot_die "unknown command: $cmd"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  chroot_main "$@"
fi
