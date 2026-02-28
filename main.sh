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
  # shellcheck source=lib/settings.sh
  source "$CHROOT_BASE_DIR/lib/settings.sh"
  # shellcheck source=lib/init.sh
  source "$CHROOT_BASE_DIR/lib/init.sh"
  # shellcheck source=lib/lock.sh
  source "$CHROOT_BASE_DIR/lib/lock.sh"
  # shellcheck source=lib/preflight.sh
  source "$CHROOT_BASE_DIR/lib/preflight.sh"
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

chroot_cmd_help() {
  cat <<'EOF_HELP'
Usage:
  bash path/to/chroot <command> [args]
  aurora <command> [args]

Commands:
  help
  init
  doctor [--json] [--repair-locks]
  distros [--json] [--refresh] [--install <id> --version <release>]
  install-local <distro> --file <path> [--sha256 <hex>]
  status [--all|--distro <id>] [--json] [--live]
  service <distro> [list|status|start|stop|restart|add|remove|install] [args...]
  sessions <distro> [list|status|kill|kill-all] [args...]
  login <distro>
  exec <distro> -- <cmd...>
  mount [<distro>]
  unmount [<distro>] [--kill-sessions|--no-kill-sessions]
  confirm-unmount [<distro>] [--json]
  backup [<distro>] [--out <dir>] [--mode full|rootfs|state]
  restore [<distro>] [--file <backup.tar.zst|backup.tar.xz>]
  settings [set <key> <value>] [--json]
  logs [--tail <N>]
  clear-cache [--all|--older-than <days>] [--yes]
  remove [<distro>] [--full]
  nuke [--yes]
EOF_HELP
}

chroot_main() {
  local cmd="${1:-help}"
  if [[ $# -gt 0 ]]; then
    shift
  fi

  chroot_detect_inside_chroot
  chroot_set_runtime_root "$CHROOT_RUNTIME_ROOT"
  chroot_prepend_termux_path
  chroot_detect_bins
  chroot_ensure_aurora_launcher >/dev/null 2>&1 || true

  case "$cmd" in
    help|-h|--help)
      chroot_cmd_tui
      return 0
      ;;
    init)
      chroot_cmd_init "$@"
      return 0
      ;;
  esac

  chroot_maybe_reexec_root_context "$cmd" "$@"

  trap 'if declare -F chroot_lock_release_held >/dev/null 2>&1; then chroot_lock_release_held >/dev/null 2>&1 || true; fi' EXIT

  chroot_bootstrap
  chroot_log_init
  chroot_rotate_logs

  case "$cmd" in
    doctor)
      chroot_cmd_doctor "$@"
      ;;
    status)
      chroot_cmd_status "$@"
      ;;
    distros)
      chroot_cmd_distros "$@"
      ;;
    settings)
      chroot_cmd_settings "$@"
      ;;
    logs)
      chroot_cmd_logs "$@"
      ;;
    install-local)
      [[ $# -gt 0 ]] || chroot_die "install-local requires distro"
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
    confirm-unmount)
      chroot_cmd_confirm_unmount "$@"
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
