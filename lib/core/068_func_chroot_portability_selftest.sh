chroot_portability_selftest_emit() {
  local suite="$1"
  local case_id="$2"
  local expected="$3"
  local actual="$4"
  local status="$5"
  expected="${expected//$'\t'/ }"
  expected="${expected//$'\n'/ }"
  actual="${actual//$'\t'/ }"
  actual="${actual//$'\n'/ }"
  printf '%s\t%s\t%s\t%s\t%s\n' "$suite" "$case_id" "$expected" "$actual" "$status"
}

chroot_portability_selftest_rows() {
  local case_id expected actual status candidate expected_candidates home_fallback

  if declare -F chroot_manifest_arch_selftest_rows >/dev/null 2>&1; then
    while IFS=$'\t' read -r case_id expected actual status; do
      [[ -n "$case_id" ]] || continue
      chroot_portability_selftest_emit "manifest_arch" "$case_id" "$expected" "$actual" "$status"
    done < <(chroot_manifest_arch_selftest_rows)
  else
    chroot_portability_selftest_emit "manifest_arch" "function_available" "yes" "no" "fail"
  fi

  if declare -F chroot_rootfs_shell_selftest_rows >/dev/null 2>&1; then
    while IFS=$'\t' read -r case_id expected actual status; do
      [[ -n "$case_id" ]] || continue
      chroot_portability_selftest_emit "rootfs_shell" "$case_id" "$expected" "$actual" "$status"
    done < <(chroot_rootfs_shell_selftest_rows)
  else
    chroot_portability_selftest_emit "rootfs_shell" "function_available" "yes" "no" "fail"
  fi

  while IFS=$'\t' read -r case_id expected; do
    [[ -n "$case_id" ]] || continue
    if chroot_runtime_root_is_safe_path "$case_id"; then
      actual="true"
    else
      actual="false"
    fi
    status="pass"
    [[ "$actual" == "$expected" ]] || status="fail"
    chroot_portability_selftest_emit "runtime_root" "safe_path:$case_id" "$expected" "$actual" "$status"
  done <<'EOF_RUNTIME_SAFE'
/	false
/data	false
/data/local	false
/data/local/aurora-chroot	true
/tmp/aurora-runtime	true
EOF_RUNTIME_SAFE

  expected_candidates="/data/local/aurora-chroot|/data/adb/aurora-chroot|/data/aurora-chroot"
  home_fallback="$(chroot_runtime_home_fallback 2>/dev/null || true)"
  if [[ -n "$home_fallback" ]]; then
    expected_candidates+="|$home_fallback"
  fi
  actual=""
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    if [[ -n "$actual" ]]; then
      actual+="|"
    fi
    actual+="$candidate"
  done < <(chroot_runtime_root_priority_candidates)
  status="pass"
  [[ "$actual" == "$expected_candidates" ]] || status="fail"
  chroot_portability_selftest_emit "runtime_root" "candidate_order" "$expected_candidates" "$actual" "$status"

  local tmp_dir="" fake_path picked
  tmp_dir="$(mktemp -d "${CHROOT_TMP_DIR:-/tmp}/portability-selftest.XXXXXX" 2>/dev/null || mktemp -d "/tmp/portability-selftest.XXXXXX")"
  fake_path="$tmp_dir/fake-tool"
  cat >"$fake_path" <<'SH'
#!/usr/bin/env sh
exit 0
SH
  chmod 755 "$fake_path"

  picked="$(chroot_detect_pick_path "" "definitely-not-a-real-command-aurora" "$fake_path" || true)"
  status="pass"
  [[ "$picked" == "$fake_path" ]] || status="fail"
  chroot_portability_selftest_emit "toolchain" "detect_pick_path:candidate" "$fake_path" "$picked" "$status"

  picked="$(chroot_detect_pick_path "$fake_path" "definitely-not-a-real-command-aurora" || true)"
  status="pass"
  [[ "$picked" == "$fake_path" ]] || status="fail"
  chroot_portability_selftest_emit "toolchain" "detect_pick_path:override" "$fake_path" "$picked" "$status"
  rm -rf -- "$tmp_dir"

  if declare -F chroot_have_chroot_backend >/dev/null 2>&1 && declare -F chroot_mount_backend_label >/dev/null 2>&1 && declare -F chroot_chroot_backend_parts_tsv >/dev/null 2>&1; then
    local tmp_backend_dir fake_busybox
    local saved_system_chroot saved_system_mount saved_system_umount saved_busybox
    local saved_bb_chroot saved_bb_mount saved_bb_umount
    local backend_bin backend_subcmd
    saved_system_chroot="${CHROOT_SYSTEM_CHROOT:-}"
    saved_system_mount="${CHROOT_SYSTEM_MOUNT:-}"
    saved_system_umount="${CHROOT_SYSTEM_UMOUNT:-}"
    saved_busybox="${CHROOT_BUSYBOX_BIN:-}"
    saved_bb_chroot="${CHROOT_BUSYBOX_HAS_CHROOT:-}"
    saved_bb_mount="${CHROOT_BUSYBOX_HAS_MOUNT:-}"
    saved_bb_umount="${CHROOT_BUSYBOX_HAS_UMOUNT:-}"

    tmp_backend_dir="$(mktemp -d "${CHROOT_TMP_DIR:-/tmp}/portability-backend-selftest.XXXXXX" 2>/dev/null || mktemp -d "/tmp/portability-backend-selftest.XXXXXX")"
    fake_busybox="$tmp_backend_dir/fake-busybox"
    cat >"$fake_busybox" <<'SH'
#!/usr/bin/env sh
applet="${1:-}"
case "$applet" in
  chroot|mount|umount)
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
SH
    chmod 755 "$fake_busybox"

    CHROOT_SYSTEM_CHROOT=""
    CHROOT_SYSTEM_MOUNT=""
    CHROOT_SYSTEM_UMOUNT=""
    CHROOT_BUSYBOX_BIN="$fake_busybox"
    CHROOT_BUSYBOX_HAS_CHROOT=""
    CHROOT_BUSYBOX_HAS_MOUNT=""
    CHROOT_BUSYBOX_HAS_UMOUNT=""

    if chroot_have_chroot_backend; then
      actual="true"
    else
      actual="false"
    fi
    status="pass"
    [[ "$actual" == "true" ]] || status="fail"
    chroot_portability_selftest_emit "toolchain" "backend:busybox_chroot_available" "true" "$actual" "$status"

    actual="$(chroot_mount_backend_label || true)"
    status="pass"
    [[ "$actual" == "$fake_busybox mount" ]] || status="fail"
    chroot_portability_selftest_emit "toolchain" "backend:mount_label_busybox" "$fake_busybox mount" "$actual" "$status"

    actual="$(chroot_umount_backend_label || true)"
    status="pass"
    [[ "$actual" == "$fake_busybox umount" ]] || status="fail"
    chroot_portability_selftest_emit "toolchain" "backend:umount_label_busybox" "$fake_busybox umount" "$actual" "$status"

    IFS=$'\t' read -r backend_bin backend_subcmd <<<"$(chroot_chroot_backend_parts_tsv || true)"
    actual="${backend_bin}|${backend_subcmd:-}"
    status="pass"
    [[ "$actual" == "$fake_busybox|chroot" ]] || status="fail"
    chroot_portability_selftest_emit "toolchain" "backend:chroot_parts_busybox" "$fake_busybox|chroot" "$actual" "$status"

    CHROOT_SYSTEM_CHROOT="$saved_system_chroot"
    CHROOT_SYSTEM_MOUNT="$saved_system_mount"
    CHROOT_SYSTEM_UMOUNT="$saved_system_umount"
    CHROOT_BUSYBOX_BIN="$saved_busybox"
    CHROOT_BUSYBOX_HAS_CHROOT="$saved_bb_chroot"
    CHROOT_BUSYBOX_HAS_MOUNT="$saved_bb_mount"
    CHROOT_BUSYBOX_HAS_UMOUNT="$saved_bb_umount"
    rm -rf -- "$tmp_backend_dir"
  else
    chroot_portability_selftest_emit "toolchain" "backend:functions_available" "yes" "no" "fail"
  fi

  if declare -F chroot_root_override_parts >/dev/null 2>&1; then
    local saved_launcher override_bin override_subcmd
    saved_launcher="${CHROOT_ROOT_LAUNCHER:-}"

    CHROOT_ROOT_LAUNCHER="busybox su"
    IFS=$'\t' read -r override_bin override_subcmd <<<"$(chroot_root_override_parts || true)"
    actual="${override_bin}|${override_subcmd}"
    status="pass"
    [[ "$actual" == "busybox|su" ]] || status="fail"
    chroot_portability_selftest_emit "root_backend" "override_parse:busybox_su" "busybox|su" "$actual" "$status"

    CHROOT_ROOT_LAUNCHER="/system/xbin/su"
    IFS=$'\t' read -r override_bin override_subcmd <<<"$(chroot_root_override_parts || true)"
    actual="${override_bin}|${override_subcmd:-}"
    status="pass"
    [[ "$actual" == "/system/xbin/su|" ]] || status="fail"
    chroot_portability_selftest_emit "root_backend" "override_parse:absolute" "/system/xbin/su|" "$actual" "$status"

    CHROOT_ROOT_LAUNCHER="$saved_launcher"
  else
    chroot_portability_selftest_emit "root_backend" "override_parse:function_available" "yes" "no" "fail"
  fi

  if declare -F chroot_root_launcher_probe >/dev/null 2>&1 && declare -F chroot_resolve_root_launcher >/dev/null 2>&1 && declare -F chroot_reexec_root_env_prefix >/dev/null 2>&1; then
    local tmp_root_dir fake_nonroot fake_noisy_root fake_su saved_id_def
    local saved_system_bin_default saved_system_xbin_default saved_root_launcher_override
    local saved_root_ready saved_root_bin saved_root_subcmd saved_root_kind
    local saved_ext_storage saved_sec_storage saved_emu_source saved_emu_target
    local saved_runtime_root saved_runtime_from_env saved_runtime_resolved

    tmp_root_dir="$(mktemp -d "${CHROOT_TMP_DIR:-/tmp}/portability-root-selftest.XXXXXX" 2>/dev/null || mktemp -d "/tmp/portability-root-selftest.XXXXXX")"
    fake_nonroot="$tmp_root_dir/fake-nonroot"
    cat >"$fake_nonroot" <<'SH'
#!/usr/bin/env sh
printf '2000\n'
exit 0
SH
    chmod 755 "$fake_nonroot"

    if chroot_root_launcher_probe "$fake_nonroot" ""; then
      actual="true"
    else
      actual="false"
    fi
    status="pass"
    [[ "$actual" == "false" ]] || status="fail"
    chroot_portability_selftest_emit "root_backend" "probe_rejects_non_root_uid" "false" "$actual" "$status"

    fake_noisy_root="$tmp_root_dir/fake-noisy-root"
    cat >"$fake_noisy_root" <<'SH'
#!/usr/bin/env sh
printf 'notice: switching context\n'
printf '0\n'
exit 0
SH
    chmod 755 "$fake_noisy_root"

    if chroot_root_launcher_probe "$fake_noisy_root" ""; then
      actual="true"
    else
      actual="false"
    fi
    status="pass"
    [[ "$actual" == "true" ]] || status="fail"
    chroot_portability_selftest_emit "root_backend" "probe_accepts_noisy_root_uid_line" "true" "$actual" "$status"

    mkdir -p "$tmp_root_dir/system-bin"
    fake_su="$tmp_root_dir/system-bin/su"
    cat >"$fake_su" <<'SH'
#!/usr/bin/env sh
case "$*" in
  *"id -u"*)
    printf '0\n'
    exit 0
    ;;
esac
exit 1
SH
    chmod 755 "$fake_su"

    saved_id_def="$(declare -f id 2>/dev/null || true)"
    id() {
      if [[ "${1:-}" == "-u" ]]; then
        printf '2000\n'
        return 0
      fi
      command id "$@"
    }

    saved_system_bin_default="${CHROOT_SYSTEM_BIN_DEFAULT:-}"
    saved_system_xbin_default="${CHROOT_SYSTEM_XBIN_DEFAULT:-}"
    saved_root_ready="${CHROOT_ROOT_BACKEND_READY:-0}"
    saved_root_bin="${CHROOT_ROOT_LAUNCHER_BIN:-}"
    saved_root_subcmd="${CHROOT_ROOT_LAUNCHER_SUBCMD:-}"
    saved_root_kind="${CHROOT_ROOT_LAUNCHER_KIND:-}"
    saved_root_launcher_override="${CHROOT_ROOT_LAUNCHER:-}"

    CHROOT_SYSTEM_BIN_DEFAULT="$tmp_root_dir/system-bin"
    CHROOT_SYSTEM_XBIN_DEFAULT="$tmp_root_dir/missing-xbin"
    CHROOT_ROOT_BACKEND_READY=0
    CHROOT_ROOT_LAUNCHER_BIN=""
    CHROOT_ROOT_LAUNCHER_SUBCMD=""
    CHROOT_ROOT_LAUNCHER_KIND=""
    CHROOT_ROOT_LAUNCHER=""
    chroot_resolve_root_launcher >/dev/null 2>&1 || true
    actual="${CHROOT_ROOT_LAUNCHER_BIN}|${CHROOT_ROOT_LAUNCHER_SUBCMD:-}"
    status="pass"
    [[ "$actual" == "$fake_su|--mount-master" ]] || status="fail"
    chroot_portability_selftest_emit "root_backend" "prefer_mount_master_for_su" "$fake_su|--mount-master" "$actual" "$status"

    unset -f id
    if [[ -n "$saved_id_def" ]]; then
      eval "$saved_id_def"
    fi
    CHROOT_SYSTEM_BIN_DEFAULT="$saved_system_bin_default"
    CHROOT_SYSTEM_XBIN_DEFAULT="$saved_system_xbin_default"
    CHROOT_ROOT_BACKEND_READY="$saved_root_ready"
    CHROOT_ROOT_LAUNCHER_BIN="$saved_root_bin"
    CHROOT_ROOT_LAUNCHER_SUBCMD="$saved_root_subcmd"
    CHROOT_ROOT_LAUNCHER_KIND="$saved_root_kind"
    CHROOT_ROOT_LAUNCHER="$saved_root_launcher_override"

    saved_runtime_root="${CHROOT_RUNTIME_ROOT:-}"
    saved_runtime_from_env="${CHROOT_RUNTIME_ROOT_FROM_ENV:-0}"
    saved_runtime_resolved="${CHROOT_RUNTIME_ROOT_RESOLVED:-0}"

    CHROOT_RUNTIME_ROOT="/data/local/aurora-chroot"
    CHROOT_RUNTIME_ROOT_FROM_ENV=0
    CHROOT_RUNTIME_ROOT_RESOLVED=0
    actual="$(chroot_reexec_root_env_prefix)"
    status="pass"
    [[ "$actual" != *" CHROOT_RUNTIME_ROOT="* ]] || status="fail"
    chroot_portability_selftest_emit "root_backend" "reexec_omits_unresolved_default_runtime_root" "no-runtime-root-env" "${actual}" "$status"

    CHROOT_RUNTIME_ROOT="/data/adb/aurora-chroot"
    CHROOT_RUNTIME_ROOT_FROM_ENV=1
    CHROOT_RUNTIME_ROOT_RESOLVED=0
    actual="$(chroot_reexec_root_env_prefix)"
    status="pass"
    [[ "$actual" == *" CHROOT_RUNTIME_ROOT="* ]] || status="fail"
    chroot_portability_selftest_emit "root_backend" "reexec_preserves_explicit_runtime_root" "runtime-root-env" "${actual}" "$status"

    CHROOT_RUNTIME_ROOT="$saved_runtime_root"
    CHROOT_RUNTIME_ROOT_FROM_ENV="$saved_runtime_from_env"
    CHROOT_RUNTIME_ROOT_RESOLVED="$saved_runtime_resolved"

    saved_ext_storage="${EXTERNAL_STORAGE:-}"
    saved_sec_storage="${SECONDARY_STORAGE:-}"
    saved_emu_source="${EMULATED_STORAGE_SOURCE:-}"
    saved_emu_target="${EMULATED_STORAGE_TARGET:-}"
    EXTERNAL_STORAGE="/sdcard"
    SECONDARY_STORAGE="/storage/1234-5678:/storage/ABCD-EF01"
    EMULATED_STORAGE_SOURCE="/mnt/shell/emulated"
    EMULATED_STORAGE_TARGET="/storage/emulated"
    actual="$(chroot_reexec_root_env_prefix)"
    status="pass"
    [[ "$actual" == *"EXTERNAL_STORAGE="* ]] || status="fail"
    [[ "$actual" == *"SECONDARY_STORAGE="* ]] || status="fail"
    [[ "$actual" == *"EMULATED_STORAGE_SOURCE="* ]] || status="fail"
    [[ "$actual" == *"EMULATED_STORAGE_TARGET="* ]] || status="fail"
    chroot_portability_selftest_emit "root_backend" "reexec_env_preserves_android_storage" "all-android-storage-vars" "${actual}" "$status"

    CHROOT_ROOT_LAUNCHER_KIND="compatibility-su"
    CHROOT_ROOT_LAUNCHER_BIN="/system/bin/su"
    CHROOT_ROOT_LAUNCHER_SUBCMD="--mount-master"
    CHROOT_ROOT_DIAGNOSTICS="using compatibility launcher: /system/bin/su --mount-master"
    CHROOT_ROOT_PROBE_TRACE=$'compatibility-su\t/system/bin/su --mount-master\tpass\tresolved=/system/bin/su uid=0 via launcher-c'
    actual="$(chroot_reexec_root_env_prefix)"
    status="pass"
    [[ "$actual" == *"CHROOT_ROOT_ORIGINAL_LAUNCHER_KIND="* ]] || status="fail"
    [[ "$actual" == *"CHROOT_ROOT_ORIGINAL_LAUNCHER_BIN="* ]] || status="fail"
    [[ "$actual" == *"CHROOT_ROOT_ORIGINAL_LAUNCHER_SUBCMD="* ]] || status="fail"
    chroot_portability_selftest_emit "root_backend" "reexec_env_preserves_original_backend_metadata" "original-root-backend-vars" "${actual}" "$status"

    if [[ -n "$saved_ext_storage" ]]; then export EXTERNAL_STORAGE="$saved_ext_storage"; else unset EXTERNAL_STORAGE; fi
    if [[ -n "$saved_sec_storage" ]]; then export SECONDARY_STORAGE="$saved_sec_storage"; else unset SECONDARY_STORAGE; fi
    if [[ -n "$saved_emu_source" ]]; then export EMULATED_STORAGE_SOURCE="$saved_emu_source"; else unset EMULATED_STORAGE_SOURCE; fi
    if [[ -n "$saved_emu_target" ]]; then export EMULATED_STORAGE_TARGET="$saved_emu_target"; else unset EMULATED_STORAGE_TARGET; fi
    rm -rf -- "$tmp_root_dir"
  else
    chroot_portability_selftest_emit "root_backend" "probe:functions_available" "yes" "no" "fail"
  fi

  if declare -F chroot_tool_backend_parts_tsv >/dev/null 2>&1; then
    local tmp_backend_dir fake_system_chroot fake_system_mount fake_system_umount fake_toybox fake_busybox fake_managed_busybox explicit_mount
    local saved_system_chroot2 saved_system_mount2 saved_system_umount2 saved_busybox2 saved_toybox2
    local saved_bb_chroot2 saved_bb_mount2 saved_bb_umount2
    local saved_toy_chroot2 saved_toy_mount2 saved_toy_umount2
    local saved_chroot_override saved_mount_override saved_umount_override
    local saved_runtime_root2 saved_runtime_resolved2

    tmp_backend_dir="$(mktemp -d "${CHROOT_TMP_DIR:-/tmp}/portability-tool-selftest.XXXXXX" 2>/dev/null || mktemp -d "/tmp/portability-tool-selftest.XXXXXX")"
    fake_system_chroot="$tmp_backend_dir/system-chroot"
    fake_system_mount="$tmp_backend_dir/system-mount"
    fake_system_umount="$tmp_backend_dir/system-umount"
    fake_toybox="$tmp_backend_dir/fake-toybox"
    fake_busybox="$tmp_backend_dir/fake-busybox"
    fake_managed_busybox="$tmp_backend_dir/fake-managed-busybox"
    explicit_mount="$tmp_backend_dir/explicit-mount"

    cat >"$fake_system_chroot" <<'SH'
#!/usr/bin/env sh
case "${1:-}" in
  --help|-h|--version)
    exit 0
    ;;
esac
exit 1
SH
    cat >"$fake_system_mount" <<'SH'
#!/usr/bin/env sh
case "${1:-}" in
  --help|-h|--version)
    exit 0
    ;;
esac
exit 1
SH
    cat >"$fake_system_umount" <<'SH'
#!/usr/bin/env sh
case "${1:-}" in
  --help|-h|--version)
    exit 0
    ;;
esac
exit 1
SH
    cat >"$fake_busybox" <<'SH'
#!/usr/bin/env sh
case "${1:-}" in
  chroot|mount|umount)
    exit 0
    ;;
esac
exit 1
SH
    cat >"$fake_toybox" <<'SH'
#!/usr/bin/env sh
case "${1:-}" in
  --list)
    printf 'chroot\nmount\numount\n'
    exit 0
    ;;
  chroot|mount|umount)
    if [ "${2:-}" = "--help" ]; then
      exit 1
    fi
    exit 0
    ;;
esac
exit 1
SH
    cat >"$fake_managed_busybox" <<'SH'
#!/usr/bin/env sh
case "${1:-}" in
  --help)
    printf 'BusyBox fake managed\n'
    exit 0
    ;;
  chroot|mount|umount)
    exit 0
    ;;
esac
exit 1
SH
    cat >"$explicit_mount" <<'SH'
#!/usr/bin/env sh
case "${1:-}" in
  --help|-h|--version)
    exit 0
    ;;
esac
printf 'explicit-override-ok\n' >&2
exit 0
SH
    chmod 755 "$fake_system_chroot" "$fake_system_mount" "$fake_system_umount" "$fake_toybox" "$fake_busybox" "$fake_managed_busybox" "$explicit_mount"

    actual="$(chroot_detect_box_applet "$fake_toybox" mount 2>/dev/null || true)"
    status="pass"
    [[ "$actual" == "1" ]] || status="fail"
    chroot_portability_selftest_emit "toolchain" "backend:toybox_list_detects_applet" "1" "$actual" "$status"

    actual="$(chroot_detect_box_applet "$fake_toybox" mountpoint 2>/dev/null || true)"
    status="pass"
    [[ "$actual" == "0" ]] || status="fail"
    chroot_portability_selftest_emit "toolchain" "backend:toybox_list_exact_match" "0" "$actual" "$status"

    saved_system_chroot2="${CHROOT_SYSTEM_CHROOT:-}"
    saved_system_mount2="${CHROOT_SYSTEM_MOUNT:-}"
    saved_system_umount2="${CHROOT_SYSTEM_UMOUNT:-}"
    saved_busybox2="${CHROOT_BUSYBOX_BIN:-}"
    saved_toybox2="${CHROOT_TOYBOX_BIN:-}"
    saved_bb_chroot2="${CHROOT_BUSYBOX_HAS_CHROOT:-}"
    saved_bb_mount2="${CHROOT_BUSYBOX_HAS_MOUNT:-}"
    saved_bb_umount2="${CHROOT_BUSYBOX_HAS_UMOUNT:-}"
    saved_toy_chroot2="${CHROOT_TOYBOX_HAS_CHROOT:-}"
    saved_toy_mount2="${CHROOT_TOYBOX_HAS_MOUNT:-}"
    saved_toy_umount2="${CHROOT_TOYBOX_HAS_UMOUNT:-}"
    saved_chroot_override="${CHROOT_CHROOT_BIN:-}"
    saved_mount_override="${CHROOT_MOUNT_BIN:-}"
    saved_umount_override="${CHROOT_UMOUNT_BIN:-}"
    saved_runtime_root2="${CHROOT_RUNTIME_ROOT:-}"
    saved_runtime_resolved2="${CHROOT_RUNTIME_ROOT_RESOLVED:-0}"

    CHROOT_SYSTEM_CHROOT="$fake_system_chroot"
    CHROOT_SYSTEM_MOUNT="$fake_system_mount"
    CHROOT_SYSTEM_UMOUNT="$fake_system_umount"
    CHROOT_BUSYBOX_BIN="$fake_busybox"
    CHROOT_TOYBOX_BIN="$fake_toybox"
    CHROOT_BUSYBOX_HAS_CHROOT="1"
    CHROOT_BUSYBOX_HAS_MOUNT="1"
    CHROOT_BUSYBOX_HAS_UMOUNT="1"
    CHROOT_TOYBOX_HAS_CHROOT="1"
    CHROOT_TOYBOX_HAS_MOUNT="1"
    CHROOT_TOYBOX_HAS_UMOUNT="1"

    actual="$(chroot_tool_backend_parts_tsv chroot 2>/dev/null | tr '\t' '|')"
    status="pass"
    [[ "$actual" == "$fake_system_chroot|" ]] || status="fail"
    chroot_portability_selftest_emit "toolchain" "backend:native_chroot_preferred" "$fake_system_chroot|" "$actual" "$status"

    actual="$(chroot_tool_backend_parts_tsv mount 2>/dev/null | tr '\t' '|')"
    status="pass"
    [[ "$actual" == "$fake_system_mount|" ]] || status="fail"
    chroot_portability_selftest_emit "toolchain" "backend:native_mount_preferred" "$fake_system_mount|" "$actual" "$status"

    CHROOT_SYSTEM_MOUNT=""
    CHROOT_TOYBOX_HAS_MOUNT=""
    actual="$(chroot_tool_backend_parts_tsv mount 2>/dev/null | tr '\t' '|')"
    status="pass"
    [[ "$actual" == "$fake_toybox|mount" ]] || status="fail"
    chroot_portability_selftest_emit "toolchain" "backend:toybox_before_builtin_busybox" "$fake_toybox|mount" "$actual" "$status"

    CHROOT_TOYBOX_HAS_MOUNT="0"
    actual="$(chroot_tool_backend_parts_tsv mount 2>/dev/null | tr '\t' '|')"
    status="pass"
    [[ "$actual" == "$fake_busybox|mount" ]] || status="fail"
    chroot_portability_selftest_emit "toolchain" "backend:built_in_busybox_before_managed" "$fake_busybox|mount" "$actual" "$status"

    if declare -F chroot_busybox_write_metadata >/dev/null 2>&1; then
      chroot_set_runtime_root "$tmp_backend_dir/runtime"
      CHROOT_RUNTIME_ROOT_RESOLVED=1
      mkdir -p "$(chroot_busybox_dir)"
      cp -- "$fake_managed_busybox" "$(chroot_busybox_active_binary_path)"
      chmod 755 "$(chroot_busybox_active_binary_path)"
      chroot_busybox_validate_binary_tsv "$(chroot_busybox_active_binary_path)" >"$tmp_backend_dir/managed-validation.tsv"
      : >"$tmp_backend_dir/managed-tools.tsv"
      chroot_busybox_write_metadata "path_file" "$fake_managed_busybox" "$(chroot_busybox_active_binary_path)" "" "" "" "selftest" "BusyBox fake managed" "$(chroot_file_size_bytes "$(chroot_busybox_active_binary_path)")" "$(chroot_busybox_sha256_file "$(chroot_busybox_active_binary_path)")" "valid" "$tmp_backend_dir/managed-validation.tsv" "$tmp_backend_dir/managed-tools.tsv"
      CHROOT_BUSYBOX_HAS_MOUNT="0"
      actual="$(chroot_tool_backend_parts_tsv mount 2>/dev/null | tr '\t' '|')"
      status="pass"
      [[ "$actual" == "$(chroot_busybox_active_binary_path)|mount" ]] || status="fail"
      chroot_portability_selftest_emit "toolchain" "backend:managed_busybox_last" "$(chroot_busybox_active_binary_path)|mount" "$actual" "$status"
    else
      chroot_portability_selftest_emit "toolchain" "backend:managed_busybox_last" "function_available" "missing" "fail"
    fi

    CHROOT_MOUNT_BIN="$explicit_mount"
    CHROOT_SYSTEM_MOUNT="$explicit_mount"
    CHROOT_TOYBOX_HAS_MOUNT="1"
    CHROOT_BUSYBOX_HAS_MOUNT="1"
    actual="$(chroot_tool_backend_parts_tsv mount 2>/dev/null | tr '\t' '|')"
    status="pass"
    [[ "$actual" == "$explicit_mount|" ]] || status="fail"
    chroot_portability_selftest_emit "toolchain" "backend:explicit_mount_override_preferred" "$explicit_mount|" "$actual" "$status"

    CHROOT_SYSTEM_CHROOT="$saved_system_chroot2"
    CHROOT_SYSTEM_MOUNT="$saved_system_mount2"
    CHROOT_SYSTEM_UMOUNT="$saved_system_umount2"
    CHROOT_BUSYBOX_BIN="$saved_busybox2"
    CHROOT_TOYBOX_BIN="$saved_toybox2"
    CHROOT_BUSYBOX_HAS_CHROOT="$saved_bb_chroot2"
    CHROOT_BUSYBOX_HAS_MOUNT="$saved_bb_mount2"
    CHROOT_BUSYBOX_HAS_UMOUNT="$saved_bb_umount2"
    CHROOT_TOYBOX_HAS_CHROOT="$saved_toy_chroot2"
    CHROOT_TOYBOX_HAS_MOUNT="$saved_toy_mount2"
    CHROOT_TOYBOX_HAS_UMOUNT="$saved_toy_umount2"
    CHROOT_CHROOT_BIN="$saved_chroot_override"
    CHROOT_MOUNT_BIN="$saved_mount_override"
    CHROOT_UMOUNT_BIN="$saved_umount_override"
    chroot_set_runtime_root "$saved_runtime_root2"
    CHROOT_RUNTIME_ROOT_RESOLVED="$saved_runtime_resolved2"
    rm -rf -- "$tmp_backend_dir"
  else
    chroot_portability_selftest_emit "toolchain" "backend:resolver_available" "yes" "no" "fail"
  fi

  if declare -F chroot_busybox_arch_repo_binary >/dev/null 2>&1; then
    actual="$(chroot_busybox_arch_repo_binary "arm64-v8a" "aarch64" "26" 2>/dev/null || true)"
    status="pass"
    [[ "$actual" == "busybox-arm64-selinux" ]] || status="fail"
    chroot_portability_selftest_emit "busybox" "arch:arm64_api26_prefers_selinux" "busybox-arm64-selinux" "$actual" "$status"

    actual="$(chroot_busybox_arch_repo_binary "arm64-v8a" "aarch64" "25" 2>/dev/null || true)"
    status="pass"
    [[ "$actual" == "busybox-arm64" ]] || status="fail"
    chroot_portability_selftest_emit "busybox" "arch:arm64_api25_prefers_plain" "busybox-arm64" "$actual" "$status"

    actual="$(chroot_busybox_arch_repo_binary "" "x86_64" "" 2>/dev/null || true)"
    status="pass"
    [[ "$actual" == "busybox-x86_64" ]] || status="fail"
    chroot_portability_selftest_emit "busybox" "arch:x86_64_unknown_api_prefers_plain" "busybox-x86_64" "$actual" "$status"
  else
    chroot_portability_selftest_emit "busybox" "arch:function_available" "yes" "no" "fail"
  fi

  if declare -F chroot_busybox_validate_applet_dir_tsv >/dev/null 2>&1; then
    local tmp_bad_applet_dir bad_applet_tool
    tmp_bad_applet_dir="$(mktemp -d "${CHROOT_TMP_DIR:-/tmp}/portability-busybox-applets.XXXXXX" 2>/dev/null || mktemp -d "/tmp/portability-busybox-applets.XXXXXX")"
    for bad_applet_tool in chroot mount umount; do
      cat >"$tmp_bad_applet_dir/$bad_applet_tool" <<'SH'
#!/usr/bin/env sh
printf 'not a usable backend\n' >&2
exit 1
SH
      chmod 755 "$tmp_bad_applet_dir/$bad_applet_tool"
    done
    if chroot_busybox_validate_applet_dir_tsv "$tmp_bad_applet_dir" >/dev/null 2>&1; then
      actual="accepted"
    else
      actual="rejected"
    fi
    status="pass"
    [[ "$actual" == "rejected" ]] || status="fail"
    chroot_portability_selftest_emit "busybox" "validation:applet_help_nonzero_rejected" "rejected" "$actual" "$status"
    rm -rf -- "$tmp_bad_applet_dir"
  else
    chroot_portability_selftest_emit "busybox" "validation:applet_dir_validator_available" "yes" "no" "fail"
  fi

  if declare -F chroot_android_full_bind_sources_from_file >/dev/null 2>&1 && declare -F chroot_mountinfo_record_from_file >/dev/null 2>&1 && declare -F chroot_mount_bind_record_matches_source >/dev/null 2>&1 && declare -F chroot_mount_target_matches_fstype_from_file >/dev/null 2>&1; then
    local tmp_mount_dir bind_fixture ambiguous_fixture android_fixture rows

    tmp_mount_dir="$(mktemp -d "${CHROOT_TMP_DIR:-/tmp}/portability-mount-selftest.XXXXXX" 2>/dev/null || mktemp -d "/tmp/portability-mount-selftest.XXXXXX")"
    bind_fixture="$tmp_mount_dir/bind.mountinfo"
    ambiguous_fixture="$tmp_mount_dir/ambiguous.mountinfo"
    android_fixture="$tmp_mount_dir/android.mountinfo"

    cat >"$bind_fixture" <<'EOF_BIND_MOUNTINFO'
10 1 0:30 / /system rw,relatime - ext4 /dev/block/dm-0 rw
11 1 0:31 / /vendor rw,relatime - ext4 /dev/block/dm-2 rw
36 25 0:32 / /tmp/rootfs/system rw,relatime - ext4 /dev/block/dm-0 rw
37 25 0:33 / /tmp/rootfs/system rw,relatime - ext4 /dev/block/dm-1 rw
38 25 0:34 / /tmp/rootfs/vendor rw,relatime - ext4 /dev/block/dm-2 rw
39 25 0:35 /proc /tmp/rootfs/proc rw,relatime - proc proc rw
40 25 0:36 / /tmp/rootfs/dev/shm rw,relatime - tmpfs tmpfs rw
EOF_BIND_MOUNTINFO

    actual="$(chroot_mountinfo_record_from_file "/tmp/rootfs/system" "$bind_fixture" 2>/dev/null | tr '\t' '|')"
    status="pass"
    [[ "$actual" == "/|ext4|/dev/block/dm-1" ]] || status="fail"
    chroot_portability_selftest_emit "mount_parser" "record_uses_topmost_visible_mount" "/|ext4|/dev/block/dm-1" "$actual" "$status"

    if chroot_mount_bind_record_matches_source "/vendor" "/tmp/rootfs/vendor" "$bind_fixture"; then
      actual="true"
    else
      actual="false"
    fi
    status="pass"
    [[ "$actual" == "true" ]] || status="fail"
    chroot_portability_selftest_emit "mount_parser" "bind_record_matches_source" "true" "$actual" "$status"

    if chroot_mount_bind_record_matches_source "/system" "/tmp/rootfs/system" "$bind_fixture"; then
      actual="true"
    else
      actual="false"
    fi
    status="pass"
    [[ "$actual" == "false" ]] || status="fail"
    chroot_portability_selftest_emit "mount_parser" "bind_record_rejects_conflict" "false" "$actual" "$status"

    cat >"$ambiguous_fixture" <<'EOF_BIND_AMBIG_MOUNTINFO'
10 1 0:30 / /A rw,relatime - ext4 /dev/block/dm-0 rw
11 1 0:31 / /B rw,relatime - ext4 /dev/block/dm-0 rw
12 1 0:32 / /tmp/rootfs/A rw,relatime - ext4 /dev/block/dm-0 rw
EOF_BIND_AMBIG_MOUNTINFO

    if chroot_mount_bind_record_matches_source "/A" "/tmp/rootfs/A" "$ambiguous_fixture"; then
      actual="true"
    else
      actual="false"
    fi
    status="pass"
    [[ "$actual" == "false" ]] || status="fail"
    chroot_portability_selftest_emit "mount_parser" "bind_record_rejects_ambiguous_exact_mount_aliases" "false" "$actual" "$status"

    if chroot_mount_target_matches_fstype_from_file "/tmp/rootfs/proc" "proc" "proc" "$bind_fixture"; then
      actual="true"
    else
      actual="false"
    fi
    status="pass"
    [[ "$actual" == "true" ]] || status="fail"
    chroot_portability_selftest_emit "mount_parser" "proc_record_matches_fstype" "true" "$actual" "$status"

    if chroot_mount_bind_record_matches_source "/system" "/tmp/rootfs/proc" "$bind_fixture"; then
      actual="true"
    else
      actual="false"
    fi
    status="pass"
    [[ "$actual" == "false" ]] || status="fail"
    chroot_portability_selftest_emit "mount_parser" "bind_record_rejects_proc_conflict" "false" "$actual" "$status"

    if chroot_mount_target_matches_fstype_from_file "/tmp/rootfs/dev/shm" "tmpfs" "tmpfs" "$bind_fixture"; then
      actual="true"
    else
      actual="false"
    fi
    status="pass"
    [[ "$actual" == "true" ]] || status="fail"
    chroot_portability_selftest_emit "mount_parser" "tmpfs_record_matches_fstype" "true" "$actual" "$status"

    cat >"$android_fixture" <<'EOF_ANDROID_MOUNTINFO'
41 25 0:40 / /system_ext rw,relatime - ext4 /dev/block/system rw
42 25 0:41 / /vendor_boot rw,relatime - ext4 /dev/block/vendor_boot rw
43 25 0:42 / /product_services rw,relatime - ext4 /dev/block/product rw
44 25 0:43 / /my_company rw,relatime - ext4 /dev/block/my_company rw
45 25 0:44 / /data rw,relatime - f2fs /dev/block/userdata rw
46 25 0:45 /bin /system/bin rw,relatime - ext4 /dev/block/system rw
EOF_ANDROID_MOUNTINFO

    rows="$(chroot_android_full_bind_sources_from_file "$android_fixture" 2>/dev/null | sort -u | paste -sd ',' -)"
    status="pass"
    [[ "$rows" == *"/system_ext"* ]] || status="fail"
    [[ "$rows" == *"/vendor_boot"* ]] || status="fail"
    [[ "$rows" == *"/product_services"* ]] || status="fail"
    [[ "$rows" == *"/my_company"* ]] || status="fail"
    [[ "$rows" != *"/data"* ]] || status="fail"
    [[ "$rows" != *"/system/bin"* ]] || status="fail"
    chroot_portability_selftest_emit "mount_parser" "android_full_bind_detects_top_level_partitions" "system_ext,vendor_boot,product_services,my_company and no data/system/bin" "$rows" "$status"

    rm -rf -- "$tmp_mount_dir"
  else
    chroot_portability_selftest_emit "mount_parser" "functions_available" "yes" "no" "fail"
  fi

  if declare -F chroot_mount_rollback_target >/dev/null 2>&1; then
    local saved_is_mounted_def saved_umount_def saved_warn_def saved_error_def
    local tmp_rollback_dir rollback_log actual

    tmp_rollback_dir="$(mktemp -d "${CHROOT_TMP_DIR:-/tmp}/portability-rollback-selftest.XXXXXX" 2>/dev/null || mktemp -d "/tmp/portability-rollback-selftest.XXXXXX")"
    rollback_log="$tmp_rollback_dir/rollback.log"
    saved_is_mounted_def="$(declare -f chroot_is_mounted 2>/dev/null || true)"
    saved_umount_def="$(declare -f chroot_run_umount_cmd 2>/dev/null || true)"
    saved_warn_def="$(declare -f chroot_log_warn 2>/dev/null || true)"
    saved_error_def="$(declare -f chroot_log_error 2>/dev/null || true)"

    chroot_is_mounted() {
      [[ "${1:-}" == "/tmp/test-rollback-target" ]]
    }
    chroot_run_umount_cmd() {
      printf '%s\n' "$*" >>"$rollback_log"
      return 0
    }
    chroot_log_warn() { :; }
    chroot_log_error() { :; }

    if chroot_mount_rollback_target "/tmp/test-rollback-target" "demo" "bind"; then
      actual="true"
    else
      actual="false"
    fi
    status="pass"
    [[ "$actual" == "true" ]] || status="fail"
    if ! grep -q "/tmp/test-rollback-target" "$rollback_log" 2>/dev/null; then
      status="fail"
    fi
    chroot_portability_selftest_emit "mount_parser" "rollback_unmounts_failed_mount" "true + target logged" "$actual" "$status"

    unset -f chroot_is_mounted chroot_run_umount_cmd chroot_log_warn chroot_log_error
    if [[ -n "$saved_is_mounted_def" ]]; then eval "$saved_is_mounted_def"; fi
    if [[ -n "$saved_umount_def" ]]; then eval "$saved_umount_def"; fi
    if [[ -n "$saved_warn_def" ]]; then eval "$saved_warn_def"; fi
    if [[ -n "$saved_error_def" ]]; then eval "$saved_error_def"; fi
    rm -rf -- "$tmp_rollback_dir"
  else
    chroot_portability_selftest_emit "mount_parser" "rollback:function_available" "yes" "no" "fail"
  fi

  if declare -F chroot_preflight_collect >/dev/null 2>&1; then
    local saved_reexec_ctx saved_orig_kind saved_orig_bin saved_orig_subcmd saved_orig_diag saved_orig_trace
    local saved_root_kind2 saved_root_bin2 saved_root_subcmd2 saved_root_diag2 saved_root_trace2
    local saved_id_def2 root_detail

    saved_reexec_ctx="${CHROOT_REEXEC_ROOT_CONTEXT:-0}"
    saved_orig_kind="${CHROOT_ROOT_ORIGINAL_LAUNCHER_KIND:-}"
    saved_orig_bin="${CHROOT_ROOT_ORIGINAL_LAUNCHER_BIN:-}"
    saved_orig_subcmd="${CHROOT_ROOT_ORIGINAL_LAUNCHER_SUBCMD:-}"
    saved_orig_diag="${CHROOT_ROOT_ORIGINAL_DIAGNOSTICS:-}"
    saved_orig_trace="${CHROOT_ROOT_ORIGINAL_PROBE_TRACE:-}"
    saved_root_kind2="${CHROOT_ROOT_LAUNCHER_KIND:-}"
    saved_root_bin2="${CHROOT_ROOT_LAUNCHER_BIN:-}"
    saved_root_subcmd2="${CHROOT_ROOT_LAUNCHER_SUBCMD:-}"
    saved_root_diag2="${CHROOT_ROOT_DIAGNOSTICS:-}"
    saved_root_trace2="${CHROOT_ROOT_PROBE_TRACE:-}"
    saved_id_def2="$(declare -f id 2>/dev/null || true)"

    id() {
      if [[ "${1:-}" == "-u" ]]; then
        printf '0\n'
        return 0
      fi
      command id "$@"
    }

    CHROOT_REEXEC_ROOT_CONTEXT=1
    CHROOT_ROOT_ORIGINAL_LAUNCHER_KIND="compatibility-su"
    CHROOT_ROOT_ORIGINAL_LAUNCHER_BIN="/system/bin/su"
    CHROOT_ROOT_ORIGINAL_LAUNCHER_SUBCMD="--mount-master"
    CHROOT_ROOT_ORIGINAL_DIAGNOSTICS="using compatibility launcher: /system/bin/su --mount-master"
    CHROOT_ROOT_ORIGINAL_PROBE_TRACE=$'compatibility-su\t/system/bin/su --mount-master\tpass\tresolved=/system/bin/su uid=0 via launcher-c'
    root_detail="$(printf '%s\n' "$(chroot_preflight_collect)" | awk -F'\t' '$1=="root_access" {print $3; exit}')"
    status="pass"
    [[ "$root_detail" == *"root backend=compatibility-su"* ]] || status="fail"
    [[ "$root_detail" == *"launcher=/system/bin/su"* ]] || status="fail"
    [[ "$root_detail" == *"subcmd=--mount-master"* ]] || status="fail"
    [[ "$root_detail" == *"current=direct-root"* ]] || status="fail"
    chroot_portability_selftest_emit "root_backend" "preflight_reports_original_backend_after_reexec" "compatibility-su with original launcher metadata" "$root_detail" "$status"

    unset -f id
    if [[ -n "$saved_id_def2" ]]; then
      eval "$saved_id_def2"
    fi
    CHROOT_REEXEC_ROOT_CONTEXT="$saved_reexec_ctx"
    CHROOT_ROOT_ORIGINAL_LAUNCHER_KIND="$saved_orig_kind"
    CHROOT_ROOT_ORIGINAL_LAUNCHER_BIN="$saved_orig_bin"
    CHROOT_ROOT_ORIGINAL_LAUNCHER_SUBCMD="$saved_orig_subcmd"
    CHROOT_ROOT_ORIGINAL_DIAGNOSTICS="$saved_orig_diag"
    CHROOT_ROOT_ORIGINAL_PROBE_TRACE="$saved_orig_trace"
    CHROOT_ROOT_LAUNCHER_KIND="$saved_root_kind2"
    CHROOT_ROOT_LAUNCHER_BIN="$saved_root_bin2"
    CHROOT_ROOT_LAUNCHER_SUBCMD="$saved_root_subcmd2"
    CHROOT_ROOT_DIAGNOSTICS="$saved_root_diag2"
    CHROOT_ROOT_PROBE_TRACE="$saved_root_trace2"
  else
    chroot_portability_selftest_emit "root_backend" "preflight:function_available" "yes" "no" "fail"
  fi
}

chroot_portability_selftest_summary_tsv() {
  local rows="${1:-}"
  local total=0 passed=0 failed=0
  local _suite _case _expected _actual status

  if [[ -z "$rows" ]]; then
    rows="$(chroot_portability_selftest_rows || true)"
  fi

  while IFS=$'\t' read -r _suite _case _expected _actual status; do
    [[ -n "$status" ]] || continue
    total=$((total + 1))
    if [[ "$status" == "pass" ]]; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi
  done <<<"$rows"

  printf '%s\t%s\t%s\n' "$total" "$passed" "$failed"
}
