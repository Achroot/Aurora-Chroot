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
  local case_id expected actual status

  if declare -F chroot_manifest_arch_selftest_rows >/dev/null 2>&1; then
    while IFS=$'\t' read -r case_id expected actual status; do
      [[ -n "$case_id" ]] || continue
      chroot_portability_selftest_emit "manifest_arch" "$case_id" "$expected" "$actual" "$status"
    done < <(chroot_manifest_arch_selftest_rows)
  else
    chroot_portability_selftest_emit "manifest_arch" "function_available" "yes" "no" "fail"
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
/data/local/chroot	true
/tmp/aurora-runtime	true
EOF_RUNTIME_SAFE

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
