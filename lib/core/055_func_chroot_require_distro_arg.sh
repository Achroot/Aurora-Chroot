chroot_require_distro_arg() {
  local distro="${1:-}"
  [[ -n "$distro" ]] || chroot_die "distro argument is required"
  [[ "$distro" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || chroot_die "invalid distro id: $distro"
}

