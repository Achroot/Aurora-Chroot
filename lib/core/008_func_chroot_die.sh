chroot_die() {
  if declare -F chroot_log_internal_command_fail >/dev/null 2>&1; then
    chroot_log_internal_command_fail "$*" || true
  fi
  if declare -F chroot_log_command_error >/dev/null 2>&1; then
    chroot_log_command_error "$*" || true
  fi
  CHROOT_LOG_SUPPRESS_STDERR_EVENT=1 chroot_err "$*"
  if declare -F chroot_lock_release_held >/dev/null 2>&1; then
    chroot_lock_release_held >/dev/null 2>&1 || true
  fi
  exit 1
}
