chroot_detect_inside_chroot() {
  if [[ "$CHROOT_INSIDE_CHROOT" == "0" || "$CHROOT_INSIDE_CHROOT" == "1" ]]; then
    return 0
  fi

  if chroot_is_termux_env; then
    CHROOT_INSIDE_CHROOT="0"
    return 0
  fi

  if chroot_cmd_exists getprop; then
    CHROOT_INSIDE_CHROOT="0"
    return 0
  fi

  if [[ -r "/proc/version" ]] && grep -qi "android" "/proc/version" 2>/dev/null; then
    CHROOT_INSIDE_CHROOT="0"
    return 0
  fi

  CHROOT_INSIDE_CHROOT="1"
}
