#!/usr/bin/env bash

chroot_preflight_collect() {
  local key status detail
  local chroot_backend_label mount_backend_label umount_backend_label
  chroot_backend_label="$(chroot_chroot_backend_label || true)"
  mount_backend_label="$(chroot_mount_backend_label || true)"
  umount_backend_label="$(chroot_umount_backend_label || true)"

  key="root_access"
  if chroot_is_root_available; then
    status="pass"
    if [[ "$(id -u)" == "0" ]]; then
      CHROOT_ROOT_LAUNCHER_KIND="direct-root"
      CHROOT_ROOT_LAUNCHER_BIN=""
      if [[ -z "${CHROOT_ROOT_PROBE_TRACE:-}" ]]; then
        CHROOT_ROOT_PROBE_TRACE=$'direct-root\tuid=0\tpass\talready running as root'
      fi
      detail="root backend=direct-root launcher=none"
    else
      detail="root backend=${CHROOT_ROOT_LAUNCHER_KIND:-unknown} launcher=${CHROOT_ROOT_LAUNCHER_BIN:-unknown}"
      if [[ -n "${CHROOT_ROOT_LAUNCHER_SUBCMD:-}" ]]; then
        detail+=" subcmd=${CHROOT_ROOT_LAUNCHER_SUBCMD}"
      fi
    fi
  else
    status="fail"
    detail="root backend unavailable (${CHROOT_ROOT_DIAGNOSTICS:-no diagnostics})"
  fi
  printf '%s\t%s\t%s\n' "$key" "$status" "$detail"

  key="system_chroot"
  if chroot_have_chroot_backend; then
    status="pass"
    detail="chroot backend=${chroot_backend_label:-unknown}"
  else
    status="fail"
    detail="chroot backend missing"
  fi
  printf '%s\t%s\t%s\n' "$key" "$status" "$detail"

  key="mount_tools"
  if chroot_have_mount_backend && chroot_have_umount_backend; then
    status="pass"
    detail="mount=${mount_backend_label:-unknown} umount=${umount_backend_label:-unknown}"
  else
    status="fail"
    detail="mount/umount backends missing"
  fi
  printf '%s\t%s\t%s\n' "$key" "$status" "$detail"

  key="toolchain_backend"
  if [[ -n "$CHROOT_HOST_SH" ]] && chroot_have_chroot_backend && chroot_have_mount_backend && chroot_have_umount_backend; then
    status="pass"
  else
    status="warn"
  fi
  detail="chroot=${chroot_backend_label:-none} mount=${mount_backend_label:-none} umount=${umount_backend_label:-none} sh=${CHROOT_HOST_SH:-none} busybox=${CHROOT_BUSYBOX_BIN:-none} toybox=${CHROOT_TOYBOX_BIN:-none}"
  printf '%s\t%s\t%s\n' "$key" "$status" "$detail"

  key="required_bins"
  if [[ -n "$CHROOT_TAR_BIN" && -n "$CHROOT_CURL_BIN" && -n "$CHROOT_SHA256_BIN" && -n "$CHROOT_BASH_BIN" ]]; then
    status="pass"
    detail="tar curl sha256sum bash present"
  else
    status="fail"
    detail="missing one of tar/curl/sha256sum/bash"
  fi
  printf '%s\t%s\t%s\n' "$key" "$status" "$detail"

  key="python"
  if [[ -n "$CHROOT_PYTHON_BIN" ]]; then
    status="pass"
    detail="$CHROOT_PYTHON_BIN"
  else
    status="fail"
    detail="python missing"
  fi
  printf '%s\t%s\t%s\n' "$key" "$status" "$detail"

  key="runtime_root"
  if chroot_ensure_runtime_layout >/dev/null 2>&1; then
    if touch "$CHROOT_TMP_DIR/.write-test.$$" 2>/dev/null; then
      rm -f -- "$CHROOT_TMP_DIR/.write-test.$$"
      status="pass"
      detail="runtime root writable"
    else
      status="fail"
      detail="runtime root not writable"
    fi
  else
    status="fail"
    detail="failed creating runtime layout"
  fi
  printf '%s\t%s\t%s\n' "$key" "$status" "$detail"

  key="free_space"
  local avail min_kb avail_mb
  min_kb=$((512 * 1024))
  avail="$(df -kP "$CHROOT_RUNTIME_ROOT" 2>/dev/null | awk 'NR>1 {avail=$4} END{print avail}' || true)"
  if [[ -n "$avail" && "$avail" =~ ^[0-9]+$ ]]; then
    avail_mb=$((avail / 1024))
    if (( avail < min_kb )); then
      status="warn"
      detail="low free space (${avail}KB ~= ${avail_mb}MB available)"
    else
      status="pass"
      detail="measured free space ${avail}KB ~= ${avail_mb}MB available"
    fi
  else
    status="warn"
    detail="failed to measure free space for runtime root"
  fi
  printf '%s\t%s\t%s\n' "$key" "$status" "$detail"

  key="manifest_cache"
  if [[ -f "$CHROOT_MANIFEST_FILE" ]]; then
    status="pass"
    detail="manifest present"
  else
    status="warn"
    detail="manifest missing; run distros"
  fi
  printf '%s\t%s\t%s\n' "$key" "$status" "$detail"

  key="stale_locks"
  local stale_count=0 active_count=0 lock_path
  for lock_path in "$CHROOT_LOCK_DIR"/*.lockdir; do
    [[ -e "$lock_path" ]] || continue
    if chroot_lock_is_stale "$lock_path"; then
      stale_count=$((stale_count + 1))
    else
      active_count=$((active_count + 1))
    fi
  done
  if (( stale_count > 0 )); then
    status="warn"
    detail="$stale_count stale lockdirs (active=$active_count)"
  else
    status="pass"
    if (( active_count > 0 )); then
      detail="no stale lockdirs (active=$active_count)"
    else
      detail="no lockdirs"
    fi
  fi
  printf '%s\t%s\t%s\n' "$key" "$status" "$detail"
}

chroot_preflight_has_failures() {
  local line
  while IFS= read -r line; do
    [[ "$line" == *$'\tfail\t'* ]] && return 0
  done
  return 1
}

chroot_preflight_hard_fail() {
  local data
  data="$(chroot_preflight_collect)"
  if printf '%s\n' "$data" | chroot_preflight_has_failures; then
    printf '%s\n' "$data" | while IFS=$'\t' read -r key status detail; do
      printf '%-18s %-5s %s\n' "$key" "$status" "$detail" >&2
    done
    chroot_die "preflight checks failed"
  fi
}

chroot_cmd_doctor() {
  local json=0
  local repair_locks=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) json=1 ;;
      --repair-locks) repair_locks=1 ;;
      *) chroot_die "unknown doctor arg: $1" ;;
    esac
    shift
  done

  chroot_detect_bins
  chroot_detect_python
  chroot_ensure_runtime_layout
  chroot_is_root_available >/dev/null 2>&1 || true
  if [[ "$(id -u)" == "0" && -z "${CHROOT_ROOT_PROBE_TRACE:-}" ]]; then
    CHROOT_ROOT_PROBE_TRACE=$'direct-root\tuid=0\tpass\talready running as root'
  fi

  local report
  report="$(chroot_preflight_collect)"
  local selftest_rows=""
  if declare -F chroot_portability_selftest_rows >/dev/null 2>&1; then
    selftest_rows="$(chroot_portability_selftest_rows || true)"
  fi

  if (( repair_locks == 1 )); then
    local repaired
    repaired="$(chroot_lock_repair_stale)"
    chroot_log_info doctor "repaired stale lock count=$repaired"
  fi

  if (( json == 1 )); then
    chroot_require_python
    local chroot_backend_label mount_backend_label umount_backend_label
    chroot_backend_label="$(chroot_chroot_backend_label || true)"
    mount_backend_label="$(chroot_mount_backend_label || true)"
    umount_backend_label="$(chroot_umount_backend_label || true)"
    "$CHROOT_PYTHON_BIN" - "$report" "${CHROOT_RUNTIME_ROOT:-}" "${CHROOT_ROOT_LAUNCHER_KIND:-}" "${CHROOT_ROOT_LAUNCHER_BIN:-}" "${CHROOT_ROOT_LAUNCHER_SUBCMD:-}" "${CHROOT_ROOT_DIAGNOSTICS:-}" "${CHROOT_ROOT_PROBE_TRACE:-}" "$chroot_backend_label" "$mount_backend_label" "$umount_backend_label" "${CHROOT_HOST_SH:-}" "${CHROOT_BUSYBOX_BIN:-}" "${CHROOT_TOYBOX_BIN:-}" "$selftest_rows" <<'PY'
import json
import re
import sys

(
    report_text,
    runtime_root,
    root_kind,
    root_launcher,
    root_launcher_subcmd,
    root_diagnostics,
    root_probe_text,
    chroot_bin,
    mount_bin,
    umount_bin,
    host_sh,
    busybox_bin,
    toybox_bin,
    selftest_text,
) = sys.argv[1:15]

rows = []
for line in report_text.splitlines():
    line = line.rstrip('\n')
    if not line:
        continue
    key, status, detail = line.split('\t', 2)
    rows.append({"check": key, "status": status, "detail": detail})

if not root_kind or root_kind == "unknown":
    for row in rows:
        if row.get("check") != "root_access":
            continue
        detail = str(row.get("detail", ""))
        m = re.search(r"root backend=([^ ]+)", detail)
        if m:
            root_kind = m.group(1)
        m2 = re.search(r"launcher=([^ ]+)", detail)
        if m2:
            root_launcher = m2.group(1)
        m3 = re.search(r"subcmd=([^ ]+)", detail)
        if m3:
            root_launcher_subcmd = m3.group(1)
        break

probe_rows = []
for line in (root_probe_text or "").splitlines():
    line = line.strip()
    if not line:
        continue
    parts = line.split("\t", 3)
    while len(parts) < 4:
        parts.append("")
    phase, candidate, result, detail = parts
    probe_rows.append(
        {
            "phase": phase,
            "candidate": candidate,
            "result": result,
            "detail": detail,
        }
    )

selftest_rows = []
for line in (selftest_text or "").splitlines():
    line = line.strip()
    if not line:
        continue
    parts = line.split("\t", 4)
    while len(parts) < 5:
        parts.append("")
    suite, case_id, expected, actual, status = parts
    selftest_rows.append(
        {
            "suite": suite,
            "case": case_id,
            "expected": expected,
            "actual": actual,
            "status": status,
        }
    )

selftest_total = len(selftest_rows)
selftest_failed = sum(1 for row in selftest_rows if row.get("status") != "pass")
selftest_passed = selftest_total - selftest_failed
selftest_status = "pass" if selftest_failed == 0 else "fail"
selftest_failed_rows = [row for row in selftest_rows if row.get("status") != "pass"]

print(
    json.dumps(
        {
            "checks": rows,
            "diagnostics": {
                "runtime_root": runtime_root,
                "root_backend": {
                    "kind": root_kind or "unknown",
                    "launcher": root_launcher or "none",
                    "subcmd": root_launcher_subcmd or "",
                    "detail": root_diagnostics or "",
                    "probe_trace": probe_rows,
                },
                "tools": {
                    "chroot": chroot_bin or "",
                    "mount": mount_bin or "",
                    "umount": umount_bin or "",
                    "sh": host_sh or "",
                    "busybox": busybox_bin or "",
                    "toybox": toybox_bin or "",
                },
                "selftests": {
                    "status": selftest_status,
                    "total": selftest_total,
                    "passed": selftest_passed,
                    "failed": selftest_failed,
                    "failed_cases": selftest_failed_rows,
                },
            },
        },
        indent=2,
    )
)
PY
    return 0
  fi

  printf '%-18s %-5s %s\n' "check" "stat" "detail"
  printf '%-18s %-5s %s\n' "-----" "----" "------"
  printf '%s\n' "$report" | while IFS=$'\t' read -r key status detail; do
    printf '%-18s %-5s %s\n' "$key" "$status" "$detail"
  done
}
