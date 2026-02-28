#!/usr/bin/env bash

chroot_nuke_confirm_yes_no() {
  local answer
  while true; do
    printf 'Proceed with NUKE? [y/N]: ' >&2
    read -r answer
    case "$answer" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO|'') return 1 ;;
    esac
    printf 'Please answer y or n.\n' >&2
  done
}

chroot_nuke_remove_launchers() {
  local home_dir
  home_dir="${HOME:-$CHROOT_TERMUX_HOME_DEFAULT}"

  local -a candidates=(
    "$CHROOT_TERMUX_BIN/$CHROOT_AURORA_LAUNCHER_NAME"
    "$CHROOT_TERMUX_HOME_DEFAULT/bin/$CHROOT_AURORA_LAUNCHER_NAME"
    "$home_dir/bin/$CHROOT_AURORA_LAUNCHER_NAME"
  )

  local p removed=0
  for p in "${candidates[@]}"; do
    [[ -e "$p" ]] || continue
    rm -f -- "$p" 2>/dev/null || chroot_run_root rm -f -- "$p" 2>/dev/null || true
    if [[ ! -e "$p" ]]; then
      chroot_info "Removed launcher: $p"
      removed=1
    else
      chroot_warn "Could not remove launcher: $p"
    fi
  done

  if (( removed == 0 )); then
    chroot_info "No aurora launcher file found to remove."
  fi
}

chroot_nuke_runtime_root_is_safe() {
  local path="$1"
  chroot_runtime_root_is_absolute "$path" || return 1
  chroot_runtime_root_is_safe_path "$path" || return 1
  return 0
}

chroot_cmd_nuke() {
  local yes=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes|-y) yes=1 ;;
      *) chroot_die "unknown nuke arg: $1" ;;
    esac
    shift
  done

  chroot_preflight_hard_fail

  chroot_warn "DANGER: NUKE removes all Aurora runtime data."
  chroot_warn "Target runtime root: $CHROOT_RUNTIME_ROOT"
  chroot_warn "This removes all distros, backups, cache, manifests, logs, and settings."
  chroot_warn "Only bash path/to/chroot is intended to remain."

  if (( yes == 0 )); then
    chroot_nuke_confirm_yes_no || chroot_die "nuke aborted"
  fi

  local global_lock=0
  chroot_nuke_fail() {
    if (( global_lock == 1 )); then
      chroot_lock_release "global" >/dev/null 2>&1 || true
      global_lock=0
    fi
    chroot_die "$*"
  }

  chroot_lock_acquire "global" || chroot_die "failed global lock"
  global_lock=1

  local -a distros=()
  local distro

  chroot_info "Step 1/7: listing installed distros..."
  while IFS= read -r distro; do
    [[ -n "$distro" ]] || continue
    distros+=("$distro")
  done < <(chroot_installed_distros || true)
  if (( ${#distros[@]} == 0 )); then
    chroot_info "No installed distros found."
  else
    chroot_info "Found ${#distros[@]} installed distro(s): ${distros[*]}"
  fi

  chroot_info "Step 2/7: terminating active sessions..."
  for distro in "${distros[@]}"; do
    local sessions_before sessions_after
    sessions_before="$(chroot_session_count "$distro" 2>/dev/null || echo 0)"
    if (( sessions_before > 0 )); then
      local kill_out kill_rc targeted term_sent kill_sent remaining cleaned skipped_identity
      kill_rc=0
      kill_out="$(chroot_session_kill_all "$distro" 3)" || kill_rc=$?
      IFS=$'\t' read -r targeted term_sent kill_sent remaining cleaned skipped_identity <<<"$kill_out"
      targeted="${targeted:-0}"
      term_sent="${term_sent:-0}"
      kill_sent="${kill_sent:-0}"
      remaining="${remaining:-0}"
      cleaned="${cleaned:-0}"
      skipped_identity="${skipped_identity:-0}"
      chroot_info "Session cleanup for $distro: targeted=$targeted term=$term_sent kill=$kill_sent remaining=$remaining cleaned=$cleaned"
      if (( skipped_identity > 0 )); then
        chroot_warn "Skipped $skipped_identity session entries for $distro (missing identity metadata)."
      fi
      if (( kill_rc != 0 )); then
        chroot_warn "Session cleanup returned non-zero for $distro."
      fi
    fi
    sessions_after="$(chroot_session_count "$distro" 2>/dev/null || echo 0)"
    if (( sessions_after > 0 )); then
      chroot_nuke_fail "nuke blocked: active sessions remain for $distro = $sessions_after"
    fi
  done
  chroot_info "No active sessions remain."

  chroot_info "Step 3/7: unmounting each distro..."
  for distro in "${distros[@]}"; do
    chroot_info "Unmounting: $distro"
    chroot_cmd_unmount "$distro" --kill-sessions || chroot_nuke_fail "nuke blocked: unmount failed for $distro"

    local active_from_log active_under_rootfs
    active_from_log="$(chroot_mount_count_for_distro "$distro" 2>/dev/null || echo 0)"
    active_under_rootfs="$(chroot_mount_count_under_rootfs "$distro" 2>/dev/null || echo 0)"
    if (( active_from_log > 0 || active_under_rootfs > 0 )); then
      chroot_nuke_fail "nuke blocked: mounts still active for $distro (log=$active_from_log rootfs=$active_under_rootfs)"
    fi
  done
  chroot_info "Unmount checks passed."

  chroot_info "Step 4/7: removing distro rootfs/state data..."
  for distro in "${distros[@]}"; do
    local rootfs state_dir
    rootfs="$(chroot_distro_rootfs_dir "$distro")"
    state_dir="$(chroot_distro_state_dir "$distro")"
    [[ -d "$rootfs" ]] && chroot_safe_rm_rf "$rootfs"
    [[ -d "$state_dir" ]] && chroot_safe_rm_rf "$state_dir"
    find "$CHROOT_CACHE_DIR" -maxdepth 1 -type f -name "$distro-*" -delete 2>/dev/null || true
    chroot_info "Removed distro data: $distro"
  done

  chroot_info "Step 5/7: final mount safety check under runtime root..."
  local active_under_runtime
  active_under_runtime="$(chroot_mount_count_under_path "$CHROOT_RUNTIME_ROOT" 2>/dev/null || echo 0)"
  if (( active_under_runtime > 0 )); then
    chroot_nuke_fail "nuke blocked: mounts still active under runtime root ($active_under_runtime)"
  fi
  chroot_info "No active mounts under runtime root."

  chroot_info "Step 6/7: removing runtime root contents..."
  chroot_nuke_runtime_root_is_safe "$CHROOT_RUNTIME_ROOT" || chroot_nuke_fail "refusing nuke on unsafe runtime root: $CHROOT_RUNTIME_ROOT"
  local removed_root=0

  # Try user-context cleanup first, then root-context cleanup.
  if rm -rf -- "$CHROOT_RUNTIME_ROOT" >/dev/null 2>&1; then
    removed_root=1
  fi

  if [[ -d "$CHROOT_RUNTIME_ROOT" ]]; then
    find "$CHROOT_RUNTIME_ROOT" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + >/dev/null 2>&1 || true
  fi

  if [[ -e "$CHROOT_RUNTIME_ROOT" ]]; then
    chroot_warn "user-context runtime cleanup incomplete; trying root-context cleanup..."
    chroot_run_root rm -rf -- "$CHROOT_RUNTIME_ROOT" >/dev/null 2>&1 || true
  fi

  if [[ -d "$CHROOT_RUNTIME_ROOT" ]]; then
    chroot_run_root find "$CHROOT_RUNTIME_ROOT" -mindepth 1 -maxdepth 1 -exec rm -rf -- '{}' '+' >/dev/null 2>&1 || true
  fi

  if [[ -e "$CHROOT_RUNTIME_ROOT" ]]; then
    if find "$CHROOT_RUNTIME_ROOT" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
      chroot_nuke_fail "failed to clear runtime root: $CHROOT_RUNTIME_ROOT"
    fi
    chroot_info "Runtime root emptied: $CHROOT_RUNTIME_ROOT (directory preserved)"
  else
    (( removed_root == 1 )) || true
    chroot_info "Runtime root removed: $CHROOT_RUNTIME_ROOT"
  fi

  chroot_info "Step 7/7: removing aurora launcher(s)..."
  chroot_nuke_remove_launchers

  chroot_lock_release "global" >/dev/null 2>&1 || true
  global_lock=0

  chroot_info "NUKE complete. Remaining script should be: bash path/to/chroot"
}
