chroot_distro_rootfs_dir() {
  local distro="$1"
  printf '%s/rootfs/%s' "$CHROOT_RUNTIME_ROOT" "$distro"
}

