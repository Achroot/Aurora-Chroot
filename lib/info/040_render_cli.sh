chroot_info_render_human() {
  local payload_json="${1:-}"
  local width
  width="$(chroot_info_render_width)"

  CHROOT_INFO_RENDER_PAYLOAD="$payload_json" \
  "$CHROOT_PYTHON_BIN" - render \
    "$CHROOT_RUNTIME_ROOT" \
    "$CHROOT_ROOTFS_DIR" \
    "$CHROOT_STATE_DIR" \
    "full" \
    "" \
    "$width" < <(chroot_info_python_emit)
}
