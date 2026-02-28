chroot_ensure_termux_dependencies() {
  if chroot_is_inside_chroot || ! chroot_is_termux_env; then
    return 0
  fi

  chroot_prepend_termux_path
  chroot_detect_bins

  if [[ "$CHROOT_AUTO_INSTALL_DEPS" != "1" ]]; then
    return 0
  fi

  local need_bash=0 need_coreutils=0 need_curl=0 need_tar=0 need_python=0 need_dialog=0 need_zstd=0 need_xz=0

  chroot_cmd_exists bash || need_bash=1
  chroot_cmd_exists sha256sum || need_coreutils=1
  chroot_cmd_exists curl || need_curl=1
  chroot_cmd_exists tar || need_tar=1
  if ! chroot_cmd_exists python3 && ! chroot_cmd_exists python; then
    need_python=1
  fi
  chroot_cmd_exists dialog || need_dialog=1
  chroot_cmd_exists zstd || need_zstd=1
  chroot_cmd_exists xz || need_xz=1

  if (( need_bash + need_coreutils + need_curl + need_tar + need_python + need_dialog + need_zstd + need_xz == 0 )); then
    return 0
  fi

  [[ -n "$CHROOT_PKG_BIN" || -n "$CHROOT_APT_BIN" ]] || chroot_die "pkg/apt not found in Termux; cannot auto-install dependencies"

  chroot_info "Checking Termux dependencies..."
  local dep_help="dependency install failed; run 'termux-change-repo' then 'pkg update && pkg install -y bash coreutils curl tar python dialog zstd xz-utils'"
  (( need_bash == 0 )) || chroot_pkg_install_or_fallback bash || chroot_die "$dep_help"
  (( need_coreutils == 0 )) || chroot_pkg_install_or_fallback coreutils || chroot_die "$dep_help"
  (( need_curl == 0 )) || chroot_pkg_install_or_fallback curl || chroot_die "$dep_help"
  (( need_tar == 0 )) || chroot_pkg_install_or_fallback tar || chroot_die "$dep_help"
  (( need_python == 0 )) || chroot_pkg_install_or_fallback python || chroot_die "$dep_help"
  (( need_dialog == 0 )) || chroot_pkg_install_or_fallback dialog || chroot_die "$dep_help"
  (( need_zstd == 0 )) || chroot_pkg_install_or_fallback zstd || chroot_die "$dep_help"
  (( need_xz == 0 )) || chroot_pkg_install_or_fallback xz-utils xz || chroot_die "$dep_help"

  hash -r
  chroot_detect_bins
  chroot_detect_python
}

