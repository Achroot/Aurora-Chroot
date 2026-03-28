chroot_distro_state_dir() {
  local distro="$1"
  printf '%s/state/%s' "$CHROOT_RUNTIME_ROOT" "$distro"
}

