chroot_is_root_available() {
  if [[ "$(id -u)" == "0" ]]; then
    return 0
  fi
  chroot_resolve_root_launcher || return 1
  chroot_run_root_cmd "id -u >/dev/null 2>&1" >/dev/null 2>&1
}
