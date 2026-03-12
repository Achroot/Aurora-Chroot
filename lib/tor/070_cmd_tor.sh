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
    chroot_cmd_unmount "$distro" --no-kill-sessions >/dev/null 2>&1 || true
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
  chroot_tor_remove_rules "$distro" >/dev/null 2>&1 || true
  chroot_tor_stop_daemon "$distro" >/dev/null 2>&1 || true
  chroot_tor_freeze_clear "$distro" >/dev/null 2>&1 || true
  chroot_tor_write_status_file "$distro" 0 "" "" "" "" "" "" 0 "" "" "$warnings_json" "$last_error" "$family"
  chroot_tor_maybe_unmount_after_failure "$distro" "$mounts_before" "$rootfs_mounts_before" "$sessions_before"
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
  local use_saved_bypass=0 use_saved_exit=0
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
  if chroot_tor_run_mode_uses_saved_exit "$run_mode"; then
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
    chroot_tor_disable "$active_distro" >/dev/null 2>&1 || true
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
    chroot_tor_enable_fail "$distro" "$family" "$warnings_json" "host routing probes failed" "host routing probes failed for tor on; run 'tor $distro doctor --json' for details" "$mounts_before" "$rootfs_mounts_before" "$sessions_before" "$nat_error"
  fi
  if [[ "$filter_probe" == "1" ]]; then
    v4_backend="filter"
  elif [[ "$policy4_probe" == "1" ]]; then
    v4_backend="policy"
  else
    [[ -n "$filter_error" ]] && warnings_json="$(chroot_tor_merge_warning_json "$warnings_json" "$filter_error")"
    chroot_tor_enable_fail "$distro" "$family" "$warnings_json" "host routing probes failed" "host routing probes failed for tor on; run 'tor $distro doctor --json' for details" "$mounts_before" "$rootfs_mounts_before" "$sessions_before" "$policy4_error"
  fi
  if [[ "$filter6_probe" == "1" ]]; then
    v6_backend="filter"
  elif [[ "$policy6_probe" == "1" ]]; then
    v6_backend="policy"
  else
    [[ -n "$filter6_error" ]] && warnings_json="$(chroot_tor_merge_warning_json "$warnings_json" "$filter6_error")"
    chroot_tor_enable_fail "$distro" "$family" "$warnings_json" "host routing probes failed" "host routing probes failed for tor on; run 'tor $distro doctor --json' for details" "$mounts_before" "$rootfs_mounts_before" "$sessions_before" "$policy6_error"
  fi

  chroot_tor_stop_daemon "$distro" >/dev/null 2>&1 || true
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
    excerpt="$(chroot_tor_log_excerpt "$distro" 2>/dev/null || true)"
    chroot_tor_enable_fail "$distro" "$family" "$warnings_json" "tor bootstrap timeout" "tor bootstrap did not complete in time inside $distro" "$mounts_before" "$rootfs_mounts_before" "$sessions_before" "" "$excerpt"
  fi

  if ! chroot_tor_apply_rules "$distro" "$daemon_uid" "$v4_backend" "$v6_backend" "$lan_bypass"; then
    excerpt="$(chroot_tor_log_excerpt "$distro" 2>/dev/null || true)"
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
  local json_payload="$1"
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$json_payload" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
rows = data.get("packages", []) if isinstance(data, dict) else data
if not isinstance(rows, list):
    rows = []
print(f"{'Package':<44} {'UID':<8} {'Scope':<8} {'Mode':<8} {'Group'}")
print(f"{'-'*44} {'-'*8} {'-'*8} {'-'*8} {'-'*10}")
count = 0
for row in rows:
    if not isinstance(row, dict):
        continue
    package = str(row.get("package", ""))[:44]
    uid = row.get("uid")
    scope = str(row.get("scope", "unknown") or "unknown")
    mode = "bypass" if row.get("bypassed") else "tor"
    group = ""
    if row.get("shared_uid"):
        group = f"shared:{row.get('uid_package_count') or '?'}"
    print(f"{package:<44} {str(uid):<8} {scope:<8} {mode:<8} {group}")
    count += 1
if count == 0:
    print("No apps matched.")
PY
}

chroot_tor_exit_show_human() {
  local distro="$1"
  local strict codes resolved
  IFS=$'\t' read -r strict codes resolved <<<"$(chroot_tor_exit_resolved_tsv "$distro")"
  chroot_info "Exit strict mode: $( [[ "$strict" == "1" ]] && printf 'on' || printf 'off' )"
  if [[ -n "$resolved" ]]; then
    chroot_info "Configured exit countries: $resolved"
  else
    chroot_info "Configured exit countries: none"
  fi
}

chroot_tor_country_list_human() {
  local json_payload="$1"
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$json_payload" <<'PY'
import json
import sys

rows = json.loads(sys.argv[1])
if not isinstance(rows, list):
    rows = []
print(f"{'Code':<6} {'Country'}")
print(f"{'-'*6} {'-'*40}")
if not rows:
    print("No countries matched.")
for row in rows:
    if not isinstance(row, dict):
        continue
    print(f"{str(row.get('code','')).upper():<6} {str(row.get('name',''))}")
PY
  }

chroot_cmd_tor() {
  local distro=""
  local action json tail_lines pick_rc
  local yes=0
  json=0
  tail_lines=120

  if [[ $# -gt 0 && "$1" != --* && "$1" != "status" && "$1" != "on" && "$1" != "off" && "$1" != "stop" && "$1" != "restart" && "$1" != "freeze" && "$1" != "logs" && "$1" != "newnym" && "$1" != "doctor" && "$1" != "apps" && "$1" != "exit" && "$1" != "remove" ]]; then
    distro="$1"
    shift || true
  fi

  if [[ -z "$distro" ]]; then
    if [[ ! -t 0 ]]; then
      chroot_die "usage: bash path/to/chroot tor <distro> [status|on|off|restart|freeze|logs|newnym|doctor|apps|exit|remove] [args...]"
    fi
    pick_rc=0
    distro="$(chroot_select_installed_distro "Select distro for tor")" || pick_rc=$?
    case "$pick_rc" in
      0) ;;
      2) chroot_die "no installed distros found" ;;
      *) chroot_die "tor command aborted" ;;
    esac
  fi

  chroot_require_distro_arg "$distro"
  chroot_preflight_hard_fail
  [[ -d "$(chroot_distro_rootfs_dir "$distro")" ]] || chroot_die "distro not installed: $distro"

  action="${1:-status}"
  if [[ $# -gt 0 ]]; then
    shift
  fi

  case "$action" in
    status)
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --json) json=1 ;;
          *) chroot_die "unknown tor status arg: $1" ;;
        esac
        shift
      done
      if (( json == 1 )); then
        chroot_tor_status_json "$distro"
      else
        chroot_tor_status_human "$distro"
      fi
      ;;
    logs)
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --tail)
            shift
            [[ $# -gt 0 ]] || chroot_die "--tail requires a value"
            tail_lines="$1"
            ;;
          *)
            chroot_die "unknown tor logs arg: $1"
            ;;
        esac
        shift
      done
      chroot_tor_logs "$distro" "$tail_lines"
      ;;
    apps)
      local apps_action="${1:-list}"
      local scope_filter="all"
      if [[ $# -gt 0 ]]; then
        shift
      fi
      case "$apps_action" in
        list)
          while [[ $# -gt 0 ]]; do
            case "$1" in
              --json) json=1 ;;
              --user-only) scope_filter="user" ;;
              --system-only) scope_filter="system" ;;
              *) chroot_die "unknown tor apps list arg: $1" ;;
            esac
            shift
          done
          chroot_tor_apps_ensure "$distro"
          if (( json == 1 )); then
            chroot_tor_apps_list_json "$distro" "$scope_filter" 0
          else
            chroot_tor_apps_list_human "$(chroot_tor_apps_list_json "$distro" "$scope_filter" 0)"
          fi
          ;;
        search)
          local query="${1:-}"
          [[ -n "$query" ]] || chroot_die "tor apps search requires a query"
          shift || true
          while [[ $# -gt 0 ]]; do
            case "$1" in
              --json) json=1 ;;
              --user-only) scope_filter="user" ;;
              --system-only) scope_filter="system" ;;
              *) chroot_die "unknown tor apps search arg: $1" ;;
            esac
            shift
          done
          if (( json == 1 )); then
            chroot_tor_apps_search_json "$distro" "$query" 0 "$scope_filter"
          else
            chroot_tor_apps_list_human "$(chroot_tor_apps_search_json "$distro" "$query" 0 "$scope_filter")"
          fi
          ;;
        bypass)
          local bypass_action="${1:-show}"
          if [[ $# -gt 0 ]]; then
            shift
          fi
          case "$bypass_action" in
            show)
              while [[ $# -gt 0 ]]; do
                case "$1" in
                  --json) json=1 ;;
                  --user-only) scope_filter="user" ;;
                  --system-only) scope_filter="system" ;;
                  *) chroot_die "unknown tor apps bypass show arg: $1" ;;
                esac
                shift
              done
              if (( json == 1 )); then
                chroot_tor_bypass_show_json "$distro" "$scope_filter"
              else
                chroot_tor_apps_list_human "$(chroot_tor_bypass_show_json "$distro" "$scope_filter")"
              fi
              ;;
            add)
              local query="${1:-}"
              [[ -n "$query" ]] || chroot_die "tor apps bypass add requires an app query"
              shift || true
              while [[ $# -gt 0 ]]; do
                case "$1" in
                  --user-only) scope_filter="user" ;;
                  --system-only) scope_filter="system" ;;
                  *) chroot_die "unknown tor apps bypass add arg: $1" ;;
                esac
                shift
              done
              chroot_lock_acquire "tor" || chroot_die "failed tor lock"
              local package_name group_payload group_count
              local -a uid_group_packages=()
              package_name="$(chroot_tor_app_resolve_query "$distro" "$query" 0 "$scope_filter")"
              group_payload="$(chroot_tor_app_uid_group_packages "$distro" "$package_name")"
              mapfile -t uid_group_packages <<<"$group_payload"
              (( ${#uid_group_packages[@]} > 0 )) || chroot_die "failed to resolve shared-uid group for app: $package_name"
              local member
              for member in "${uid_group_packages[@]}"; do
                [[ -n "$member" ]] || continue
                chroot_tor_bypass_package_add_exact "$distro" "$member"
              done
              chroot_tor_apps_refresh "$distro"
              chroot_tor_targets_invalidate "$distro"
              chroot_lock_release "tor"
              group_count="${#uid_group_packages[@]}"
              chroot_log_info tor "apps-bypass-add distro=$distro package=$package_name"
              if (( group_count > 1 )); then
                chroot_info "Added shared-UID app group to Tor bypass list via $package_name ($group_count packages share that UID)."
              else
                chroot_info "Added app to Tor bypass list: $package_name"
              fi
              ;;
            remove)
              local query="${1:-}"
              [[ -n "$query" ]] || chroot_die "tor apps bypass remove requires an app query"
              shift || true
              while [[ $# -gt 0 ]]; do
                case "$1" in
                  --user-only) scope_filter="user" ;;
                  --system-only) scope_filter="system" ;;
                  *) chroot_die "unknown tor apps bypass remove arg: $1" ;;
                esac
                shift
              done
              chroot_lock_acquire "tor" || chroot_die "failed tor lock"
              local package_name group_payload group_count
              local -a uid_group_packages=()
              package_name="$(chroot_tor_app_resolve_query "$distro" "$query" 1 "$scope_filter")"
              group_payload="$(chroot_tor_app_uid_group_packages "$distro" "$package_name")"
              mapfile -t uid_group_packages <<<"$group_payload"
              (( ${#uid_group_packages[@]} > 0 )) || chroot_die "failed to resolve shared-uid group for app: $package_name"
              local member
              for member in "${uid_group_packages[@]}"; do
                [[ -n "$member" ]] || continue
                chroot_tor_bypass_package_remove_exact "$distro" "$member"
              done
              chroot_tor_apps_refresh "$distro"
              chroot_tor_targets_invalidate "$distro"
              chroot_lock_release "tor"
              group_count="${#uid_group_packages[@]}"
              chroot_log_info tor "apps-bypass-remove distro=$distro package=$package_name"
              if (( group_count > 1 )); then
                chroot_info "Removed shared-UID app group from Tor bypass list via $package_name ($group_count packages share that UID)."
              else
                chroot_info "Removed app from Tor bypass list: $package_name"
              fi
              ;;
            *)
              chroot_die "unknown tor apps bypass action: $bypass_action"
              ;;
          esac
          ;;
        *)
          chroot_die "unknown tor apps action: $apps_action"
          ;;
      esac
      ;;
    exit)
      local exit_action="${1:-show}"
      if [[ $# -gt 0 ]]; then
        shift
      fi
      case "$exit_action" in
        show)
          while [[ $# -gt 0 ]]; do
            case "$1" in
              --json) json=1 ;;
              *) chroot_die "unknown tor exit show arg: $1" ;;
            esac
            shift
          done
          if (( json == 1 )); then
            chroot_tor_exit_show_json "$distro"
          else
            chroot_tor_exit_show_human "$distro"
          fi
          ;;
        list)
          local query=""
          while [[ $# -gt 0 ]]; do
            case "$1" in
              --json) json=1 ;;
              --query)
                shift
                [[ $# -gt 0 ]] || chroot_die "--query requires a value"
                query="$1"
                ;;
              *)
                chroot_die "unknown tor exit list arg: $1"
                ;;
            esac
            shift
          done
          if (( json == 1 )); then
            chroot_tor_country_search_json "$query"
          else
            chroot_tor_country_list_human "$(chroot_tor_country_search_json "$query")"
          fi
          ;;
        add)
          local query="${1:-}"
          [[ -n "$query" ]] || chroot_die "tor exit add requires a country query"
          chroot_lock_acquire "tor" || chroot_die "failed tor lock"
          local code
          code="$(chroot_tor_country_resolve_query "$query")"
          chroot_tor_exit_add_code_exact "$distro" "$code"
          chroot_tor_targets_invalidate "$distro"
          chroot_lock_release "tor"
          chroot_log_info tor "exit-add distro=$distro code=$code"
          chroot_info "Added preferred exit country: ${code^^}"
          ;;
        remove)
          local query="${1:-}"
          [[ -n "$query" ]] || chroot_die "tor exit remove requires a country query"
          chroot_lock_acquire "tor" || chroot_die "failed tor lock"
          local code
          code="$(chroot_tor_country_resolve_query "$query")"
          chroot_tor_exit_remove_code_exact "$distro" "$code"
          chroot_tor_targets_invalidate "$distro"
          chroot_lock_release "tor"
          chroot_log_info tor "exit-remove distro=$distro code=$code"
          chroot_info "Removed preferred exit country: ${code^^}"
          ;;
        clear)
          [[ $# -eq 0 ]] || chroot_die "tor exit clear does not accept extra arguments"
          chroot_lock_acquire "tor" || chroot_die "failed tor lock"
          chroot_tor_exit_clear "$distro"
          chroot_tor_targets_invalidate "$distro"
          chroot_lock_release "tor"
          chroot_log_info tor "exit-clear distro=$distro"
          chroot_info "Cleared exit country preferences for distro '$distro'."
          ;;
        strict)
          local value="${1:-}"
          [[ -n "$value" ]] || chroot_die "tor exit strict requires on|off"
          chroot_lock_acquire "tor" || chroot_die "failed tor lock"
          chroot_tor_exit_set_strict "$distro" "$value"
          chroot_tor_targets_invalidate "$distro"
          chroot_lock_release "tor"
          chroot_log_info tor "exit-strict distro=$distro value=$value"
          chroot_info "Set exit strict mode to ${value,,} for distro '$distro'."
          ;;
        *)
          chroot_die "unknown tor exit action: $exit_action"
          ;;
      esac
      ;;
    newnym)
      [[ $# -eq 0 ]] || chroot_die "tor newnym does not accept extra arguments"
      chroot_lock_acquire "tor" || chroot_die "failed tor lock"
      chroot_tor_newnym "$distro"
      chroot_lock_release "tor"
      chroot_log_info tor "newnym distro=$distro"
      chroot_info "Requested new Tor identity for distro '$distro'."
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
    remove)
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
    on)
      local run_mode="default" lan_bypass="1"
      IFS='|' read -r run_mode lan_bypass <<<"$(chroot_tor_parse_enable_args "on" "$@")"
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
      [[ $# -eq 0 ]] || chroot_die "tor off does not accept extra arguments"
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
      IFS='|' read -r run_mode lan_bypass <<<"$(chroot_tor_parse_enable_args "restart" "$@")"
      chroot_lock_acquire "global" || chroot_die "failed global lock"
      chroot_lock_acquire "tor" || {
        chroot_lock_release "global"
        chroot_die "failed tor lock"
      }
      chroot_tor_disable "$distro" >/dev/null 2>&1 || true
      chroot_tor_enable "$distro" "$run_mode" "$lan_bypass"
      chroot_lock_release "tor"
      chroot_lock_release "global"
      ;;
    *)
      chroot_die "unknown tor action: $action"
      ;;
  esac
}
