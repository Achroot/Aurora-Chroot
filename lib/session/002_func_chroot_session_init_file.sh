chroot_session_init_file() {
  local distro="$1"
  local sf
  sf="$(chroot_distro_session_file "$distro")"
  mkdir -p "$(dirname "$sf")"
  [[ -f "$sf" ]] || printf '[]\n' >"$sf"
}

