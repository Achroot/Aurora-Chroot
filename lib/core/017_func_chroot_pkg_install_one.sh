chroot_pkg_install_one() {
  local pkg="$1"
  local rc=1

  if [[ -n "$CHROOT_PKG_BIN" ]]; then
    if "$CHROOT_PKG_BIN" install -y "$pkg"; then
      return 0
    fi
    rc=$?
  fi

  if [[ -n "$CHROOT_APT_BIN" ]]; then
    if "$CHROOT_APT_BIN" install -y "$pkg"; then
      return 0
    fi
    rc=$?
  fi

  return "$rc"
}

