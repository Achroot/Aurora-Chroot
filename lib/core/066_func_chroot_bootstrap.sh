chroot_bootstrap() {
  chroot_detect_inside_chroot
  chroot_prepend_termux_path
  chroot_detect_bins
  if [[ "${CHROOT_RUNTIME_ROOT_RESOLVED:-0}" != "1" ]]; then
    chroot_resolve_runtime_root
  fi
  chroot_ensure_termux_dependencies
  chroot_detect_bins
  chroot_ensure_aurora_launcher || chroot_warn "failed to create aurora launcher"
  chroot_require_python
  chroot_is_root_available || chroot_die "root backend unavailable; ${CHROOT_ROOT_DIAGNOSTICS:-no diagnostics}"
  chroot_ensure_runtime_layout
  chroot_ensure_settings
}
