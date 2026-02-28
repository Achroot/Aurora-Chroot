#!/usr/bin/env bash

chroot_cmd_clear_cache() {
  local all=0
  local yes=0
  local older_days=14

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
      chroot_confirm_typed_y "Clear all cached tarballs. Type y to continue" || chroot_die "clear-cache aborted"
    fi
    chroot_lock_acquire "global" || chroot_die "failed global lock"
    find "$CHROOT_CACHE_DIR" -mindepth 1 -maxdepth 1 -type f -delete
    chroot_lock_release "global"
    chroot_log_info cache "clear all"
    chroot_info "Cache cleared"
    return 0
  fi

  chroot_lock_acquire "global" || chroot_die "failed global lock"
  find "$CHROOT_CACHE_DIR" -mindepth 1 -maxdepth 1 -type f -mtime "+$older_days" -delete
  chroot_lock_release "global"
  chroot_log_info cache "clear older-than=$older_days"
  chroot_info "Cleared cache files older than $older_days days"
}
