chroot_die() {
  chroot_err "$*"
  if declare -F chroot_lock_release_held >/dev/null 2>&1; then
    chroot_lock_release_held >/dev/null 2>&1 || true
  fi
  exit 1
}

