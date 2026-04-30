chroot_distro_state_file() {
  local distro="$1"
  printf '%s/state/%s/state.json' "$CHROOT_RUNTIME_ROOT" "$distro"
}

