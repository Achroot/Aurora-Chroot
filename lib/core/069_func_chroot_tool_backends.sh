chroot_busybox_supports_applet() {
  local applet="$1"
  local cache_var=""
  case "$applet" in
    chroot) cache_var="CHROOT_BUSYBOX_HAS_CHROOT" ;;
    mount) cache_var="CHROOT_BUSYBOX_HAS_MOUNT" ;;
    umount) cache_var="CHROOT_BUSYBOX_HAS_UMOUNT" ;;
    *) cache_var="" ;;
  esac

  if [[ -n "$cache_var" ]]; then
    case "${!cache_var:-}" in
      1) return 0 ;;
      0) return 1 ;;
    esac
  fi

  if [[ -z "${CHROOT_BUSYBOX_BIN:-}" || ! -x "${CHROOT_BUSYBOX_BIN:-}" ]]; then
    [[ -n "$cache_var" ]] && printf -v "$cache_var" '%s' "0"
    return 1
  fi

  if "$CHROOT_BUSYBOX_BIN" "$applet" --help >/dev/null 2>&1; then
    [[ -n "$cache_var" ]] && printf -v "$cache_var" '%s' "1"
    return 0
  fi

  [[ -n "$cache_var" ]] && printf -v "$cache_var" '%s' "0"
  return 1
}

chroot_toybox_supports_applet() {
  local applet="$1"
  local cache_var=""
  case "$applet" in
    chroot) cache_var="CHROOT_TOYBOX_HAS_CHROOT" ;;
    mount) cache_var="CHROOT_TOYBOX_HAS_MOUNT" ;;
    umount) cache_var="CHROOT_TOYBOX_HAS_UMOUNT" ;;
    *) cache_var="" ;;
  esac

  if [[ -n "$cache_var" ]]; then
    case "${!cache_var:-}" in
      1) return 0 ;;
      0) return 1 ;;
    esac
  fi

  if [[ -z "${CHROOT_TOYBOX_BIN:-}" || ! -x "${CHROOT_TOYBOX_BIN:-}" ]]; then
    [[ -n "$cache_var" ]] && printf -v "$cache_var" '%s' "0"
    return 1
  fi

  if "$CHROOT_TOYBOX_BIN" "$applet" --help >/dev/null 2>&1; then
    [[ -n "$cache_var" ]] && printf -v "$cache_var" '%s' "1"
    return 0
  fi

  [[ -n "$cache_var" ]] && printf -v "$cache_var" '%s' "0"
  return 1
}

chroot_have_chroot_backend() {
  [[ -n "${CHROOT_SYSTEM_CHROOT:-}" ]] && return 0
  chroot_busybox_supports_applet chroot && return 0
  chroot_toybox_supports_applet chroot
}

chroot_have_mount_backend() {
  [[ -n "${CHROOT_SYSTEM_MOUNT:-}" ]] && return 0
  chroot_busybox_supports_applet mount && return 0
  chroot_toybox_supports_applet mount
}

chroot_have_umount_backend() {
  [[ -n "${CHROOT_SYSTEM_UMOUNT:-}" ]] && return 0
  chroot_busybox_supports_applet umount && return 0
  chroot_toybox_supports_applet umount
}

chroot_chroot_backend_label() {
  if [[ -n "${CHROOT_SYSTEM_CHROOT:-}" ]]; then
    printf '%s\n' "$CHROOT_SYSTEM_CHROOT"
    return 0
  fi
  if chroot_busybox_supports_applet chroot; then
    printf '%s %s\n' "$CHROOT_BUSYBOX_BIN" "chroot"
    return 0
  fi
  if chroot_toybox_supports_applet chroot; then
    printf '%s %s\n' "$CHROOT_TOYBOX_BIN" "chroot"
    return 0
  fi
  return 1
}

chroot_mount_backend_label() {
  if [[ -n "${CHROOT_SYSTEM_MOUNT:-}" ]]; then
    printf '%s\n' "$CHROOT_SYSTEM_MOUNT"
    return 0
  fi
  if chroot_busybox_supports_applet mount; then
    printf '%s %s\n' "$CHROOT_BUSYBOX_BIN" "mount"
    return 0
  fi
  if chroot_toybox_supports_applet mount; then
    printf '%s %s\n' "$CHROOT_TOYBOX_BIN" "mount"
    return 0
  fi
  return 1
}

chroot_umount_backend_label() {
  if [[ -n "${CHROOT_SYSTEM_UMOUNT:-}" ]]; then
    printf '%s\n' "$CHROOT_SYSTEM_UMOUNT"
    return 0
  fi
  if chroot_busybox_supports_applet umount; then
    printf '%s %s\n' "$CHROOT_BUSYBOX_BIN" "umount"
    return 0
  fi
  if chroot_toybox_supports_applet umount; then
    printf '%s %s\n' "$CHROOT_TOYBOX_BIN" "umount"
    return 0
  fi
  return 1
}

chroot_chroot_backend_parts_tsv() {
  if [[ -n "${CHROOT_SYSTEM_CHROOT:-}" ]]; then
    printf '%s\t%s\n' "$CHROOT_SYSTEM_CHROOT" ""
    return 0
  fi
  if chroot_busybox_supports_applet chroot; then
    printf '%s\t%s\n' "$CHROOT_BUSYBOX_BIN" "chroot"
    return 0
  fi
  if chroot_toybox_supports_applet chroot; then
    printf '%s\t%s\n' "$CHROOT_TOYBOX_BIN" "chroot"
    return 0
  fi
  return 1
}

chroot_run_chroot_cmd() {
  local rootfs="$1"
  shift

  local backend_bin="" backend_subcmd=""
  IFS=$'\t' read -r backend_bin backend_subcmd <<<"$(chroot_chroot_backend_parts_tsv || true)"
  [[ -n "$backend_bin" ]] || chroot_die "chroot backend unavailable; run doctor for diagnostics"

  if [[ -n "$backend_subcmd" ]]; then
    chroot_run_root "$backend_bin" "$backend_subcmd" "$rootfs" "$@"
  else
    chroot_run_root "$backend_bin" "$rootfs" "$@"
  fi
}

chroot_run_chroot_env() {
  local rootfs="$1"
  shift

  local -a env_pairs=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --)
        shift
        break
        ;;
      *)
        env_pairs+=("$1")
        shift
        ;;
    esac
  done
  (( $# > 0 )) || chroot_die "chroot_run_chroot_env requires command after --"

  local backend_bin="" backend_subcmd=""
  IFS=$'\t' read -r backend_bin backend_subcmd <<<"$(chroot_chroot_backend_parts_tsv || true)"
  [[ -n "$backend_bin" ]] || chroot_die "chroot backend unavailable; run doctor for diagnostics"

  if [[ -n "$backend_subcmd" ]]; then
    chroot_run_root env -i "${env_pairs[@]}" "$backend_bin" "$backend_subcmd" "$rootfs" "$@"
  else
    chroot_run_root env -i "${env_pairs[@]}" "$backend_bin" "$rootfs" "$@"
  fi
}

chroot_run_mount_cmd() {
  if [[ -n "${CHROOT_SYSTEM_MOUNT:-}" ]]; then
    chroot_run_root "$CHROOT_SYSTEM_MOUNT" "$@"
    return $?
  fi
  if chroot_busybox_supports_applet mount; then
    chroot_run_root "$CHROOT_BUSYBOX_BIN" mount "$@"
    return $?
  fi
  if chroot_toybox_supports_applet mount; then
    chroot_run_root "$CHROOT_TOYBOX_BIN" mount "$@"
    return $?
  fi
  chroot_die "mount backend unavailable; run doctor for diagnostics"
}

chroot_run_umount_cmd() {
  if [[ -n "${CHROOT_SYSTEM_UMOUNT:-}" ]]; then
    chroot_run_root "$CHROOT_SYSTEM_UMOUNT" "$@"
    return $?
  fi
  if chroot_busybox_supports_applet umount; then
    chroot_run_root "$CHROOT_BUSYBOX_BIN" umount "$@"
    return $?
  fi
  if chroot_toybox_supports_applet umount; then
    chroot_run_root "$CHROOT_TOYBOX_BIN" umount "$@"
    return $?
  fi
  chroot_die "umount backend unavailable; run doctor for diagnostics"
}
