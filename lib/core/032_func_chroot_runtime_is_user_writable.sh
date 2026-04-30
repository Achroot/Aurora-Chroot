chroot_runtime_is_user_writable() {
  mkdir -p "$CHROOT_TMP_DIR" 2>/dev/null || return 1
  touch "$CHROOT_TMP_DIR/.write-test.$$" 2>/dev/null || return 1
  rm -f -- "$CHROOT_TMP_DIR/.write-test.$$"
}

