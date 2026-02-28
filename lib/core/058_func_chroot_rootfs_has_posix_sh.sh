chroot_rootfs_has_posix_sh() {
  local dir="$1"
  chroot_run_root test -x "$dir/bin/sh" >/dev/null 2>&1 || chroot_run_root test -x "$dir/usr/bin/sh" >/dev/null 2>&1
}

