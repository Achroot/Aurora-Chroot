chroot_cmd_service() {
  local distro=""
  if [[ $# -gt 0 && "$1" != --* && "$1" != "list" && "$1" != "status" && "$1" != "start" && "$1" != "stop" && "$1" != "restart" && "$1" != "add" && "$1" != "remove" && "$1" != "install" ]]; then
    distro="$1"
    shift || true
  fi
  
  if [[ -z "$distro" ]]; then
    chroot_die "usage: bash path/to/chroot service <distro> <action> [args] (actions: list|status|start|stop|restart|add|remove|install)"
  fi
  
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
      local name="$1"
      shift || chroot_die "service add requires <name> <command>"
      local cmd="$*"
      [[ -n "$name" && -n "$cmd" ]] || chroot_die "service add requires <name> <command>"
      chroot_require_service_name "$name"
      chroot_service_add_def "$distro" "$name" "$cmd"
      ;;
    install)
      local builtin_id="${1:-}"
      if [[ "$builtin_id" == "--json" ]]; then
        chroot_service_builtin_catalog_json
        return 0
      fi
      if [[ "$builtin_id" == "--list" ]]; then
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
      fi
      chroot_service_install_builtin "$distro" "$builtin_id"
      ;;
    remove)
      local name="${1:-}"
      if [[ -z "$name" ]]; then
        if [[ ! -t 0 ]]; then
          chroot_die "service remove requires <name> in non-interactive mode"
        fi
        local pick_rc=0
        name="$(chroot_service_select_def "$distro" "Select service to remove")" || pick_rc=$?
        case "$pick_rc" in
          0) ;;
          2) chroot_die "no services defined for $distro" ;;
          *) chroot_die "service remove aborted" ;;
        esac
      fi
      chroot_require_service_name "$name"
      local def_file
      def_file="$(chroot_service_def_file "$distro" "$name")"
      chroot_info "Removing service '$name' from $distro"
      chroot_info "Will stop tracked service session: svc-$name (if running)"
      chroot_info "Will delete definition file: $def_file"
      chroot_service_stop "$distro" "$name"
      chroot_service_remove_def "$distro" "$name"
      ;;
    start)
      local name="$1"
      [[ -n "$name" ]] || chroot_die "service start requires <name>"
      chroot_require_service_name "$name"
      if chroot_service_is_pcbridge "$name"; then
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
            chroot_die "pcbridge option [s] requires an existing paired PC key in /etc/aurora-pcbridge/authorized_keys for $distro. Run service start/restart pcbridge and choose [f] first-run setup to pair a PC first."
          fi
        else
          pcbridge_prefix="AURORA_PCBRIDGE_PAIRING=1"
        fi
        chroot_service_start "$distro" "$name" "$pcbridge_prefix"
        chroot_service_pcbridge_print_after_start "$distro" "$pcbridge_mode" "$pcbridge_action"
      else
        chroot_service_start "$distro" "$name"
        chroot_service_print_ssh_connect_help "$distro" "$name" 1
      fi
      ;;
    stop)
      local name="$1"
      [[ -n "$name" ]] || chroot_die "service stop requires <name>"
      chroot_require_service_name "$name"
      chroot_service_stop "$distro" "$name"
      chroot_service_print_ssh_connect_help "$distro" "$name" 0
      ;;
    restart)
      local name="$1"
      [[ -n "$name" ]] || chroot_die "service restart requires <name>"
      chroot_require_service_name "$name"
      if chroot_service_is_pcbridge "$name"; then
        local pcbridge_mode_line pcbridge_mode pcbridge_action pcbridge_prefix
        pcbridge_mode_line="$(chroot_service_pcbridge_select_start_mode "$distro")"
        IFS=$'\t' read -r pcbridge_mode pcbridge_action <<<"$pcbridge_mode_line"
        [[ -n "$pcbridge_mode" ]] || pcbridge_mode="normal"
        pcbridge_prefix=""
        if [[ "$pcbridge_mode" == "normal" ]]; then
          if ! chroot_service_pcbridge_has_paired_keys "$distro"; then
            chroot_die "pcbridge option [s] requires an existing paired PC key in /etc/aurora-pcbridge/authorized_keys for $distro. Choose [f] first-run setup to pair a PC first."
          fi
        else
          pcbridge_prefix="AURORA_PCBRIDGE_PAIRING=1"
        fi
        chroot_service_stop "$distro" "$name"
        chroot_service_start "$distro" "$name" "$pcbridge_prefix"
        chroot_service_pcbridge_print_after_start "$distro" "$pcbridge_mode" "$pcbridge_action"
      else
        chroot_service_stop "$distro" "$name"
        chroot_service_start "$distro" "$name"
        chroot_service_print_ssh_connect_help "$distro" "$name" 1
      fi
      ;;
    *)
      chroot_die "unknown service action: $action"
      ;;
  esac
}
