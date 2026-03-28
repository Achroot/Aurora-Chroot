chroot_require_python() {
  chroot_detect_python
  [[ -n "$CHROOT_PYTHON_BIN" ]] || chroot_die "python is required but not found"
}

