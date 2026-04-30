#!/usr/bin/env bash

chroot_remove_select_distro() {
  chroot_select_installed_distro "Select distro to remove"
}

chroot_remove_confirm_yes_no() {
  local prompt="$1"
  local answer
  while true; do
    printf '%s [y/N]: ' "$prompt" >&2
    read -r answer
    case "$answer" in
      y|Y|yes|YES)
        return 0
        ;;
      n|N|no|NO|'')
        return 1
        ;;
    esac
    printf 'Please answer y or n.\n' >&2
  done
}

chroot_cmd_remove() {
  local distro=""
  if [[ $# -gt 0 && "$1" != --* ]]; then
    distro="$1"
    shift || true
  fi

  local full=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --full) full=1 ;;
      *) chroot_die "unknown remove arg: $1" ;;
    esac
    shift
  done

  if [[ -z "$distro" ]]; then
    local pick_rc=0
    distro="$(chroot_remove_select_distro)" || pick_rc=$?
    case "$pick_rc" in
      0) ;;
      2) chroot_die "no installed distros to remove" ;;
      *) chroot_die "remove aborted" ;;
    esac
  fi

  chroot_require_distro_arg "$distro"
  chroot_preflight_hard_fail

  local rootfs state_dir
  rootfs="$(chroot_distro_rootfs_dir "$distro")"
  state_dir="$(chroot_distro_state_dir "$distro")"

  [[ -d "$rootfs" || -d "$state_dir" ]] || chroot_die "distro not found: $distro"

  chroot_info "Target distro: $distro"
  chroot_info "Rootfs path: $rootfs"
  chroot_info "State path: $state_dir"
  if (( full == 1 )); then
    chroot_info "Cache cleanup: enabled (--full)"
  fi
  chroot_info "Session handling: active sessions will be terminated before unmount."
  chroot_remove_confirm_yes_no "Remove distro '$distro' now?" || chroot_die "remove aborted"

  if declare -F chroot_tor_locked_teardown_for_distro >/dev/null 2>&1; then
    chroot_tor_locked_teardown_for_distro "$distro" >/dev/null 2>&1 || true
  fi

  # Unmount first so this path avoids nested-lock deadlocks.
  local unmount_rc=0
  chroot_log_run_internal_command core unmount "$distro" unmount "$distro" --kill-sessions -- chroot_cmd_unmount "$distro" --kill-sessions || unmount_rc=$?

  chroot_lock_acquire "distro-$distro" || chroot_die "failed distro lock"

  # Refuse removal while anything is still mounted under the rootfs.
  local active_from_log active_under_rootfs sessions_after
  active_from_log="$(chroot_mount_count_for_distro "$distro" 2>/dev/null || echo 0)"
  active_under_rootfs="$(chroot_mount_count_under_rootfs "$distro" 2>/dev/null || echo 0)"
  sessions_after="$(chroot_session_count "$distro" 2>/dev/null || echo 0)"
  if (( sessions_after > 0 || active_from_log > 0 || active_under_rootfs > 0 )); then
    chroot_lock_release "distro-$distro"
    chroot_die "cannot remove; active state remains (sessions=$sessions_after log_mounts=$active_from_log rootfs_mounts=$active_under_rootfs). stop running tasks, then unmount again"
  fi
  if (( unmount_rc != 0 )); then
    chroot_warn "unmount/session cleanup reported issues, but no active sessions/mounts remain; continuing remove"
  fi

  [[ -d "$rootfs" ]] && chroot_safe_rm_rf "$rootfs"
  [[ -d "$state_dir" ]] && chroot_safe_rm_rf "$state_dir"

  if (( full == 1 )); then
    find "$CHROOT_CACHE_DIR" -maxdepth 1 -type f -name "$distro-*" -delete 2>/dev/null || true
  fi

  chroot_lock_release "distro-$distro"

  local alias_rc=0
  chroot_alias_remove_distro "$distro" || alias_rc=$?
  if (( alias_rc != 0 )); then
    chroot_warn "remove succeeded, but failed to update shell alias for $distro"
    chroot_log_warn remove "alias remove failed distro=$distro rc=$alias_rc"
  else
    local alias_target_label
    alias_target_label="${CHROOT_ALIAS_LAST_TARGET_LABEL:-shell profiles}"
    chroot_info "Alias $distro removed from $alias_target_label."
  fi

  chroot_log_info remove "distro=$distro full=$full"
  if (( full == 1 )); then
    chroot_info "Removed $distro (rootfs/state/cache cleaned)"
  else
    chroot_info "Removed $distro (rootfs/state cleaned)"
  fi
}
