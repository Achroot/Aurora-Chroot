#!/usr/bin/env bash

chroot_clear_cache_delete_dir_contents() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  chroot_run_root find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf -- '{}' '+' >/dev/null 2>&1 || true
}

chroot_clear_cache_delete_staging_rootfs_dirs() {
  [[ -d "$CHROOT_ROOTFS_DIR" ]] || return 0
  chroot_run_root find "$CHROOT_ROOTFS_DIR" -mindepth 1 -maxdepth 1 -type d -name '*.staging.*' -exec rm -rf -- '{}' '+' >/dev/null 2>&1 || true
}

chroot_clear_cache_other_lock_names() {
  local lock_path lock_name
  chroot_lock_repair_stale >/dev/null 2>&1 || true

  for lock_path in "$CHROOT_LOCK_DIR"/*.lockdir; do
    [[ -e "$lock_path" ]] || continue
    lock_name="$(basename "$lock_path" .lockdir)"
    [[ "$lock_name" == "global" ]] && continue
    printf '%s\n' "$lock_name"
  done
}

chroot_clear_cache_prune_stale_runtime_logs() {
  local distro mount_log mount_dir desktop_log desktop_dir desktop_cfg running_pid

  while IFS= read -r distro; do
    [[ -n "$distro" ]] || continue

    mount_log="$(chroot_distro_mount_log "$distro")"
    if [[ -f "$mount_log" ]]; then
      if [[ "$(chroot_mount_count_for_distro "$distro" 2>/dev/null || echo 0)" == "0" ]]; then
        chroot_run_root rm -f -- "$mount_log" >/dev/null 2>&1 || true
        mount_dir="$(dirname "$mount_log")"
        chroot_run_root rmdir "$mount_dir" >/dev/null 2>&1 || true
      fi
    fi

    if declare -F chroot_service_desktop_runtime_log_file >/dev/null 2>&1; then
      desktop_log="$(chroot_service_desktop_runtime_log_file "$distro" 2>/dev/null || true)"
      if [[ -n "$desktop_log" && -f "$desktop_log" ]]; then
        running_pid=""
        if declare -F chroot_service_get_pid >/dev/null 2>&1; then
          running_pid="$(chroot_service_get_pid "$distro" "desktop" 2>/dev/null || true)"
        fi
        if [[ -z "$running_pid" ]]; then
          chroot_run_root rm -f -- "$desktop_log" >/dev/null 2>&1 || true
          desktop_dir="$(chroot_service_desktop_state_dir "$distro" 2>/dev/null || true)"
          desktop_cfg="$(chroot_service_desktop_config_file "$distro" 2>/dev/null || true)"
          if [[ -n "$desktop_dir" && ( -z "$desktop_cfg" || ! -f "$desktop_cfg" ) ]]; then
            chroot_run_root rmdir "$desktop_dir" >/dev/null 2>&1 || true
          fi
        fi
      fi
    fi
  done < <(chroot_installed_distros || true)
}

chroot_cmd_clear_cache() {
  local all=0
  local yes=0
  local older_days=14
  local other_locks=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all) all=1 ;;
      --yes|-y) yes=1 ;;
      --older-than)
        shift
        [[ $# -gt 0 ]] || chroot_die "--older-than requires value"
        older_days="$1"
        [[ "$older_days" =~ ^[0-9]+$ ]] || chroot_die "--older-than must be a positive integer"
        (( older_days > 0 )) || chroot_die "--older-than must be greater than zero"
        ;;
      *) chroot_die "unknown clear-cache arg: $1" ;;
    esac
    shift
  done

  chroot_preflight_hard_fail

  if (( all == 1 )); then
    if (( yes == 0 )); then
      chroot_confirm_typed_y "Clear all cached downloads and disposable runtime files. Type y to continue" || chroot_die "clear-cache aborted"
    fi
    chroot_lock_acquire "global" || chroot_die "failed global lock"

    chroot_clear_cache_delete_dir_contents "$CHROOT_CACHE_DIR"
    chroot_clear_cache_prune_stale_runtime_logs

    other_locks="$(chroot_clear_cache_other_lock_names || true)"
    if [[ -z "$other_locks" ]]; then
      chroot_clear_cache_delete_dir_contents "$CHROOT_TMP_DIR"
      chroot_clear_cache_delete_staging_rootfs_dirs
    else
      chroot_warn "Skipped tmp workspace and interrupted install staging cleanup because other Aurora locks are active: $(printf '%s' "$other_locks" | paste -sd ', ' -)"
    fi

    chroot_lock_release "global"
    chroot_log_info cache "clear all artifacts=downloads,tmp,staging-dirs,stale-runtime-logs"
    if [[ -z "$other_locks" ]]; then
      chroot_info "Cleared cached downloads, tmp workspace, interrupted install staging dirs, and stale runtime logs"
    else
      chroot_info "Cleared cached downloads and stale runtime logs"
    fi
    return 0
  fi

  chroot_lock_acquire "global" || chroot_die "failed global lock"
  find "$CHROOT_CACHE_DIR" -mindepth 1 -maxdepth 1 -type f -mtime "+$older_days" -delete
  chroot_lock_release "global"
  chroot_log_info cache "clear older-than=$older_days"
  chroot_info "Cleared cache files older than $older_days days"
}
