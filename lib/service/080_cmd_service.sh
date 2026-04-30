chroot_cmd_service() {
  local distro="${1:-}"
  [[ -n "$distro" ]] || chroot_die "usage: bash path/to/chroot <distro> service <action> [args] (actions: list|status|on|start|off|stop|restart|add|install|remove|rm)"
  shift || true

  chroot_require_distro_arg "$distro"
  chroot_preflight_hard_fail
  [[ -d "$(chroot_distro_rootfs_dir "$distro")" ]] || chroot_die "distro not installed: $distro"
  
  local action="${1:-list}"
  if [[ $# -gt 0 ]]; then shift; fi
  
  case "$action" in
    list|status)
      if [[ "${1:-}" == "--json" ]]; then
        chroot_service_status_json "$distro"
      else
        local json_out
        json_out="$(chroot_service_status_json "$distro")"
        chroot_require_python
        "$CHROOT_PYTHON_BIN" - "$json_out" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
print(f"{'Service Name':<20} {'Status':<10} {'PID':<8} {'Command'}")
print(f"{'-'*20} {'-'*10} {'-'*8} {'-'*30}")
for row in data:
    pid = row['pid'] if row['pid'] else "-"
    print(f"{row['name']:<20} {row['state']:<10} {pid:<8} {row['command']}")
if not data:
    print("No services defined.")
PY
        chroot_service_print_ssh_connect_help_for_distro "$distro" 1
      fi
      ;;
    add)
      local name="${1:-}"
      shift || chroot_die "service add requires <name> <command>"
      local cmd="$*"
      [[ -n "$name" && -n "$cmd" ]] || chroot_die "service add requires <name> <command>"
      chroot_require_service_name "$name"
      chroot_service_add_def "$distro" "$name" "$cmd"
      ;;
    install)
      local builtin_id="${1:-}"
      if [[ "$builtin_id" == "--json" ]]; then
        [[ $# -eq 1 ]] || chroot_die "service install --json does not accept extra arguments"
        chroot_service_builtin_catalog_json
        return 0
      fi
      if [[ "$builtin_id" == "--list" ]]; then
        [[ $# -eq 1 ]] || chroot_die "service install --list does not accept extra arguments"
        chroot_service_builtin_list_human
        return 0
      fi
      if [[ -z "$builtin_id" ]]; then
        if [[ ! -t 0 ]]; then
          chroot_die "service install requires <builtin-id> in non-interactive mode (use --json to list)"
        fi
        local pick_rc=0
        builtin_id="$(chroot_service_select_builtin "Select built-in service to install")" || pick_rc=$?
        case "$pick_rc" in
          0) ;;
          2) chroot_die "no built-in services available" ;;
          *) chroot_die "service install aborted" ;;
        esac
      else
        shift || true
      fi
      if [[ "$builtin_id" == "desktop" ]]; then
        local profile_id="" reinstall=0
        while [[ $# -gt 0 ]]; do
          case "$1" in
            --profiles)
              if [[ -n "$profile_id" || "$reinstall" == "1" ]]; then
                chroot_die "desktop profile query cannot be combined with --profile or --reinstall"
              fi
              shift || true
              [[ "${1:-}" == "--json" && $# -eq 1 ]] || chroot_die "desktop profile query requires: $distro service install desktop --profiles --json"
              chroot_service_desktop_profiles_json "$distro"
              return 0
              ;;
            --profile)
              shift || true
              [[ -n "${1:-}" ]] || chroot_die "desktop install requires a value after --profile"
              [[ -z "$profile_id" ]] || chroot_die "desktop install profile was provided more than once"
              profile_id="$1"
              shift || true
              ;;
            --reinstall)
              reinstall=1
              shift || true
              ;;
            --json)
              chroot_die "desktop profile query requires: $distro service install desktop --profiles --json"
              ;;
            --list)
              chroot_die "--list is only valid as: $distro service install --list"
              ;;
            *)
              chroot_die "unknown desktop install argument: $1"
              ;;
          esac
        done
        if [[ "$reinstall" == "1" && -z "$profile_id" ]]; then
          chroot_die "desktop --reinstall requires --profile <xfce|lxqt>"
        fi
        chroot_service_install_builtin "$distro" "$builtin_id" "$profile_id" "$reinstall"
        return 0
      fi
      if [[ $# -gt 0 ]]; then
        case "$1" in
          --profile|--profiles|--reinstall)
            chroot_die "$1 is only valid with '$distro service install desktop'"
            ;;
          *)
            chroot_die "unknown service install argument for $builtin_id: $1"
            ;;
        esac
      fi
      chroot_service_install_builtin "$distro" "$builtin_id"
      ;;
    remove|rm)
      local name="${1:-}"
      if [[ -z "$name" ]]; then
        if [[ ! -t 0 ]]; then
          chroot_die "service $action requires <name> in non-interactive mode"
        fi
        local pick_rc=0
        name="$(chroot_service_select_def "$distro" "Select service to remove")" || pick_rc=$?
        case "$pick_rc" in
          0) ;;
          2) chroot_die "no services defined for $distro" ;;
          *) chroot_die "service $action aborted" ;;
        esac
      fi
      chroot_require_service_name "$name"
      if [[ "${name,,}" == "$CHROOT_SERVICE_DESKTOP_SERVICE_NAME" ]]; then
        chroot_service_desktop_remove "$distro"
        return 0
      fi
      local def_file
      def_file="$(chroot_service_def_file "$distro" "$name")"
      chroot_info "Removing service '$name' from $distro"
      chroot_info "Will stop tracked service session: svc-$name (if running)"
      chroot_info "Will delete definition file: $def_file"
      chroot_log_run_internal_command service service.stop "$distro" "$distro" service stop "$name" -- chroot_service_stop "$distro" "$name"
      chroot_service_remove_def "$distro" "$name"
      ;;
    on|start)
      local name="${1:-}"
      [[ -n "$name" ]] || chroot_die "service $action requires <name>"
      chroot_require_service_name "$name"
      if [[ "${name,,}" == "$CHROOT_SERVICE_DESKTOP_SERVICE_NAME" ]]; then
        chroot_service_desktop_start "$distro"
      elif chroot_service_is_pcbridge "$name"; then
        local running_pid
        running_pid="$(chroot_service_get_pid "$distro" "$name" 2>/dev/null || true)"
        if [[ -n "$running_pid" ]]; then
          chroot_info "Service '$name' is already running (PID: $running_pid)"
          chroot_info "Use restart to switch pcbridge mode: [f] setup, [c] cleanup, [s] normal."
          return 0
        fi

        local pcbridge_mode_line pcbridge_mode pcbridge_action pcbridge_prefix
        pcbridge_mode_line="$(chroot_service_pcbridge_select_start_mode "$distro")"
        IFS=$'\t' read -r pcbridge_mode pcbridge_action <<<"$pcbridge_mode_line"
        [[ -n "$pcbridge_mode" ]] || pcbridge_mode="normal"
        pcbridge_prefix=""
        if [[ "$pcbridge_mode" == "normal" ]]; then
          if ! chroot_service_pcbridge_has_paired_keys "$distro"; then
            chroot_die "pcbridge option [s] requires an existing paired PC key in /etc/aurora-pcbridge/authorized_keys for $distro. Run $distro service start pcbridge or $distro service restart pcbridge and choose [f] first-run setup to pair a PC first."
          fi
        else
          pcbridge_prefix="AURORA_PCBRIDGE_PAIRING=1 AURORA_PCBRIDGE_ACTION=$pcbridge_action"
        fi
        chroot_service_builtin_install_assets "$distro" "pcbridge"
        chroot_service_start "$distro" "$name" "$pcbridge_prefix"
        chroot_service_pcbridge_print_after_start "$distro" "$pcbridge_mode" "$pcbridge_action"
      else
        chroot_service_start "$distro" "$name"
        chroot_service_print_ssh_connect_help "$distro" "$name" 1
      fi
      ;;
    off|stop)
      local name="${1:-}"
      [[ -n "$name" ]] || chroot_die "service $action requires <name>"
      chroot_require_service_name "$name"
      if [[ "${name,,}" == "$CHROOT_SERVICE_DESKTOP_SERVICE_NAME" ]]; then
        chroot_service_desktop_stop "$distro"
      else
        chroot_service_stop "$distro" "$name"
      fi
      chroot_service_print_ssh_connect_help "$distro" "$name" 0
      ;;
    restart)
      local name="${1:-}"
      [[ -n "$name" ]] || chroot_die "service restart requires <name>"
      chroot_require_service_name "$name"
      if [[ "${name,,}" == "$CHROOT_SERVICE_DESKTOP_SERVICE_NAME" ]]; then
        chroot_service_desktop_restart "$distro"
      elif chroot_service_is_pcbridge "$name"; then
        local pcbridge_mode_line pcbridge_mode pcbridge_action pcbridge_prefix
        pcbridge_mode_line="$(chroot_service_pcbridge_select_start_mode "$distro")"
        IFS=$'\t' read -r pcbridge_mode pcbridge_action <<<"$pcbridge_mode_line"
        [[ -n "$pcbridge_mode" ]] || pcbridge_mode="normal"
        pcbridge_prefix=""
        if [[ "$pcbridge_mode" == "normal" ]]; then
          if ! chroot_service_pcbridge_has_paired_keys "$distro"; then
            chroot_die "pcbridge option [s] requires an existing paired PC key in /etc/aurora-pcbridge/authorized_keys for $distro. Choose [f] first-run setup from $distro service restart pcbridge to pair a PC first."
          fi
        else
          pcbridge_prefix="AURORA_PCBRIDGE_PAIRING=1 AURORA_PCBRIDGE_ACTION=$pcbridge_action"
        fi
        chroot_log_run_internal_command service service.stop "$distro" "$distro" service stop "$name" -- chroot_service_stop "$distro" "$name"
        chroot_service_builtin_install_assets "$distro" "pcbridge"
        chroot_log_run_internal_command service service.start "$distro" "$distro" service start "$name" -- chroot_service_start "$distro" "$name" "$pcbridge_prefix"
        chroot_service_pcbridge_print_after_start "$distro" "$pcbridge_mode" "$pcbridge_action"
      else
        chroot_log_run_internal_command service service.stop "$distro" "$distro" service stop "$name" -- chroot_service_stop "$distro" "$name"
        chroot_log_run_internal_command service service.start "$distro" "$distro" service start "$name" -- chroot_service_start "$distro" "$name"
        chroot_service_print_ssh_connect_help "$distro" "$name" 1
      fi
      ;;
    *)
      chroot_die "unknown service action: $action (expected: list|status|on|start|off|stop|restart|add|install|remove|rm)"
      ;;
  esac
}
