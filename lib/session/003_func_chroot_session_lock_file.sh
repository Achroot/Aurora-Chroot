chroot_session_lock_file() {
  local distro="$1"
  printf '%s.lock' "$(chroot_distro_session_file "$distro")"
}

