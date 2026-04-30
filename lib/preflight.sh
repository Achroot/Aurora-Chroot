#!/usr/bin/env bash

chroot_root_reporting_hydrate_original() {
  if [[ "$(id -u)" == "0" && "${CHROOT_REEXEC_ROOT_CONTEXT:-0}" == "1" && -n "${CHROOT_ROOT_ORIGINAL_LAUNCHER_KIND:-}" && -n "${CHROOT_ROOT_ORIGINAL_LAUNCHER_BIN:-}" ]]; then
    CHROOT_ROOT_LAUNCHER_KIND="$CHROOT_ROOT_ORIGINAL_LAUNCHER_KIND"
    CHROOT_ROOT_LAUNCHER_BIN="$CHROOT_ROOT_ORIGINAL_LAUNCHER_BIN"
    CHROOT_ROOT_LAUNCHER_SUBCMD="${CHROOT_ROOT_ORIGINAL_LAUNCHER_SUBCMD:-}"
    if [[ -n "${CHROOT_ROOT_ORIGINAL_DIAGNOSTICS:-}" ]]; then
      CHROOT_ROOT_DIAGNOSTICS="$CHROOT_ROOT_ORIGINAL_DIAGNOSTICS"
    fi
    if [[ -n "${CHROOT_ROOT_ORIGINAL_PROBE_TRACE:-}" ]]; then
      CHROOT_ROOT_PROBE_TRACE="$CHROOT_ROOT_ORIGINAL_PROBE_TRACE"
    elif [[ -z "${CHROOT_ROOT_PROBE_TRACE:-}" ]]; then
      CHROOT_ROOT_PROBE_TRACE=$'reexec-root\tuid=0\tpass\tpreserved original root backend metadata after reexec'
    fi
  fi
}

chroot_preflight_collect() {
  local key status detail
  local chroot_backend_label mount_backend_label umount_backend_label
  local original_root_kind original_root_launcher original_root_subcmd
  local busybox_missing busybox_active busybox_active_csv busybox_missing_csv
  chroot_backend_label="$(chroot_chroot_backend_label || true)"
  mount_backend_label="$(chroot_mount_backend_label || true)"
  umount_backend_label="$(chroot_umount_backend_label || true)"
  original_root_kind="${CHROOT_ROOT_ORIGINAL_LAUNCHER_KIND:-}"
  original_root_launcher="${CHROOT_ROOT_ORIGINAL_LAUNCHER_BIN:-}"
  original_root_subcmd="${CHROOT_ROOT_ORIGINAL_LAUNCHER_SUBCMD:-}"
  chroot_root_reporting_hydrate_original

  key="root_access"
  if chroot_is_root_available; then
    status="pass"
    if [[ "$(id -u)" == "0" ]]; then
      if [[ "${CHROOT_REEXEC_ROOT_CONTEXT:-0}" == "1" && -n "$original_root_kind" && -n "$original_root_launcher" ]]; then
        CHROOT_ROOT_LAUNCHER_KIND="$original_root_kind"
        CHROOT_ROOT_LAUNCHER_BIN="$original_root_launcher"
        CHROOT_ROOT_LAUNCHER_SUBCMD="$original_root_subcmd"
        if [[ -n "${CHROOT_ROOT_ORIGINAL_DIAGNOSTICS:-}" ]]; then
          CHROOT_ROOT_DIAGNOSTICS="$CHROOT_ROOT_ORIGINAL_DIAGNOSTICS"
        fi
        if [[ -n "${CHROOT_ROOT_ORIGINAL_PROBE_TRACE:-}" ]]; then
          CHROOT_ROOT_PROBE_TRACE="$CHROOT_ROOT_ORIGINAL_PROBE_TRACE"
        elif [[ -z "${CHROOT_ROOT_PROBE_TRACE:-}" ]]; then
          CHROOT_ROOT_PROBE_TRACE=$'reexec-root\tuid=0\tpass\tpreserved original root backend metadata after reexec'
        fi
        detail="root backend=${original_root_kind} launcher=${original_root_launcher}"
        if [[ -n "$original_root_subcmd" ]]; then
          detail+=" subcmd=${original_root_subcmd}"
        fi
        detail+=" current=direct-root"
      else
        CHROOT_ROOT_LAUNCHER_KIND="direct-root"
        CHROOT_ROOT_LAUNCHER_BIN=""
        CHROOT_ROOT_LAUNCHER_SUBCMD=""
        if [[ -z "${CHROOT_ROOT_PROBE_TRACE:-}" ]]; then
          CHROOT_ROOT_PROBE_TRACE=$'direct-root\tuid=0\tpass\talready running as root'
        fi
        detail="root backend=direct-root launcher=none"
      fi
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

  key="busybox_fallback"
  if declare -F chroot_busybox_native_missing_tools >/dev/null 2>&1; then
    busybox_missing="$(chroot_busybox_native_missing_tools)"
    busybox_active="$(chroot_busybox_active_fallback_tools)"
    if [[ -z "$busybox_missing" ]]; then
      status="pass"
      detail="BusyBox fetch/path is not required; native/built-in providers cover required backend tools"
    elif [[ -n "$busybox_active" ]]; then
      status="warn"
      busybox_active_csv="$(printf '%s\n' "$busybox_active" | chroot_busybox_join_lines_comma)"
      detail="managed BusyBox fallback active for ${busybox_active_csv}"
    else
      status="fail"
      busybox_missing_csv="$(printf '%s\n' "$busybox_missing" | chroot_busybox_join_lines_comma)"
      detail="managed BusyBox fallback required for ${busybox_missing_csv}; run busybox fetch or busybox <path-to-busybox-or-applet-directory>"
    fi
  else
    status="warn"
    detail="BusyBox fallback detector unavailable"
  fi
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
    if declare -F chroot_busybox_native_missing_tools >/dev/null 2>&1; then
      local missing_tools
      missing_tools="$(chroot_busybox_native_missing_tools)"
      if [[ -n "$missing_tools" ]]; then
        printf '\n%s\n' "$(chroot_busybox_render_missing_tool_guidance "$missing_tools")" >&2
      fi
    fi
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
  chroot_root_reporting_hydrate_original
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
    local busybox_json
    if declare -F chroot_busybox_diagnostics_json >/dev/null 2>&1; then
      busybox_json="$(chroot_busybox_diagnostics_json)"
    else
      busybox_json="{}"
    fi
    "$CHROOT_PYTHON_BIN" - "$report" "${CHROOT_RUNTIME_ROOT:-}" "${CHROOT_ROOT_LAUNCHER_KIND:-}" "${CHROOT_ROOT_LAUNCHER_BIN:-}" "${CHROOT_ROOT_LAUNCHER_SUBCMD:-}" "${CHROOT_ROOT_DIAGNOSTICS:-}" "${CHROOT_ROOT_PROBE_TRACE:-}" "${CHROOT_ROOT_ORIGINAL_LAUNCHER_KIND:-}" "${CHROOT_ROOT_ORIGINAL_LAUNCHER_BIN:-}" "${CHROOT_ROOT_ORIGINAL_LAUNCHER_SUBCMD:-}" "${CHROOT_ROOT_ORIGINAL_DIAGNOSTICS:-}" "${CHROOT_ROOT_ORIGINAL_PROBE_TRACE:-}" "$chroot_backend_label" "$mount_backend_label" "$umount_backend_label" "${CHROOT_HOST_SH:-}" "${CHROOT_BUSYBOX_BIN:-}" "${CHROOT_TOYBOX_BIN:-}" "$selftest_rows" "$busybox_json" <<'PY'
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
    original_root_kind,
    original_root_launcher,
    original_root_subcmd,
    original_root_diagnostics,
    original_root_probe_text,
    chroot_bin,
    mount_bin,
    umount_bin,
    host_sh,
    busybox_bin,
    toybox_bin,
    selftest_text,
    busybox_text,
) = sys.argv[1:21]

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

root_access_detail = ""
for row in rows:
    if row.get("check") == "root_access":
        root_access_detail = str(row.get("detail", ""))
        break

if "current=direct-root" in root_access_detail and original_root_kind and original_root_launcher:
    root_kind = original_root_kind
    root_launcher = original_root_launcher
    root_launcher_subcmd = original_root_subcmd or root_launcher_subcmd
    if original_root_diagnostics:
        root_diagnostics = original_root_diagnostics
    if original_root_probe_text:
        root_probe_text = original_root_probe_text

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

try:
    busybox_doc = json.loads(busybox_text or "{}")
except Exception:
    busybox_doc = {}

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
                "busybox": busybox_doc,
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
  if declare -F chroot_busybox_doctor_summary >/dev/null 2>&1; then
    printf '\n'
    chroot_busybox_doctor_summary
  fi
}
