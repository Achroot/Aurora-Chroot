chroot_is_root_available() {
  if [[ "$(id -u)" == "0" ]]; then
    return 0
  fi
  chroot_resolve_root_launcher || return 1
  [[ -n "${CHROOT_ROOT_LAUNCHER_BIN:-}" ]] || return 1
  chroot_root_launcher_probe "$CHROOT_ROOT_LAUNCHER_BIN" "${CHROOT_ROOT_LAUNCHER_SUBCMD:-}"
}
