chroot_termux_prefix_has_layout() {
  local prefix="${1:-}"
  case "$prefix" in
    /data/data/*/files/usr|/data/user/*/*/files/usr) ;;
    *) return 1 ;;
  esac
  [[ -e "$prefix/bin/pkg" ]]
}

chroot_termux_prefix_runs() {
  local prefix="${1:-}"
  chroot_termux_prefix_has_layout "$prefix" || return 1
  [[ -x "$prefix/bin/sh" ]] || return 1
  "$prefix/bin/sh" -c ":" >/dev/null 2>&1
}

chroot_is_termux_env() {
  if [[ -n "${PREFIX:-}" ]] && chroot_termux_prefix_runs "$PREFIX"; then
    return 0
  fi

  if [[ -n "$CHROOT_TERMUX_PREFIX" ]] && chroot_termux_prefix_runs "$CHROOT_TERMUX_PREFIX"; then
    return 0
  fi

  if [[ -n "${TERMUX_VERSION:-}" ]] && chroot_cmd_exists pkg; then
    local pkg_bin pkg_prefix
    pkg_bin="$(command -v pkg 2>/dev/null || true)"
    if [[ -n "$pkg_bin" && "$pkg_bin" == */bin/pkg ]]; then
      pkg_prefix="${pkg_bin%/bin/pkg}"
      chroot_termux_prefix_runs "$pkg_prefix"
      return $?
    fi
  fi

  return 1
}
