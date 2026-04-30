chroot_err() {
  if [[ "${CHROOT_LOG_SUPPRESS_STDERR_EVENT:-0}" != "1" ]] && declare -F chroot_log_error >/dev/null 2>&1; then
    chroot_log_error stderr "$*" || true
  fi
  printf 'ERROR: %s\n' "$*" >&2
}
