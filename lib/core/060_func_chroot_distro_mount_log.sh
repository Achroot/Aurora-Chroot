chroot_distro_mount_log() {
  local distro="$1"
  printf '%s/state/%s/mounts/current.log' "$CHROOT_RUNTIME_ROOT" "$distro"
}

