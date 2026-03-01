chroot_service_desktop_mark_error() {
  local distro="$1"
  local message="$2"
  if chroot_service_desktop_config_exists "$distro"; then
    chroot_service_desktop_config_set_fields "$distro" "last_error" "$message"
  fi
}

chroot_service_desktop_session_id() {
  printf 'svc-%s\n' "$CHROOT_SERVICE_DESKTOP_SERVICE_NAME"
}

chroot_service_desktop_session_is_tracked() {
  local distro="$1"
  local wanted_sid="${2:-$(chroot_service_desktop_session_id)}"
  local sid=""

  while IFS=$'\t' read -r sid _; do
    [[ -n "$sid" ]] || continue
    if [[ "$sid" == "$wanted_sid" ]]; then
      return 0
    fi
  done < <(chroot_session_list_details_tsv "$distro")

  return 1
}

chroot_service_desktop_require_installed() {
  local distro="$1"
  local installed incomplete

  installed="$(chroot_service_desktop_config_get "$distro" "installed" 2>/dev/null || true)"
  incomplete="$(chroot_service_desktop_config_get "$distro" "incomplete" 2>/dev/null || true)"

  if [[ "$installed" != "true" || "$incomplete" == "true" ]]; then
    chroot_die "desktop is not fully installed for $distro; run: service $distro install desktop --profile <xfce|lxqt>"
  fi
  if [[ ! -f "$(chroot_service_def_file "$distro" "$CHROOT_SERVICE_DESKTOP_SERVICE_NAME")" ]]; then
    chroot_die "desktop service definition is missing for $distro; reinstall the desktop service"
  fi
  if [[ ! -x "$(chroot_service_desktop_rootfs_launcher_file "$distro")" ]]; then
    chroot_die "desktop launcher is missing for $distro; reinstall the desktop service"
  fi
}

chroot_service_desktop_require_session_command() {
  local distro="$1"
  local profile_id exec_cmd rootfs

  profile_id="$(chroot_service_desktop_config_get "$distro" "profile_id" 2>/dev/null || true)"
  exec_cmd="$(chroot_service_desktop_profile_exec_cmd "$profile_id" 2>/dev/null || true)"
  [[ -n "$exec_cmd" ]] || chroot_die "desktop profile metadata is missing for $distro; reinstall the desktop service"

  rootfs="$(chroot_distro_rootfs_dir "$distro")"
  chroot_cmd_mount "$distro"
  if ! chroot_run_chroot_env "$rootfs" \
    "HOME=/root" \
    "TERM=${TERM:-xterm-256color}" \
    "PATH=$(chroot_chroot_default_path)" \
    "LANG=${LANG:-C.UTF-8}" \
    -- /bin/sh -lc "command -v $exec_cmd >/dev/null 2>&1"; then
    chroot_service_desktop_mark_error "$distro" "desktop session command '$exec_cmd' is missing inside $distro; repair packages and install desktop again"
    chroot_die "desktop session command '$exec_cmd' is missing inside $distro; repair packages and install desktop again"
  fi
}

chroot_service_desktop_start() {
  local distro="$1"
  local running_pid

  chroot_service_desktop_require_installed "$distro"
  if ! chroot_x11_enabled; then
    chroot_service_desktop_mark_error "$distro" "desktop start requires settings x11=true"
    chroot_die "desktop start requires settings x11=true"
  fi
  chroot_service_desktop_refresh_assets_from_config "$distro" >/dev/null 2>&1 || true
  chroot_service_desktop_require_session_command "$distro"
  if ! chroot_x11_bin_path >/dev/null 2>&1; then
    chroot_service_desktop_mark_error "$distro" "desktop start requires the termux-x11 binary on host"
    chroot_die "desktop start requires the termux-x11 binary on host"
  fi
  if ! chroot_x11_enable_display0 18; then
    chroot_service_desktop_mark_error "$distro" "failed to prepare Termux-X11 display :0"
    chroot_die "failed to prepare Termux-X11 display :0"
  fi

  if running_pid="$(chroot_service_get_pid "$distro" "$CHROOT_SERVICE_DESKTOP_SERVICE_NAME" 2>/dev/null || true)" && [[ -n "$running_pid" ]]; then
    chroot_info "Service 'desktop' is already running (PID: $running_pid)"
    chroot_service_desktop_config_set_fields "$distro" "last_error" ""
    chroot_info "Open Termux:X11 now to view the desktop GUI."
    return 0
  fi

  chroot_service_desktop_runtime_log_clear "$distro"
  chroot_service_start "$distro" "$CHROOT_SERVICE_DESKTOP_SERVICE_NAME" "" "$(chroot_service_desktop_runtime_log_file "$distro")"
  chroot_service_desktop_config_set_fields "$distro" \
    "last_started_at" "$(chroot_now_ts)" \
    "last_error" ""
  chroot_info "Open Termux:X11 now to view the desktop GUI."
}

chroot_service_desktop_stop() {
  local distro="$1"
  chroot_service_stop "$distro" "$CHROOT_SERVICE_DESKTOP_SERVICE_NAME"
  if chroot_service_desktop_config_exists "$distro"; then
    chroot_service_desktop_config_set_fields "$distro" "last_stopped_at" "$(chroot_now_ts)" "last_error" ""
  fi
}

chroot_service_desktop_restart() {
  local distro="$1"
  chroot_service_desktop_stop "$distro"
  chroot_service_desktop_start "$distro"
}
