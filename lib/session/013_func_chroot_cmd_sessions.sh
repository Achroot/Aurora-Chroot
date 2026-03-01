chroot_cmd_sessions() {
  local distro=""
  if [[ $# -gt 0 && "$1" != --* && "$1" != "list" && "$1" != "status" && "$1" != "kill" && "$1" != "kill-all" ]]; then
    distro="$1"
    shift || true
  fi

  [[ -n "$distro" ]] || chroot_die "usage: bash path/to/chroot sessions <distro> [list|status|kill|kill-all] [args]"
  chroot_require_distro_arg "$distro"
  chroot_preflight_hard_fail
  [[ -d "$(chroot_distro_rootfs_dir "$distro")" ]] || chroot_die "distro not installed: $distro"

  local action="${1:-list}"
  if [[ $# -gt 0 ]]; then
    shift
  fi

  case "$action" in
    list|status)
      chroot_session_prune_stale "$distro" >/dev/null 2>&1 || true
      if [[ "${1:-}" == "--json" ]]; then
        chroot_session_list_json "$distro"
      else
        local count=0 sid pid mode started state cmd
        printf '%-28s %-8s %-8s %-16s %s\n' "Session ID" "PID" "Mode" "State" "Command"
        printf '%-28s %-8s %-8s %-16s %s\n' "----------" "---" "----" "-----" "-------"
        while IFS=$'\t' read -r sid pid mode started state cmd; do
          [[ -n "$sid" ]] || continue
          [[ -n "$pid" ]] || pid="-"
          [[ -n "$mode" ]] || mode="-"
          [[ -n "$state" ]] || state="-"
          [[ -n "$cmd" ]] || cmd="-"
          printf '%-28s %-8s %-8s %-16s %s\n' "$sid" "$pid" "$mode" "$state" "$cmd"
          count=$((count + 1))
        done < <(chroot_session_list_details_tsv "$distro")
        if (( count == 0 )); then
          chroot_info "No tracked sessions for $distro."
        fi
        # Keep SSH connection hints visible from sessions view for active SSH services.
        if declare -F chroot_service_print_ssh_connect_help_for_distro >/dev/null 2>&1; then
          chroot_service_print_ssh_connect_help_for_distro "$distro" 1
        fi
      fi
      ;;
    kill)
      local session_id="${1:-}"
      if [[ -z "$session_id" ]]; then
        if [[ ! -t 0 ]]; then
          chroot_die "sessions kill requires <session_id> in non-interactive mode"
        fi
        local pick_rc=0
        session_id="$(chroot_session_select_one "$distro" "Select session to kill")" || pick_rc=$?
        case "$pick_rc" in
          0) ;;
          2) chroot_die "no tracked sessions for $distro" ;;
          *) chroot_die "sessions kill aborted" ;;
        esac
      fi

      if [[ "$session_id" == "$(chroot_service_desktop_session_id)" ]] && chroot_service_desktop_session_is_tracked "$distro" "$session_id"; then
        chroot_service_desktop_stop "$distro"
        chroot_log_info sessions "kill-desktop-stop distro=$distro session=$session_id"
        return 0
      fi

      local kill_out kill_rc found targeted term_sent kill_sent still_alive
      kill_rc=0
      kill_out="$(chroot_session_kill_one "$distro" "$session_id" 3)" || kill_rc=$?
      IFS=$'\t' read -r found targeted term_sent kill_sent still_alive <<<"$kill_out"
      found="${found:-0}"
      targeted="${targeted:-0}"
      term_sent="${term_sent:-0}"
      kill_sent="${kill_sent:-0}"
      still_alive="${still_alive:-0}"

      if (( found == 0 || kill_rc == 2 )); then
        chroot_die "session not found: $session_id"
      fi
      if (( still_alive == 0 )); then
        chroot_log_info sessions "kill distro=$distro session=$session_id targeted=$targeted term=$term_sent kill=$kill_sent alive=0"
        chroot_info "Session '$session_id' removed from tracking (term=$term_sent kill=$kill_sent)."
      else
        chroot_log_warn sessions "kill-failed distro=$distro session=$session_id targeted=$targeted term=$term_sent kill=$kill_sent alive=1"
        chroot_warn "Session '$session_id' may still be active (term=$term_sent kill=$kill_sent)."
        return 1
      fi
      ;;
    kill-all)
      local grace=3
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --grace)
            shift
            [[ $# -gt 0 ]] || chroot_die "--grace needs value"
            grace="$1"
            ;;
          *)
            chroot_die "unknown sessions kill-all arg: $1"
            ;;
        esac
        shift
      done
      [[ "$grace" =~ ^[0-9]+$ ]] || chroot_die "--grace must be a non-negative integer"

      if chroot_service_desktop_session_is_tracked "$distro"; then
        chroot_info "Stopping desktop service before killing remaining sessions..."
        chroot_service_desktop_stop "$distro"
      fi

      local kill_out kill_rc targeted term_sent kill_sent remaining cleaned skipped_identity
      kill_rc=0
      kill_out="$(chroot_session_kill_all "$distro" "$grace")" || kill_rc=$?
      IFS=$'\t' read -r targeted term_sent kill_sent remaining cleaned skipped_identity <<<"$kill_out"
      targeted="${targeted:-0}"
      term_sent="${term_sent:-0}"
      kill_sent="${kill_sent:-0}"
      remaining="${remaining:-0}"
      cleaned="${cleaned:-0}"
      skipped_identity="${skipped_identity:-0}"

      chroot_log_info sessions "kill-all distro=$distro targeted=$targeted term=$term_sent kill=$kill_sent remaining=$remaining cleaned=$cleaned skipped_identity=$skipped_identity"
      chroot_info "Session cleanup for $distro: targeted=$targeted term=$term_sent kill=$kill_sent remaining=$remaining cleaned=$cleaned"
      if (( skipped_identity > 0 )); then
        chroot_warn "Skipped $skipped_identity session entries for $distro (missing identity metadata)."
      fi
      if (( kill_rc != 0 || remaining > 0 )); then
        chroot_warn "Some sessions are still active for $distro after kill-all."
        return 1
      fi
      ;;
    *)
      chroot_die "unknown sessions action: $action"
      ;;
  esac
}
