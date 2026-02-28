chroot_is_termux_env() {
  if [[ -n "${TERMUX_VERSION:-}" ]]; then
    return 0
  fi

  if [[ -n "${PREFIX:-}" && -x "${PREFIX}/bin/pkg" ]]; then
    return 0
  fi

  if [[ -n "$CHROOT_TERMUX_PREFIX" && -x "$CHROOT_TERMUX_PREFIX/bin/pkg" ]]; then
    return 0
  fi

  if chroot_cmd_exists pkg; then
    local pkg_bin
    pkg_bin="$(command -v pkg 2>/dev/null || true)"
    [[ -n "$pkg_bin" && "$pkg_bin" == */bin/pkg ]]
    return $?
  fi

  return 1
}
