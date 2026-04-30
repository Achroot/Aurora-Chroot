chroot_service_desktop_remove_assets() {
  local distro="$1"
  local launcher_path profile_dir

  launcher_path="$(chroot_service_desktop_rootfs_launcher_file "$distro")"
  profile_dir="$(chroot_service_desktop_rootfs_config_dir "$distro")"

  chroot_run_root rm -f -- "$launcher_path" >/dev/null 2>&1 || true
  chroot_run_root rm -rf -- "$profile_dir" >/dev/null 2>&1 || true
}

chroot_service_desktop_remove() {
  local distro="$1"
  chroot_log_run_internal_command service service.stop "$distro" "$distro" service stop "$CHROOT_SERVICE_DESKTOP_SERVICE_NAME" -- chroot_service_desktop_stop "$distro" >/dev/null 2>&1 || true
  chroot_service_remove_def "$distro" "$CHROOT_SERVICE_DESKTOP_SERVICE_NAME" >/dev/null 2>&1 || true
  chroot_service_desktop_config_remove "$distro"
  chroot_service_desktop_remove_assets "$distro"
  chroot_info "Removed managed desktop service and assets from $distro"
}
