chroot_tor_warning_list_json() {
  local warning="${1:-}"
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$warning" <<'PY'
import json
import sys

warning = str(sys.argv[1] or "").strip()
payload = [warning] if warning else []
print(json.dumps(payload))
PY
}

chroot_tor_merge_warning_json() {
  local first_json="${1:-[]}"
  local second_text="${2:-}"
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$first_json" "$second_text" <<'PY'
import json
import sys

base_text, extra_text = sys.argv[1:3]
try:
    payload = json.loads(base_text)
    if not isinstance(payload, list):
        payload = []
except Exception:
    payload = []

extra = str(extra_text or "").strip()
if extra and extra not in payload:
    payload.append(extra)
print(json.dumps(payload))
PY
}

chroot_tor_parse_enable_args() {
  local verb="${1:-on}"
  shift || true

  local configured=0
  local selector=""
  local lan_bypass=1
  local arg=""
  local run_mode=""

  for arg in "$@"; do
    case "$arg" in
      --configured)
        (( configured == 0 )) || chroot_die "duplicate --configured for tor $verb"
        configured=1
        ;;
      --no-lan-bypass)
        [[ "$lan_bypass" == "1" ]] || chroot_die "duplicate --no-lan-bypass for tor $verb"
        lan_bypass=0
        ;;
      apps|exit)
        [[ -z "$selector" ]] || chroot_die "tor $verb accepts only one configured selector: apps or exit"
        selector="$arg"
        ;;
      *)
        chroot_die "unknown tor $verb arg: $arg"
        ;;
    esac
  done

  if [[ -n "$selector" && "$configured" != "1" ]]; then
    chroot_die "tor $verb selector '$selector' requires --configured"
  fi

  if (( configured == 0 )); then
    printf 'default|%s\n' "$lan_bypass"
    return 0
  fi

  case "$selector" in
    "") run_mode="configured" ;;
    apps) run_mode="configured-apps" ;;
    exit) run_mode="configured-exit" ;;
  esac
  printf '%s|%s\n' "$run_mode" "$lan_bypass"
}

chroot_tor_maybe_unmount_after_failure() {
  local distro="$1"
  local mounts_before="${2:-0}"
  local rootfs_mounts_before="${3:-0}"
  local sessions_before="${4:-0}"

  [[ "$mounts_before" =~ ^[0-9]+$ ]] || mounts_before=0
  [[ "$rootfs_mounts_before" =~ ^[0-9]+$ ]] || rootfs_mounts_before=0
  [[ "$sessions_before" =~ ^[0-9]+$ ]] || sessions_before=0

  if (( mounts_before == 0 && rootfs_mounts_before == 0 && sessions_before == 0 )); then
    chroot_log_run_internal_command core unmount "$distro" unmount "$distro" --no-kill-sessions -- chroot_cmd_unmount "$distro" --no-kill-sessions >/dev/null 2>&1 || true
  fi
}

chroot_tor_enable_fail() {
  local distro="$1"
  local family="$2"
  local warnings_json="${3:-[]}"
  local last_error="$4"
  local user_msg="$5"
  local mounts_before="${6:-0}"
  local rootfs_mounts_before="${7:-0}"
  local sessions_before="${8:-0}"
  local extra_warning="${9:-}"
  local excerpt="${10:-}"

  [[ -n "$extra_warning" ]] && warnings_json="$(chroot_tor_merge_warning_json "$warnings_json" "$extra_warning")"
  if [[ -n "${CHROOT_TOR_LAST_RULE_ERROR:-}" ]]; then
    warnings_json="$(chroot_tor_merge_warning_json "$warnings_json" "$CHROOT_TOR_LAST_RULE_ERROR")"
  fi
  chroot_tor_performance_controller_stop "$distro" >/dev/null 2>&1 || true
  chroot_tor_remove_rules "$distro" >/dev/null 2>&1 || true
  chroot_tor_stop_daemon "$distro" >/dev/null 2>&1 || true
  chroot_tor_freeze_clear "$distro" >/dev/null 2>&1 || true
  chroot_tor_write_status_file "$distro" 0 "" "" "" "" "" "" 0 "" "" "$warnings_json" "$last_error" "$family"
  chroot_tor_maybe_unmount_after_failure "$distro" "$mounts_before" "$rootfs_mounts_before" "$sessions_before"
  if declare -F chroot_log_set_pending_error_detail >/dev/null 2>&1; then
    local stage=""
    case "$last_error" in
      *bootstrap*)
        stage="bootstrap"
        ;;
      *routing*)
        stage="routing"
        ;;
      *install*)
        stage="install"
        ;;
      *config*|*configuration*)
        stage="config"
        ;;
      *start*)
        stage="start"
        ;;
      *performance*)
        stage="performance"
        ;;
    esac
    [[ -n "$stage" ]] && chroot_log_set_pending_error_detail "stage" "$stage"
    [[ -n "$last_error" ]] && chroot_log_set_pending_error_detail "error_key" "$last_error"
    [[ -n "$excerpt" ]] && chroot_log_set_pending_error_detail "bootstrap_summary" "$excerpt"
  fi
  if [[ -n "$excerpt" ]]; then
    chroot_die "$user_msg: $excerpt"
  fi
  chroot_die "$user_msg"
}

chroot_tor_enable() {
  local distro="$1"
  local run_mode="${2:-default}"
  local lan_bypass="${3:-1}"
  local family active_distro active_at
  local identity_mode daemon_user daemon_uid daemon_gid warning_text warnings_json
  local termux_uid_included=1 host_uid pid pid_starttime enabled_at excerpt timeout_sec
  local use_saved_bypass=0 use_saved_exit=0 use_performance=0
  local performance_selection_json="" performance_summary=""
  local mounts_before=0 rootfs_mounts_before=0 sessions_before=0
  local nat_probe=0 filter_probe=0 filter6_probe=0 policy4_probe=0 policy6_probe=0
  local nat_error="" filter_error="" filter6_error="" policy4_error="" policy6_error=""
  local v4_backend="filter" v6_backend="filter"

  case "$run_mode" in
    default|configured|configured-apps|configured-exit) ;;
    *) chroot_die "unknown tor run mode: $run_mode" ;;
  esac
  case "$lan_bypass" in
    0|1) ;;
    *) chroot_die "invalid tor lan-bypass mode: $lan_bypass" ;;
  esac
  if chroot_tor_run_mode_uses_saved_bypass "$run_mode"; then
    use_saved_bypass=1
  fi
  if chroot_tor_performance_mode_enabled_for_run "$distro" "$run_mode"; then
    use_performance=1
  fi
  if [[ "$use_performance" != "1" ]] && chroot_tor_run_mode_uses_saved_exit "$run_mode"; then
    use_saved_exit=1
  fi

  chroot_tor_detect_backends 1
  family="$(chroot_tor_detect_distro_family "$distro")"
  mounts_before="$(chroot_mount_count_for_distro "$distro" 2>/dev/null || echo 0)"
  rootfs_mounts_before="$(chroot_mount_count_under_rootfs "$distro" 2>/dev/null || echo 0)"
  sessions_before="$(chroot_session_count "$distro" 2>/dev/null || echo 0)"
  timeout_sec="$(chroot_tor_bootstrap_timeout_seconds)"
  if ! chroot_tor_ensure_tor_installed "$distro"; then
    chroot_tor_enable_fail "$distro" "$family" "[]" "tor install failed" "failed to install tor inside $distro" "$mounts_before" "$rootfs_mounts_before" "$sessions_before"
  fi

  IFS='|' read -r active_distro active_at <<<"$(chroot_tor_global_active_tsv)"
  if [[ -n "$active_distro" && "$active_distro" != "$distro" ]]; then
    chroot_info "Disabling active Tor distro '$active_distro' before enabling '$distro'..."
    chroot_log_run_internal_command tor tor.off "$active_distro" "$active_distro" tor off -- chroot_tor_disable "$active_distro" >/dev/null 2>&1 || true
  fi

  IFS='|' read -r identity_mode daemon_user daemon_uid daemon_gid warning_text <<<"$(chroot_tor_detect_daemon_identity "$distro")"
  if [[ "$daemon_user" == "root" || "$daemon_uid" == "0" ]]; then
    warnings_json="$(chroot_tor_warning_list_json "$warning_text")"
    chroot_tor_enable_fail "$distro" "$family" "$warnings_json" "unsupported tor daemon identity" "refusing to run tor as root inside $distro; install a tor package that provides a dedicated tor user" "$mounts_before" "$rootfs_mounts_before" "$sessions_before"
  fi
  host_uid="$(chroot_host_user_uid 2>/dev/null || true)"
  if [[ -n "$host_uid" && "$host_uid" == "$daemon_uid" ]]; then
    termux_uid_included=0
    warning_text="Aurora host uid matches the distro tor daemon uid; Termux traffic is excluded from tor routing."
  fi
  warnings_json="$(chroot_tor_warning_list_json "$warning_text")"
  IFS='|' read -r nat_probe nat_error filter_probe filter_error filter6_probe filter6_error policy4_probe policy4_error policy6_probe policy6_error <<<"$(chroot_tor_routing_probe_tsv "$daemon_uid")"
  if [[ "$nat_probe" != "1" ]]; then
    chroot_tor_enable_fail "$distro" "$family" "$warnings_json" "host routing probes failed" "host routing probes failed for tor on; run '$distro tor doctor --json' for details" "$mounts_before" "$rootfs_mounts_before" "$sessions_before" "$nat_error"
  fi
  if [[ "$filter_probe" == "1" ]]; then
    v4_backend="filter"
  elif [[ "$policy4_probe" == "1" ]]; then
    v4_backend="policy"
  else
    [[ -n "$filter_error" ]] && warnings_json="$(chroot_tor_merge_warning_json "$warnings_json" "$filter_error")"
    chroot_tor_enable_fail "$distro" "$family" "$warnings_json" "host routing probes failed" "host routing probes failed for tor on; run '$distro tor doctor --json' for details" "$mounts_before" "$rootfs_mounts_before" "$sessions_before" "$policy4_error"
  fi
  if [[ "$filter6_probe" == "1" ]]; then
    v6_backend="filter"
  elif [[ "$policy6_probe" == "1" ]]; then
    v6_backend="policy"
  else
    [[ -n "$filter6_error" ]] && warnings_json="$(chroot_tor_merge_warning_json "$warnings_json" "$filter6_error")"
    chroot_tor_enable_fail "$distro" "$family" "$warnings_json" "host routing probes failed" "host routing probes failed for tor on; run '$distro tor doctor --json' for details" "$mounts_before" "$rootfs_mounts_before" "$sessions_before" "$policy6_error"
  fi

  chroot_tor_stop_daemon "$distro" >/dev/null 2>&1 || true
  chroot_tor_performance_controller_stop "$distro" >/dev/null 2>&1 || true
  chroot_tor_remove_rules "$distro" >/dev/null 2>&1 || true
  chroot_tor_freeze_clear "$distro"

  if ! chroot_tor_apps_refresh "$distro"; then
    chroot_tor_enable_fail "$distro" "$family" "$warnings_json" "failed to refresh tor app inventory" "failed to refresh Android app inventory for tor" "$mounts_before" "$rootfs_mounts_before" "$sessions_before"
  fi
  if ! chroot_tor_targets_generate "$distro" "$termux_uid_included" "$use_saved_bypass"; then
    chroot_tor_enable_fail "$distro" "$family" "$warnings_json" "failed to generate tor uid targets" "failed to generate tor uid targets" "$mounts_before" "$rootfs_mounts_before" "$sessions_before"
  fi
  if ! chroot_tor_prepare_rootfs_paths "$distro" "$daemon_uid" "$daemon_gid"; then
    chroot_tor_enable_fail "$distro" "$family" "$warnings_json" "failed to prepare tor runtime paths" "failed to prepare tor runtime paths inside $distro" "$mounts_before" "$rootfs_mounts_before" "$sessions_before"
  fi
  if ! chroot_tor_write_torrc "$distro" "$daemon_user" "$use_saved_exit"; then
    chroot_tor_enable_fail "$distro" "$family" "$warnings_json" "failed to write tor configuration" "failed to write tor configuration inside $distro" "$mounts_before" "$rootfs_mounts_before" "$sessions_before"
  fi
  if ! chroot_tor_verify_config "$distro"; then
    chroot_tor_enable_fail "$distro" "$family" "$warnings_json" "tor config verification failed" "tor configuration verification failed inside $distro" "$mounts_before" "$rootfs_mounts_before" "$sessions_before"
  fi

  if ! chroot_tor_start_daemon "$distro" "$daemon_uid" "$daemon_gid"; then
    chroot_tor_enable_fail "$distro" "$family" "$warnings_json" "tor daemon failed to start" "tor daemon failed to start inside $distro" "$mounts_before" "$rootfs_mounts_before" "$sessions_before"
  fi

  if ! chroot_tor_wait_for_bootstrap "$distro" "$timeout_sec"; then
    excerpt="$(chroot_tor_bootstrap_summary "$distro" 2>/dev/null || true)"
    chroot_tor_enable_fail "$distro" "$family" "$warnings_json" "tor bootstrap timeout" "tor bootstrap did not complete in time inside $distro" "$mounts_before" "$rootfs_mounts_before" "$sessions_before" "" "$excerpt"
  fi

  if [[ "$use_performance" == "1" ]]; then
    chroot_info "Sampling live Tor exits for performance mode..."
    if ! performance_selection_json="$(chroot_tor_performance_select_json "$distro" "startup")"; then
      excerpt="$(chroot_tor_bootstrap_summary "$distro" 2>/dev/null || true)"
      chroot_tor_enable_fail "$distro" "$family" "$warnings_json" "failed to select performance exit" "tor performance mode could not select a live exit" "$mounts_before" "$rootfs_mounts_before" "$sessions_before" "" "$excerpt"
    fi
    if ! chroot_tor_performance_apply_selection "$distro" "$performance_selection_json" "startup"; then
      excerpt="$(chroot_tor_bootstrap_summary "$distro" 2>/dev/null || true)"
      chroot_tor_enable_fail "$distro" "$family" "$warnings_json" "failed to apply performance exit" "tor performance mode could not apply the selected exit" "$mounts_before" "$rootfs_mounts_before" "$sessions_before" "" "$excerpt"
    fi
  else
    chroot_tor_performance_clear "$distro" >/dev/null 2>&1 || true
  fi

  if ! chroot_tor_apply_rules "$distro" "$daemon_uid" "$v4_backend" "$v6_backend" "$lan_bypass"; then
    excerpt="$(chroot_tor_bootstrap_summary "$distro" 2>/dev/null || true)"
    chroot_tor_enable_fail "$distro" "$family" "$warnings_json" "failed to apply tor routing rules" "failed to apply tor routing rules" "$mounts_before" "$rootfs_mounts_before" "$sessions_before" "" "$excerpt"
  fi

  if ! chroot_tor_rules_active "$distro"; then
    warnings_json="$(chroot_tor_merge_warning_json "$warnings_json" "routing verification failed after apply")"
    chroot_tor_clear_global_active
    chroot_tor_enable_fail "$distro" "$family" "$warnings_json" "tor routing rules did not become active" "tor routing rules did not become active after apply" "$mounts_before" "$rootfs_mounts_before" "$sessions_before"
  fi

  pid="$(chroot_tor_current_pid "$distro" 2>/dev/null || true)"
  pid_starttime=""
  if [[ -n "$pid" ]]; then
    pid_starttime="$(chroot_tor_pid_starttime "$pid" 2>/dev/null || true)"
  fi
  enabled_at="$(chroot_now_ts)"

  chroot_session_remove "$distro" "tor" >/dev/null 2>&1 || true
  if [[ -n "$pid" ]]; then
    chroot_session_add "$distro" "tor" "tor" "aurora tor daemon" "$pid"
  fi

  chroot_tor_write_status_file "$distro" 1 "$enabled_at" "$run_mode" "$identity_mode" "$daemon_user" "$daemon_uid" "$daemon_gid" "$termux_uid_included" "$pid" "$pid_starttime" "$warnings_json" "" "$family" "$lan_bypass"
  chroot_tor_write_global_active "$distro" "$enabled_at"
  if [[ "$use_performance" == "1" ]]; then
    chroot_tor_performance_controller_start "$distro" >/dev/null || chroot_warn "performance monitor did not start; selection remains pinned but dynamic reselection is unavailable."
    performance_summary="$("$CHROOT_PYTHON_BIN" - "$performance_selection_json" <<'PY'
import json
import sys

try:
    payload = json.loads(sys.argv[1])
except Exception:
    payload = {}
best = payload.get("best", {}) if isinstance(payload.get("best"), dict) else {}
probe = best.get("probe", {}) if isinstance(best.get("probe"), dict) else {}
parts = []
if best.get("nickname") or best.get("fingerprint"):
    parts.append(str(best.get("nickname") or best.get("fingerprint") or ""))
if best.get("country_code"):
    parts.append(str(best.get("country_code") or "").upper())
if probe.get("speed_mbps") not in (None, ""):
    parts.append(f"{probe.get('speed_mbps')} Mbps")
if probe.get("latency_ms") not in (None, ""):
    parts.append(f"{probe.get('latency_ms')} ms")
if parts:
    print("Performance exit selected: " + " | ".join(parts))
PY
)"
    [[ -n "$performance_summary" ]] && chroot_info "$performance_summary"
  fi
  chroot_log_info tor "enabled distro=$distro mode=$run_mode pid=${pid:-unknown} user=$daemon_user uid=$daemon_uid termux_uid_included=$termux_uid_included lan_bypass=$lan_bypass"
  chroot_info "Tor mode enabled through distro '$distro' ($run_mode)."
}

chroot_tor_disable() {
  local distro="$1"
  local active_distro active_at
  local enabled_saved identity_mode daemon_user daemon_uid daemon_gid termux_uid_included activated_saved last_error saved_distro saved_family
  local family off_error=""

  chroot_tor_detect_backends 0
  family="$(chroot_tor_detect_distro_family "$distro")"
  IFS='|' read -r active_distro active_at <<<"$(chroot_tor_global_active_tsv)"
  IFS='|' read -r enabled_saved identity_mode daemon_user daemon_uid daemon_gid termux_uid_included activated_saved last_error saved_distro saved_family <<<"$(chroot_tor_saved_state_tsv "$distro")"

  chroot_tor_performance_controller_stop "$distro" >/dev/null 2>&1 || true

  if [[ -n "$active_distro" && "$active_distro" == "$distro" ]]; then
    if ! chroot_tor_remove_rules "$distro"; then
      off_error="failed to remove tor routing rules cleanly"
    fi
    chroot_tor_clear_global_active
  fi

  if ! chroot_tor_stop_daemon "$distro"; then
    if [[ -n "$off_error" ]]; then
      off_error="$off_error; tor daemon may still be running"
    else
      off_error="tor daemon may still be running"
    fi
  fi

  chroot_session_remove "$distro" "tor" >/dev/null 2>&1 || true
  chroot_tor_targets_invalidate "$distro"
  chroot_tor_policy_clear_state "$distro"
  chroot_tor_freeze_clear "$distro"
  chroot_tor_write_status_file "$distro" 0 "" "" "" "" "" "" 0 "" "" "[]" "$off_error" "$family"
  if [[ -n "$off_error" ]]; then
    chroot_log_warn tor "disabled-with-warning distro=$distro msg=$off_error"
    chroot_warn "$off_error"
    return 1
  fi

  chroot_log_info tor "disabled distro=$distro"
  chroot_info "Tor mode disabled for distro '$distro'."
}

chroot_tor_apps_list_human() {
  chroot_require_python
  "$CHROOT_PYTHON_BIN" -c '
import json
import sys

try:
    data = json.load(sys.stdin)
except Exception:
    data = {}
rows = data.get("packages", []) if isinstance(data, dict) else []
print("[x] = tunneled through Tor | [ ] = bypassed")
printed = 0
for row in rows if isinstance(rows, list) else []:
    if not isinstance(row, dict):
        continue
    marker = "[ ]" if row.get("bypassed") else "[x]"
    value = str(row.get("display_name") or row.get("label") or row.get("package") or "")
    print("{} {}".format(marker, value))
    printed += 1
if printed == 0:
    print("No apps matched.")
'
}

chroot_cmd_tor() {
  local distro="${1:-}"
  local action json
  local yes=0
  json=0

  [[ -n "$distro" ]] || chroot_die "usage: bash path/to/chroot <distro> tor [status|on|start|off|stop|restart|freeze|newnym|doctor|apps|exit|remove|rm] [args...]"
  shift || true

  chroot_require_distro_arg "$distro"
  chroot_preflight_hard_fail
  [[ -d "$(chroot_distro_rootfs_dir "$distro")" ]] || chroot_die "distro not installed: $distro"

  action="${1:-status}"
  if [[ $# -gt 0 ]]; then
    shift
  fi

  case "$action" in
    status)
      local apps_refresh_ok=0
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --json) json=1 ;;
          *) chroot_die "unknown tor status arg: $1" ;;
        esac
        shift
      done
      chroot_lock_acquire "tor" || chroot_die "failed tor lock"
      if chroot_log_run_internal_command tor tor.apps.refresh "$distro" "$distro" tor apps refresh --json -- chroot_tor_apps_refresh "$distro" 0 >/dev/null 2>&1; then
        apps_refresh_ok=1
      fi
      chroot_log_run_internal_command tor tor.exit.refresh "$distro" "$distro" tor exit refresh --json -- chroot_tor_exit_cache_refresh "$distro" >/dev/null 2>&1 || true
      chroot_lock_release "tor"
      CHROOT_TOR_STATUS_APPS_REFRESH_OK="$apps_refresh_ok"
      if (( json == 1 )); then
        chroot_tor_status_json "$distro"
      else
        chroot_tor_status_human "$distro"
      fi
      unset CHROOT_TOR_STATUS_APPS_REFRESH_OK
      ;;
    apps)
      local apps_action="${1:-list}"
      if [[ $# -gt 0 ]]; then
        shift
      fi
      case "$apps_action" in
        list)
          local scope_filter="all"
          local mode_filter="all"
          while [[ $# -gt 0 ]]; do
            case "$1" in
              --json) json=1 ;;
              --user) scope_filter="user" ;;
              --system) scope_filter="system" ;;
              --unknown) scope_filter="unknown" ;;
              *) chroot_die "unknown tor apps list arg: $1" ;;
            esac
            shift
          done
          if (( json == 1 )); then
            chroot_tor_apps_list_json "$distro" "$scope_filter" "$mode_filter" "" 0
          else
            chroot_tor_apps_list_json "$distro" "$scope_filter" "$mode_filter" "" 0 | chroot_tor_apps_list_human
          fi
          ;;
        refresh)
          while [[ $# -gt 0 ]]; do
            case "$1" in
              --json) json=1 ;;
              *) chroot_die "unknown tor apps refresh arg: $1" ;;
            esac
            shift
          done
          if (( json == 1 )); then
            chroot_tor_apps_list_json "$distro" "all" "all" "" 1
          else
            chroot_tor_apps_list_json "$distro" "all" "all" "" 1 >/dev/null
            chroot_info "Refreshed Apps Tunneling inventory for distro '$distro'."
          fi
          ;;
        set)
          local app_query_csv="${1:-}"
          local app_mode="${2:-}"
          local resolved_apps=""
          [[ -n "$app_query_csv" ]] || chroot_die "tor apps set requires an app query or comma-separated app list"
          [[ -n "$app_mode" ]] || chroot_die "tor apps set requires a mode: tunneled|bypassed"
          shift 2 || true
          [[ $# -eq 0 ]] || chroot_die "unknown tor apps set arg: $1"
          case "$app_mode" in
            tunneled|bypassed) ;;
            *) chroot_die "invalid tor apps set mode: $app_mode (expected: tunneled|bypassed)" ;;
          esac
          chroot_lock_acquire "tor" || chroot_die "failed tor lock"
          local query_token package_name
          local -a package_names=()
          IFS=',' read -r -a _raw_queries <<<"$app_query_csv"
          for query_token in "${_raw_queries[@]}"; do
            query_token="${query_token#"${query_token%%[![:space:]]*}"}"
            query_token="${query_token%"${query_token##*[![:space:]]}"}"
            [[ -n "$query_token" ]] || continue
            package_name="$(chroot_tor_app_resolve_query "$distro" "$query_token")"
            [[ -n "$package_name" ]] || chroot_die "failed to resolve app query: $query_token"
            package_names+=("$package_name")
          done
          (( ${#package_names[@]} > 0 )) || chroot_die "tor apps set did not resolve any apps"
          resolved_apps="$(chroot_tor_apps_describe_packages "$distro" "${package_names[@]}")"
          chroot_tor_apps_set_mode_packages "$distro" "$app_mode" "${package_names[@]}"
          chroot_lock_release "tor"
          chroot_log_info tor "apps-set distro=$distro count=${#package_names[@]} mode=$app_mode"
          if [[ "$app_mode" == "bypassed" ]]; then
            chroot_info "Saved app selection as bypassed: ${resolved_apps:-${package_names[*]}}"
          else
            chroot_info "Saved app selection as tunneled: ${resolved_apps:-${package_names[*]}}"
          fi
          ;;
        apply)
          local selection_file=""
          local use_stdin=0
          while [[ $# -gt 0 ]]; do
            case "$1" in
              --json) json=1 ;;
              --file)
                shift
                [[ $# -gt 0 ]] || chroot_die "--file requires a path"
                selection_file="$1"
                ;;
              --stdin)
                use_stdin=1
                ;;
              *) chroot_die "unknown tor apps apply arg: $1" ;;
            esac
            shift
          done
          if (( use_stdin == 1 )) && [[ -n "$selection_file" ]]; then
            chroot_die "tor apps apply accepts either --file <path> or --stdin, not both"
          fi
          if (( use_stdin == 0 )) && [[ -z "$selection_file" ]]; then
            chroot_die "tor apps apply requires --file <path> or --stdin"
          fi
          if (( use_stdin == 1 )); then
            chroot_tor_ensure_state_layout "$distro"
            selection_file="$CHROOT_TMP_DIR/tor-apps-apply.$$.json"
            cat >"$selection_file"
          fi
          chroot_lock_acquire "tor" || chroot_die "failed tor lock"
          chroot_tor_apps_apply_selection_file "$distro" "$selection_file"
          chroot_lock_release "tor"
          chroot_log_info tor "apps-apply distro=$distro file=$selection_file"
          if (( use_stdin == 1 )); then
            rm -f -- "$selection_file"
          fi
          if (( json == 1 )); then
            chroot_tor_apps_list_json "$distro" "all" "all" "" 0
          else
            chroot_info "Saved Apps Tunneling selection."
          fi
          ;;
        *)
          chroot_die "unknown tor apps action: $apps_action (expected: list|refresh|set|apply)"
          ;;
      esac
      ;;
    exit)
      local exit_action="${1:-list}"
      if [[ $# -gt 0 ]]; then
        shift
      fi
      case "$exit_action" in
        list)
          while [[ $# -gt 0 ]]; do
            case "$1" in
              --json) json=1 ;;
              *)
                chroot_die "unknown tor exit list arg: $1"
                ;;
            esac
            shift
          done
          if (( json == 1 )); then
            chroot_tor_exit_list_json "$distro" "0" "" 0
          else
            chroot_tor_exit_list_json "$distro" "0" "" 0 | chroot_tor_exit_list_human
          fi
          ;;
        performance-ignore)
          local perf_ignore_action="${1:-list}"
          if [[ $# -gt 0 ]]; then
            shift
          fi
          case "$perf_ignore_action" in
            list)
              while [[ $# -gt 0 ]]; do
                case "$1" in
                  --json) json=1 ;;
                  *)
                    chroot_die "unknown tor exit performance-ignore list arg: $1"
                    ;;
                esac
                shift
              done
              if (( json == 1 )); then
                chroot_tor_exit_performance_ignore_list_json "$distro" 0 ""
              else
                chroot_tor_exit_performance_ignore_list_json "$distro" 0 "" | chroot_tor_exit_performance_ignore_list_human
              fi
              ;;
            set)
              local value_a="${1:-}"
              local value_b="${2:-}"
              local resolved_countries=""
              [[ -n "$value_a" ]] || chroot_die "tor exit performance-ignore set requires a country list"
              [[ -n "$value_b" ]] || chroot_die "tor exit performance-ignore set requires a mode"
              shift 2 || true
              [[ $# -eq 0 ]] || chroot_die "unknown tor exit performance-ignore set arg: $1"
              case "${value_b,,}" in
                ignored|allowed) ;;
                *) chroot_die "tor exit performance-ignore set mode must be ignored|allowed" ;;
              esac
              chroot_lock_acquire "tor" || chroot_die "failed tor lock"
              local token code
              local -a codes=()
              IFS=',' read -r -a _raw_exit_queries <<<"$value_a"
              for token in "${_raw_exit_queries[@]}"; do
                token="${token#"${token%%[![:space:]]*}"}"
                token="${token%"${token##*[![:space:]]}"}"
                [[ -n "$token" ]] || continue
                code="$(chroot_tor_country_resolve_query "$token")"
                [[ -n "$code" ]] || chroot_die "failed to resolve performance-ignore query: $token"
                codes+=("$code")
              done
              (( ${#codes[@]} > 0 )) || chroot_die "tor exit performance-ignore set did not resolve any countries"
              resolved_countries="$(chroot_tor_exit_describe_codes "${codes[@]}")"
              chroot_tor_exit_set_performance_ignore_codes_mode "$distro" "${value_b,,}" "${codes[@]}"
              chroot_lock_release "tor"
              chroot_log_info tor "exit-performance-ignore-set distro=$distro count=${#codes[@]} mode=${value_b,,}"
              if [[ "${value_b,,}" == "ignored" ]]; then
                chroot_info "Saved performance-ignore countries: ${resolved_countries:-${codes[*]}}"
              else
                chroot_info "Allowed performance countries again: ${resolved_countries:-${codes[*]}}"
              fi
              ;;
            *)
              chroot_die "unknown tor exit performance-ignore action: $perf_ignore_action (expected: list|set)"
              ;;
          esac
          ;;
        refresh)
          while [[ $# -gt 0 ]]; do
            case "$1" in
              --json) json=1 ;;
              *)
                chroot_die "unknown tor exit refresh arg: $1"
                ;;
            esac
            shift
          done
          if (( json == 1 )); then
            chroot_tor_exit_list_json "$distro" "0" "" 1
          else
            chroot_tor_exit_list_json "$distro" "0" "" 1 >/dev/null
            chroot_info "Refreshed Exit Tunneling inventory for distro '$distro'."
          fi
          ;;
        set)
          local value_a="${1:-}"
          local value_b="${2:-}"
          local resolved_countries=""
          [[ -n "$value_a" ]] || chroot_die "tor exit set requires a country list, 'strict', or 'performance'"
          [[ -n "$value_b" ]] || chroot_die "tor exit set requires a mode"
          shift 2 || true
          [[ $# -eq 0 ]] || chroot_die "unknown tor exit set arg: $1"
          chroot_lock_acquire "tor" || chroot_die "failed tor lock"
          if [[ "${value_a,,}" == "strict" ]]; then
            case "${value_b,,}" in
              on|off) ;;
              *) chroot_die "tor exit set strict requires on|off" ;;
            esac
            chroot_tor_exit_set_strict "$distro" "$value_b"
            chroot_lock_release "tor"
            chroot_log_info tor "exit-set-strict distro=$distro value=$value_b"
            chroot_info "Set Exit Tunneling strict to ${value_b,,}."
          elif [[ "${value_a,,}" == "performance" ]]; then
            case "${value_b,,}" in
              on|off) ;;
              *) chroot_die "tor exit set performance requires on|off" ;;
            esac
            chroot_tor_exit_set_performance "$distro" "$value_b"
            chroot_lock_release "tor"
            chroot_log_info tor "exit-set-performance distro=$distro value=$value_b"
            chroot_info "Set Exit Tunneling performance to ${value_b,,}."
          else
            case "${value_b,,}" in
              selected|unselected) ;;
              *) chroot_die "tor exit set mode must be selected|unselected" ;;
            esac
            local token code
            local -a codes=()
            IFS=',' read -r -a _raw_exit_queries <<<"$value_a"
            for token in "${_raw_exit_queries[@]}"; do
              token="${token#"${token%%[![:space:]]*}"}"
              token="${token%"${token##*[![:space:]]}"}"
              [[ -n "$token" ]] || continue
              code="$(chroot_tor_country_resolve_query "$token")"
              [[ -n "$code" ]] || chroot_die "failed to resolve exit query: $token"
              codes+=("$code")
            done
            (( ${#codes[@]} > 0 )) || chroot_die "tor exit set did not resolve any countries"
            resolved_countries="$(chroot_tor_exit_describe_codes "${codes[@]}")"
            chroot_tor_exit_set_codes_mode "$distro" "${value_b,,}" "${codes[@]}"
            chroot_lock_release "tor"
            chroot_log_info tor "exit-set distro=$distro count=${#codes[@]} mode=${value_b,,}"
            if [[ "${value_b,,}" == "selected" ]]; then
              chroot_info "Saved exit selection as selected: ${resolved_countries:-${codes[*]}}"
            else
              chroot_info "Saved exit selection as unselected: ${resolved_countries:-${codes[*]}}"
            fi
          fi
          ;;
        apply)
          local selection_file=""
          local use_stdin=0
          while [[ $# -gt 0 ]]; do
            case "$1" in
              --json) json=1 ;;
              --file)
                shift
                [[ $# -gt 0 ]] || chroot_die "--file requires a path"
                selection_file="$1"
                ;;
              --stdin)
                use_stdin=1
                ;;
              *) chroot_die "unknown tor exit apply arg: $1" ;;
            esac
            shift
          done
          if (( use_stdin == 1 )) && [[ -n "$selection_file" ]]; then
            chroot_die "tor exit apply accepts either --file <path> or --stdin, not both"
          fi
          if (( use_stdin == 0 )) && [[ -z "$selection_file" ]]; then
            chroot_die "tor exit apply requires --file <path> or --stdin"
          fi
          if (( use_stdin == 1 )); then
            chroot_tor_ensure_state_layout "$distro"
            selection_file="$CHROOT_TMP_DIR/tor-exit-apply.$$.json"
            cat >"$selection_file"
          fi
          chroot_lock_acquire "tor" || chroot_die "failed tor lock"
          chroot_tor_exit_apply_selection_file "$distro" "$selection_file"
          chroot_lock_release "tor"
          chroot_log_info tor "exit-apply distro=$distro file=$selection_file"
          if (( use_stdin == 1 )); then
            rm -f -- "$selection_file"
          fi
          if (( json == 1 )); then
            chroot_tor_exit_list_json "$distro" "0" "" 0
          else
            chroot_info "Saved Exit Tunneling selection."
          fi
          ;;
        *)
          chroot_die "unknown tor exit action: $exit_action (expected: list|performance-ignore|refresh|set|apply)"
          ;;
      esac
      ;;
    newnym)
      [[ $# -eq 0 ]] || chroot_die "tor newnym does not accept extra arguments"
      local performance_active=0
      if chroot_tor_performance_mode_enabled_for_run "$distro" "$(chroot_tor_saved_run_mode "$distro" | tr -d '[:space:]')"; then
        performance_active=1
      fi
      chroot_lock_acquire "tor" || chroot_die "failed tor lock"
      chroot_tor_newnym "$distro"
      chroot_lock_release "tor"
      chroot_log_info tor "newnym distro=$distro"
      if (( performance_active == 1 )); then
        chroot_info "Requested background performance reselection for distro '$distro'. Aurora is sampling now, and if it finds a better relay it will apply it to your new streams. Existing streams stay on their current circuit until they finish."
      else
        chroot_info "Requested new Tor identity for distro '$distro'."
      fi
      ;;
    freeze)
      [[ $# -eq 0 ]] || chroot_die "tor freeze does not accept extra arguments"
      chroot_lock_acquire "tor" || chroot_die "failed tor lock"
      chroot_tor_freeze_current "$distro"
      chroot_lock_release "tor"
      chroot_log_info tor "freeze distro=$distro"
      chroot_info "Pinned current Tor exit for distro '$distro' until newnym, off, or restart."
      ;;
    doctor)
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --json) json=1 ;;
          *) chroot_die "unknown tor doctor arg: $1" ;;
        esac
        shift
      done
      chroot_lock_acquire "tor" || chroot_die "failed tor lock"
      if (( json == 1 )); then
        chroot_tor_doctor_json "$distro"
      else
        chroot_tor_doctor_human "$distro"
      fi
      chroot_lock_release "tor"
      ;;
    remove|rm)
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --yes) yes=1 ;;
          *) chroot_die "unknown tor remove arg: $1" ;;
        esac
        shift
      done
      if (( yes == 0 )); then
        if [[ ! -t 0 ]]; then
          chroot_die "tor remove requires --yes in non-interactive mode"
        fi
        printf "Remove Aurora-managed Tor state and Tor runtime/config/log/cache directories for '%s' but keep installed packages? [y/N]: " "$distro" >&2
        local answer=""
        read -r answer
        case "$answer" in
          y|Y|yes|YES) ;;
          *) chroot_die "tor remove aborted" ;;
        esac
      fi
      chroot_lock_acquire "global" || chroot_die "failed global lock"
      chroot_lock_acquire "tor" || {
        chroot_lock_release "global"
        chroot_die "failed tor lock"
      }
      chroot_tor_remove_managed_files "$distro"
      chroot_lock_release "tor"
      chroot_lock_release "global"
      chroot_log_info tor "remove distro=$distro"
      chroot_info "Removed Aurora-managed Tor state and Tor runtime/config/log/cache directories for distro '$distro' (packages kept)."
      ;;
    on|start)
      local run_mode="default" lan_bypass="1"
      IFS='|' read -r run_mode lan_bypass <<<"$(chroot_tor_parse_enable_args "$action" "$@")"
      chroot_lock_acquire "global" || chroot_die "failed global lock"
      chroot_lock_acquire "tor" || {
        chroot_lock_release "global"
        chroot_die "failed tor lock"
      }
      chroot_tor_enable "$distro" "$run_mode" "$lan_bypass"
      chroot_lock_release "tor"
      chroot_lock_release "global"
      ;;
    off|stop)
      [[ $# -eq 0 ]] || chroot_die "tor $action does not accept extra arguments"
      chroot_lock_acquire "global" || chroot_die "failed global lock"
      chroot_lock_acquire "tor" || {
        chroot_lock_release "global"
        chroot_die "failed tor lock"
      }
      chroot_tor_disable "$distro"
      chroot_lock_release "tor"
      chroot_lock_release "global"
      ;;
    restart)
      local run_mode="default" lan_bypass="1"
      local -a internal_on_argv=("$distro" "tor" "on")
      IFS='|' read -r run_mode lan_bypass <<<"$(chroot_tor_parse_enable_args "restart" "$@")"
      case "$run_mode" in
        configured)
          internal_on_argv+=("--configured")
          ;;
        configured-apps)
          internal_on_argv+=("--configured" "apps")
          ;;
        configured-exit)
          internal_on_argv+=("--configured" "exit")
          ;;
      esac
      if [[ "$lan_bypass" == "0" ]]; then
        internal_on_argv+=("--no-lan-bypass")
      fi
      chroot_lock_acquire "global" || chroot_die "failed global lock"
      chroot_lock_acquire "tor" || {
        chroot_lock_release "global"
        chroot_die "failed tor lock"
      }
      chroot_log_run_internal_command tor tor.off "$distro" "$distro" tor off -- chroot_tor_disable "$distro" >/dev/null 2>&1 || true
      chroot_log_run_internal_command tor tor.on "$distro" "${internal_on_argv[@]}" -- chroot_tor_enable "$distro" "$run_mode" "$lan_bypass"
      chroot_lock_release "tor"
      chroot_lock_release "global"
      ;;
    *)
      chroot_die "unknown tor action: $action (expected: status|on|start|off|stop|restart|freeze|newnym|doctor|apps|exit|remove|rm)"
      ;;
  esac
}
