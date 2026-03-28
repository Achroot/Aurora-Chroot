chroot_pkg_install_or_fallback() {
  local pkg="$1"
  shift || true

  if chroot_pkg_install_one "$pkg"; then
    return 0
  fi

  local alt
  for alt in "$@"; do
    if chroot_pkg_install_one "$alt"; then
      return 0
    fi
  done
  return 1
}

