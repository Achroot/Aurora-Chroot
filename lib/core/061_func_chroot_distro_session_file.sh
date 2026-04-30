chroot_distro_session_file() {
  local distro="$1"
  printf '%s/state/%s/sessions/current.json' "$CHROOT_RUNTIME_ROOT" "$distro"
}

