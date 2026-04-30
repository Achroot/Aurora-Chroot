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

chroot_detect_command_runs() {
  [[ $# -gt 0 ]] || return 1
  "$@" >/dev/null 2>&1
  local rc=$?
  (( rc != 126 && rc != 127 ))
}

chroot_detect_path_runs() {
  local probe_kind="$1"
  local bin="$2"
  [[ -n "$bin" && -x "$bin" ]] || return 1

  case "$probe_kind" in
    shell)
      chroot_detect_command_runs "$bin" -c ":"
      ;;
    chroot|mount|umount|busybox|toybox)
      chroot_detect_command_runs "$bin" --help
      ;;
    *)
      chroot_detect_command_runs "$bin" --help
      ;;
  esac
}

chroot_detect_pick_runnable_path() {
  local probe_kind="$1"
  local override="${2:-}"
  local lookup="$3"
  shift 3

  local found="" candidate=""
  if [[ -n "$override" ]]; then
    if [[ "$override" == */* ]]; then
      if chroot_detect_path_runs "$probe_kind" "$override"; then
        printf '%s\n' "$override"
        return 0
      fi
    else
      found="$(command -v "$override" 2>/dev/null || true)"
      if [[ -n "$found" ]] && chroot_detect_path_runs "$probe_kind" "$found"; then
        printf '%s\n' "$found"
        return 0
      fi
    fi
  fi

  for candidate in "$@"; do
    [[ -n "$candidate" ]] || continue
    if chroot_detect_path_runs "$probe_kind" "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  found="$(command -v "$lookup" 2>/dev/null || true)"
  if [[ -n "$found" ]] && chroot_detect_path_runs "$probe_kind" "$found"; then
    printf '%s\n' "$found"
    return 0
  fi

  return 1
}

chroot_detect_box_applet() {
  local box_bin="$1"
  local applet="$2"
  local listed=""
  [[ -n "$box_bin" && -x "$box_bin" ]] || {
    printf '0\n'
    return 0
  }

  listed="$("$box_bin" --list 2>/dev/null | tr -d '\r' || true)"
  if [[ -n "$listed" ]] && printf '%s\n' "$listed" | awk -v applet="$applet" '$0 == applet { found = 1 } END { exit found ? 0 : 1 }'; then
    printf '1\n'
    return 0
  fi

  if "$box_bin" "$applet" --help >/dev/null 2>&1; then
    printf '1\n'
  else
    printf '0\n'
  fi
}

chroot_detect_android_tool_candidates() {
  local tool="$1"
  local dir
  for dir in \
    "${CHROOT_SYSTEM_BIN_DEFAULT:-/system/bin}" \
    "${CHROOT_SYSTEM_XBIN_DEFAULT:-/system/xbin}" \
    "/system_ext/bin" \
    "/vendor/bin" \
    "/product/bin" \
    "/odm/bin" \
    "/apex/com.android.runtime/bin" \
    "/apex/com.android.art/bin"; do
    [[ -n "$dir" ]] || continue
    printf '%s/%s\n' "$dir" "$tool"
  done
}

chroot_detect_bins() {
  local system_bin system_xbin
  local -a chroot_candidates mount_candidates umount_candidates sh_candidates busybox_candidates toybox_candidates
  system_bin="${CHROOT_SYSTEM_BIN_DEFAULT:-/system/bin}"
  system_xbin="${CHROOT_SYSTEM_XBIN_DEFAULT:-/system/xbin}"
  mapfile -t chroot_candidates < <(chroot_detect_android_tool_candidates chroot)
  mapfile -t mount_candidates < <(chroot_detect_android_tool_candidates mount)
  mapfile -t umount_candidates < <(chroot_detect_android_tool_candidates umount)
  mapfile -t busybox_candidates < <(chroot_detect_android_tool_candidates busybox)
  mapfile -t toybox_candidates < <(chroot_detect_android_tool_candidates toybox)
  mapfile -t sh_candidates < <(chroot_detect_android_tool_candidates sh)

  CHROOT_SYSTEM_CHROOT="$(chroot_detect_pick_runnable_path chroot "${CHROOT_CHROOT_BIN:-${CHROOT_SYSTEM_CHROOT:-}}" "chroot" \
    "${chroot_candidates[@]}" "/bin/chroot" "/usr/bin/chroot" "/sbin/chroot" "/usr/sbin/chroot" || true)"
  CHROOT_SYSTEM_MOUNT="$(chroot_detect_pick_runnable_path mount "${CHROOT_MOUNT_BIN:-${CHROOT_SYSTEM_MOUNT:-}}" "mount" \
    "${mount_candidates[@]}" "/bin/mount" "/usr/bin/mount" "/sbin/mount" "/usr/sbin/mount" || true)"
  CHROOT_SYSTEM_UMOUNT="$(chroot_detect_pick_runnable_path umount "${CHROOT_UMOUNT_BIN:-${CHROOT_SYSTEM_UMOUNT:-}}" "umount" \
    "${umount_candidates[@]}" "/bin/umount" "/usr/bin/umount" "/sbin/umount" "/usr/sbin/umount" || true)"
  CHROOT_HOST_SH="$(chroot_detect_pick_runnable_path shell "${CHROOT_SH_BIN:-${CHROOT_HOST_SH:-}}" "sh" \
    "${sh_candidates[@]}" "/bin/sh" "$CHROOT_TERMUX_BIN/sh" "/usr/bin/sh" "/sbin/sh" "/usr/sbin/sh" || true)"
  CHROOT_BUSYBOX_BIN="$(chroot_detect_pick_runnable_path busybox "${CHROOT_BUSYBOX_OVERRIDE:-${CHROOT_BUSYBOX_BIN:-}}" "busybox" \
    "${busybox_candidates[@]}" "$CHROOT_TERMUX_BIN/busybox" "/bin/busybox" "/usr/bin/busybox" "/sbin/busybox" "/usr/sbin/busybox" || true)"
  CHROOT_TOYBOX_BIN="$(chroot_detect_pick_runnable_path toybox "${CHROOT_TOYBOX_OVERRIDE:-${CHROOT_TOYBOX_BIN:-}}" "toybox" \
    "${toybox_candidates[@]}" "$CHROOT_TERMUX_BIN/toybox" "/bin/toybox" "/usr/bin/toybox" "/sbin/toybox" "/usr/sbin/toybox" || true)"

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
