chroot_gui_display_value() {
  if chroot_x11_enabled; then
    printf ':0\n'
    return 0
  fi
  return 1
}

chroot_x11_dpi_value() {
  local dpi
  chroot_x11_enabled || return 1
  dpi="$(chroot_setting_get x11_dpi 2>/dev/null || true)"
  [[ "$dpi" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$dpi"
}

chroot_gui_env_pairs() {
  local display_value dpi_value

  display_value="$(chroot_gui_display_value || true)"
  if [[ -n "$display_value" ]]; then
    printf 'DISPLAY=%s\n' "$display_value"
  fi

  dpi_value="$(chroot_x11_dpi_value || true)"
  if [[ -n "$dpi_value" ]]; then
    printf 'AURORA_X11_DPI=%s\n' "$dpi_value"
    printf 'QT_FONT_DPI=%s\n' "$dpi_value"
  fi
}
