chroot_warn() {
  if declare -F chroot_log_warn >/dev/null 2>&1; then
    chroot_log_warn stderr "$*" || true
  fi
  printf 'WARN: %s\n' "$*" >&2
}
