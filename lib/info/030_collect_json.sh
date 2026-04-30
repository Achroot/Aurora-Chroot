chroot_info_collect_env_prepare() {
  chroot_detect_bins
  chroot_detect_python
  chroot_require_python

  chroot_is_root_available >/dev/null 2>&1 || true
  if declare -F chroot_root_reporting_hydrate_original >/dev/null 2>&1; then
    chroot_root_reporting_hydrate_original
  fi
}

chroot_info_collect_json() {
  local mode="${1:-full}"
  local section="${2:-}"
  local width="${3:-96}"
  local root_available=0
  local runtime_writable=0
  local settings_json="{}"
  local tmp_py=""
  if chroot_is_root_available >/dev/null 2>&1; then
    root_available=1
  fi
  if chroot_runtime_is_user_writable >/dev/null 2>&1; then
    runtime_writable=1
  fi
  if declare -F chroot_settings_snapshot_json >/dev/null 2>&1; then
    settings_json="$(chroot_settings_snapshot_json 2>/dev/null || printf '{}\n')"
  fi
  local busybox_summary=""
  if declare -F chroot_busybox_info_summary_line >/dev/null 2>&1; then
    busybox_summary="$(chroot_busybox_info_summary_line 2>/dev/null || true)"
  fi

  local -a env_args=(
    "CHROOT_INFO_SCHEMA_VERSION=$CHROOT_INFO_SCHEMA_VERSION"
    "CHROOT_INFO_SECTION_IDS=$(chroot_info_section_ids)"
    "CHROOT_INFO_SLOW_SECTION_IDS=$(chroot_info_slow_section_ids)"
    "CHROOT_INFO_TERMUX_PREFIX=${CHROOT_TERMUX_PREFIX:-}"
    "CHROOT_INFO_SETTINGS_JSON=$settings_json"
    "CHROOT_INFO_ROOT_AVAILABLE=$root_available"
    "CHROOT_INFO_ROOT_KIND=${CHROOT_ROOT_LAUNCHER_KIND:-}"
    "CHROOT_INFO_ROOT_BIN=${CHROOT_ROOT_LAUNCHER_BIN:-}"
    "CHROOT_INFO_ROOT_SUBCMD=${CHROOT_ROOT_LAUNCHER_SUBCMD:-}"
    "CHROOT_INFO_ROOT_DIAG=${CHROOT_ROOT_DIAGNOSTICS:-}"
    "CHROOT_INFO_CHROOT_BACKEND=$(chroot_chroot_backend_label 2>/dev/null || true)"
    "CHROOT_INFO_MOUNT_BACKEND=$(chroot_mount_backend_label 2>/dev/null || true)"
    "CHROOT_INFO_UMOUNT_BACKEND=$(chroot_umount_backend_label 2>/dev/null || true)"
    "CHROOT_INFO_BUSYBOX_SUMMARY=$busybox_summary"
    "CHROOT_INFO_RUNTIME_WRITABLE=$runtime_writable"
  )

  tmp_py="$(mktemp "${TMPDIR:-${HOME:-/tmp}}/aurora-info.XXXXXX.py" 2>/dev/null || mktemp "/tmp/aurora-info.XXXXXX.py")"
  chroot_info_python_emit >"$tmp_py"

  local -a cmd=(
    env
    "${env_args[@]}"
    "$CHROOT_PYTHON_BIN"
    "$tmp_py"
    collect
    "$CHROOT_RUNTIME_ROOT" \
    "$CHROOT_ROOTFS_DIR" \
    "$CHROOT_STATE_DIR" \
    "$mode" \
    "$section" \
    "$width"
  )

  if [[ "$root_available" == "1" ]]; then
    chroot_run_root "${cmd[@]}"
    local rc=$?
    rm -f -- "$tmp_py"
    return $rc
  fi

  "${cmd[@]}"
  local rc=$?
  rm -f -- "$tmp_py"
  return $rc
}
