chroot_detect_python() {
  if chroot_cmd_exists python3; then
    CHROOT_PYTHON_BIN="$(command -v python3)"
  elif chroot_cmd_exists python; then
    CHROOT_PYTHON_BIN="$(command -v python)"
  else
    CHROOT_PYTHON_BIN=""
  fi
}

