chroot_detect_pick_path() {
  local override="${1:-}"
  local lookup="$2"
  shift 2

  local found="" candidate
  if [[ -n "$override" ]]; then
    if [[ "$override" == */* ]]; then
      if [[ -x "$override" ]]; then
        printf '%s\n' "$override"
        return 0
      fi
    else
      found="$(command -v "$override" 2>/dev/null || true)"
      if [[ -n "$found" ]]; then
        printf '%s\n' "$found"
        return 0
      fi
    fi
  fi

  for candidate in "$@"; do
    [[ -n "$candidate" ]] || continue
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  found="$(command -v "$lookup" 2>/dev/null || true)"
  if [[ -n "$found" ]]; then
    printf '%s\n' "$found"
    return 0
  fi
  return 1
}

chroot_detect_box_applet() {
  local box_bin="$1"
  local applet="$2"
  [[ -n "$box_bin" && -x "$box_bin" ]] || {
    printf '0\n'
    return 0
  }
  if "$box_bin" "$applet" --help >/dev/null 2>&1; then
    printf '1\n'
  else
    printf '0\n'
  fi
}

chroot_detect_bins() {
  local system_bin system_xbin
  system_bin="${CHROOT_SYSTEM_BIN_DEFAULT:-/system/bin}"
  system_xbin="${CHROOT_SYSTEM_XBIN_DEFAULT:-/system/xbin}"

  CHROOT_SYSTEM_CHROOT="$(chroot_detect_pick_path "${CHROOT_CHROOT_BIN:-${CHROOT_SYSTEM_CHROOT:-}}" "chroot" \
    "$system_bin/chroot" "$system_xbin/chroot" "/bin/chroot" "/usr/bin/chroot" || true)"
  CHROOT_SYSTEM_MOUNT="$(chroot_detect_pick_path "${CHROOT_MOUNT_BIN:-${CHROOT_SYSTEM_MOUNT:-}}" "mount" \
    "$system_bin/mount" "$system_xbin/mount" "/bin/mount" "/usr/bin/mount" || true)"
  CHROOT_SYSTEM_UMOUNT="$(chroot_detect_pick_path "${CHROOT_UMOUNT_BIN:-${CHROOT_SYSTEM_UMOUNT:-}}" "umount" \
    "$system_bin/umount" "$system_xbin/umount" "/bin/umount" "/usr/bin/umount" || true)"
  CHROOT_HOST_SH="$(chroot_detect_pick_path "${CHROOT_SH_BIN:-${CHROOT_HOST_SH:-}}" "sh" \
    "$system_bin/sh" "/bin/sh" "$CHROOT_TERMUX_BIN/sh" "/usr/bin/sh" || true)"
  CHROOT_BUSYBOX_BIN="$(chroot_detect_pick_path "${CHROOT_BUSYBOX_OVERRIDE:-${CHROOT_BUSYBOX_BIN:-}}" "busybox" \
    "$system_bin/busybox" "$system_xbin/busybox" "$CHROOT_TERMUX_BIN/busybox" "/bin/busybox" "/usr/bin/busybox" || true)"
  CHROOT_TOYBOX_BIN="$(chroot_detect_pick_path "${CHROOT_TOYBOX_OVERRIDE:-${CHROOT_TOYBOX_BIN:-}}" "toybox" \
    "$system_bin/toybox" "$system_xbin/toybox" "$CHROOT_TERMUX_BIN/toybox" "/bin/toybox" "/usr/bin/toybox" || true)"

  CHROOT_BUSYBOX_HAS_CHROOT="$(chroot_detect_box_applet "$CHROOT_BUSYBOX_BIN" chroot)"
  CHROOT_BUSYBOX_HAS_MOUNT="$(chroot_detect_box_applet "$CHROOT_BUSYBOX_BIN" mount)"
  CHROOT_BUSYBOX_HAS_UMOUNT="$(chroot_detect_box_applet "$CHROOT_BUSYBOX_BIN" umount)"
  CHROOT_TOYBOX_HAS_CHROOT="$(chroot_detect_box_applet "$CHROOT_TOYBOX_BIN" chroot)"
  CHROOT_TOYBOX_HAS_MOUNT="$(chroot_detect_box_applet "$CHROOT_TOYBOX_BIN" mount)"
  CHROOT_TOYBOX_HAS_UMOUNT="$(chroot_detect_box_applet "$CHROOT_TOYBOX_BIN" umount)"

  CHROOT_TAR_BIN="$(command -v tar 2>/dev/null || true)"
  CHROOT_CURL_BIN="$(command -v curl 2>/dev/null || true)"
  CHROOT_SHA256_BIN="$(command -v sha256sum 2>/dev/null || true)"
  CHROOT_DIALOG_BIN="$(command -v dialog 2>/dev/null || true)"
  CHROOT_ZSTD_BIN="$(command -v zstd 2>/dev/null || true)"
  CHROOT_XZ_BIN="$(command -v xz 2>/dev/null || true)"
  CHROOT_BASH_BIN="$(command -v bash 2>/dev/null || true)"
  CHROOT_PKG_BIN="$(command -v pkg 2>/dev/null || true)"
  CHROOT_APT_BIN="$(command -v apt 2>/dev/null || true)"
}
