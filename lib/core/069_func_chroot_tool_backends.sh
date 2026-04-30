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

  if [[ "$(chroot_detect_box_applet "$CHROOT_BUSYBOX_BIN" "$applet")" == "1" ]]; then
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

  if [[ "$(chroot_detect_box_applet "$CHROOT_TOYBOX_BIN" "$applet")" == "1" ]]; then
    [[ -n "$cache_var" ]] && printf -v "$cache_var" '%s' "1"
    return 0
  fi

  [[ -n "$cache_var" ]] && printf -v "$cache_var" '%s' "0"
  return 1
}

chroot_system_tool_backend_bin() {
  case "$1" in
    chroot) printf '%s\n' "${CHROOT_SYSTEM_CHROOT:-}" ;;
    mount) printf '%s\n' "${CHROOT_SYSTEM_MOUNT:-}" ;;
    umount) printf '%s\n' "${CHROOT_SYSTEM_UMOUNT:-}" ;;
    *) return 1 ;;
  esac
}

chroot_system_tool_backend_override_requested() {
  case "$1" in
    chroot) [[ -n "${CHROOT_CHROOT_BIN:-}" ]] ;;
    mount) [[ -n "${CHROOT_MOUNT_BIN:-}" ]] ;;
    umount) [[ -n "${CHROOT_UMOUNT_BIN:-}" ]] ;;
    *) return 1 ;;
  esac
}

chroot_system_tool_backend_override_value() {
  case "$1" in
    chroot) printf '%s\n' "${CHROOT_CHROOT_BIN:-}" ;;
    mount) printf '%s\n' "${CHROOT_MOUNT_BIN:-}" ;;
    umount) printf '%s\n' "${CHROOT_UMOUNT_BIN:-}" ;;
    *) return 1 ;;
  esac
}

chroot_system_tool_backend_override_selected() {
  local tool="$1"
  local override_value system_bin resolved=""
  override_value="$(chroot_system_tool_backend_override_value "$tool" 2>/dev/null || true)"
  [[ -n "$override_value" ]] || return 1
  system_bin="$(chroot_system_tool_backend_bin "$tool" 2>/dev/null || true)"
  [[ -n "$system_bin" ]] || return 1
  if [[ "$override_value" == */* ]]; then
    [[ "$override_value" == "$system_bin" ]]
    return $?
  fi
  resolved="$(command -v "$override_value" 2>/dev/null || true)"
  [[ -n "$resolved" && "$resolved" == "$system_bin" ]]
}

chroot_system_tool_backend_supports() {
  local tool="$1"
  local bin=""

  bin="$(chroot_system_tool_backend_bin "$tool" 2>/dev/null || true)"
  [[ -n "$bin" && -x "$bin" ]] || return 1

  case "$tool" in
    mount|umount|chroot)
      chroot_detect_path_runs "$tool" "$bin" && return 0
      ;;
  esac

  return 1
}

chroot_tool_backend_parts_tsv() {
  local tool="$1"
  local system_bin=""

  system_bin="$(chroot_system_tool_backend_bin "$tool" 2>/dev/null || true)"
  if chroot_system_tool_backend_override_selected "$tool" && chroot_system_tool_backend_supports "$tool"; then
    printf '%s\t%s\n' "$system_bin" ""
    return 0
  fi

  if chroot_system_tool_backend_supports "$tool"; then
    printf '%s\t%s\n' "$system_bin" ""
    return 0
  fi

  if chroot_toybox_supports_applet "$tool"; then
    printf '%s\t%s\n' "$CHROOT_TOYBOX_BIN" "$tool"
    return 0
  fi

  if chroot_busybox_supports_applet "$tool"; then
    printf '%s\t%s\n' "$CHROOT_BUSYBOX_BIN" "$tool"
    return 0
  fi

  if declare -F chroot_managed_busybox_tool_backend_parts_tsv >/dev/null 2>&1 && chroot_managed_busybox_tool_backend_parts_tsv "$tool"; then
    return 0
  fi

  return 1
}

chroot_tool_backend_label() {
  local tool="$1"
  local backend_bin="" backend_subcmd=""

  IFS=$'\t' read -r backend_bin backend_subcmd <<<"$(chroot_tool_backend_parts_tsv "$tool" || true)"
  [[ -n "$backend_bin" ]] || return 1
  if [[ -n "$backend_subcmd" ]]; then
    printf '%s %s\n' "$backend_bin" "$backend_subcmd"
  else
    printf '%s\n' "$backend_bin"
  fi
}

chroot_have_chroot_backend() {
  chroot_tool_backend_parts_tsv chroot >/dev/null 2>&1
}

chroot_have_mount_backend() {
  chroot_tool_backend_parts_tsv mount >/dev/null 2>&1
}

chroot_have_umount_backend() {
  chroot_tool_backend_parts_tsv umount >/dev/null 2>&1
}

chroot_chroot_backend_label() {
  chroot_tool_backend_label chroot
}

chroot_mount_backend_label() {
  chroot_tool_backend_label mount
}

chroot_umount_backend_label() {
  chroot_tool_backend_label umount
}

chroot_chroot_backend_parts_tsv() {
  chroot_tool_backend_parts_tsv chroot
}

chroot_missing_tool_backend_die() {
  local tool="$1"
  if declare -F chroot_busybox_missing_tool_message >/dev/null 2>&1; then
    chroot_die "$(chroot_busybox_missing_tool_message "$tool")"
  fi
  chroot_die "$tool backend unavailable; run doctor for diagnostics"
}

chroot_run_chroot_cmd() {
  local rootfs="$1"
  shift

  local backend_bin="" backend_subcmd=""
  IFS=$'\t' read -r backend_bin backend_subcmd <<<"$(chroot_chroot_backend_parts_tsv || true)"
  [[ -n "$backend_bin" ]] || chroot_missing_tool_backend_die chroot

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
  [[ -n "$backend_bin" ]] || chroot_missing_tool_backend_die chroot

  if [[ -n "$backend_subcmd" ]]; then
    chroot_run_root env -i "${env_pairs[@]}" "$backend_bin" "$backend_subcmd" "$rootfs" "$@"
  else
    chroot_run_root env -i "${env_pairs[@]}" "$backend_bin" "$rootfs" "$@"
  fi
}

chroot_run_mount_cmd() {
  local backend_bin="" backend_subcmd=""

  IFS=$'\t' read -r backend_bin backend_subcmd <<<"$(chroot_tool_backend_parts_tsv mount || true)"
  if [[ -n "$backend_bin" ]]; then
    if [[ -n "$backend_subcmd" ]]; then
      chroot_run_root "$backend_bin" "$backend_subcmd" "$@"
    else
      chroot_run_root "$backend_bin" "$@"
    fi
    return $?
  fi
  chroot_missing_tool_backend_die mount
}

chroot_run_umount_cmd() {
  local backend_bin="" backend_subcmd=""

  IFS=$'\t' read -r backend_bin backend_subcmd <<<"$(chroot_tool_backend_parts_tsv umount || true)"
  if [[ -n "$backend_bin" ]]; then
    if [[ -n "$backend_subcmd" ]]; then
      chroot_run_root "$backend_bin" "$backend_subcmd" "$@"
    else
      chroot_run_root "$backend_bin" "$@"
    fi
    return $?
  fi
  chroot_missing_tool_backend_die umount
}
