chroot_ensure_distro_dirs() {
  local distro="$1"
  mkdir -p "$(chroot_distro_state_dir "$distro")/mounts"
  mkdir -p "$(chroot_distro_state_dir "$distro")/sessions"
}

