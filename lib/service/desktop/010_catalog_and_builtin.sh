chroot_service_desktop_profile_ids() {
  printf 'lxqt\n'
  printf 'xfce\n'
}

chroot_service_desktop_profile_is_valid() {
  case "${1:-}" in
    lxqt|xfce) return 0 ;;
    *) return 1 ;;
  esac
}

chroot_service_desktop_require_profile_id() {
  local profile_id="${1:-}"
  chroot_service_desktop_profile_is_valid "$profile_id" || chroot_die "desktop profile must be one of: lxqt, xfce"
}

chroot_service_desktop_profile_name() {
  case "${1:-}" in
    lxqt) printf 'LXQt\n' ;;
    xfce) printf 'XFCE\n' ;;
    *) return 1 ;;
  esac
}

chroot_service_desktop_profile_exec_cmd() {
  case "${1:-}" in
    lxqt) printf 'startlxqt\n' ;;
    xfce) printf 'startxfce4\n' ;;
    *) return 1 ;;
  esac
}

chroot_service_desktop_session_slug() {
  case "${1:-}" in
    lxqt) printf 'lxqt\n' ;;
    xfce) printf 'xfce\n' ;;
    *) return 1 ;;
  esac
}
