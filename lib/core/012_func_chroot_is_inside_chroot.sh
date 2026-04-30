chroot_is_inside_chroot() {
  chroot_detect_inside_chroot
  [[ "$CHROOT_INSIDE_CHROOT" == "1" ]]
}

