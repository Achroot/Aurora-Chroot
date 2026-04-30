chroot_service_desktop_selection_summary() {
  local distro="$1"
  local row status name supported can_install recommended blocked min_total min_available rec_total rec_available reason
  local lxqt_status="" xfce_status=""

  while IFS=$'\t' read -r row name supported can_install recommended blocked min_total min_available rec_total rec_available reason; do
    [[ -n "$row" ]] || continue
    if [[ "$recommended" == "true" ]]; then
      status="recommended"
    elif [[ "$blocked" == "true" ]]; then
      status="blocked"
    elif [[ "$can_install" == "true" ]]; then
      status="allowed"
    else
      status="unavailable"
    fi
    case "$row" in
      lxqt) lxqt_status="$status" ;;
      xfce) xfce_status="$status" ;;
    esac
  done < <(chroot_service_desktop_profile_rows_tsv "$distro")

  printf 'Desktop recommendation: LXQt %s, XFCE %s\n' "${lxqt_status:-unavailable}" "${xfce_status:-unavailable}"
}

chroot_service_desktop_prompt_profile() {
  local distro="$1"
  local total_kb total_mb available_kb available_mb
  local profile_id profile_name supported can_install recommended blocked min_total min_available rec_total rec_available reason
  local idx=1 pick line
  local -a profiles=()

  IFS=$'\t' read -r total_kb total_mb available_kb available_mb <<<"$(chroot_service_desktop_memory_info_tsv)"

  printf 'Host RAM: total=%sMB available=%sMB\n' "$total_mb" "$available_mb" >&2
  chroot_service_desktop_selection_summary "$distro" >&2
  printf '\nDesktop profiles:\n' >&2

  while IFS=$'\t' read -r profile_id profile_name supported can_install recommended blocked min_total min_available rec_total rec_available reason; do
    [[ -n "$profile_id" ]] || continue
    profiles+=("$profile_id")
    line="$profile_name"
    if [[ "$recommended" == "true" ]]; then
      line="$line [recommended]"
    elif [[ "$blocked" == "true" ]]; then
      line="$line [blocked]"
    elif [[ "$can_install" == "true" ]]; then
      line="$line [allowed]"
    else
      line="$line [unavailable]"
    fi
    printf '  %2d) %s\n' "$idx" "$line" >&2
    printf '      %s\n' "$reason" >&2
    idx=$((idx + 1))
  done < <(chroot_service_desktop_profile_rows_tsv "$distro")

  while true; do
    printf 'Select desktop profile (1-%s, q=cancel): ' "${#profiles[@]}" >&2
    read -r pick
    case "$pick" in
      q|Q|'')
        return 1
        ;;
      *)
        if [[ "$pick" =~ ^[0-9]+$ ]] && (( pick >= 1 && pick <= ${#profiles[@]} )); then
          printf '%s\n' "${profiles[$((pick - 1))]}"
          return 0
        fi
        ;;
    esac
    printf 'Invalid selection.\n' >&2
  done
}

chroot_service_desktop_write_profile_assets() {
  local distro="$1"
  local distro_family="$2"
  local profile_id="$3"
  local profile_name profile_exec session_slug
  local rootfs_cfg_dir launcher_path profile_env_path profile_json_path
  local tmp_launcher tmp_env tmp_json

  profile_name="$(chroot_service_desktop_profile_name "$profile_id")"
  profile_exec="$(chroot_service_desktop_profile_exec_cmd "$profile_id")"
  session_slug="$(chroot_service_desktop_session_slug "$profile_id")"
  rootfs_cfg_dir="$(chroot_service_desktop_rootfs_config_dir "$distro")"
  launcher_path="$(chroot_service_desktop_rootfs_launcher_file "$distro")"
  profile_env_path="$(chroot_service_desktop_rootfs_profile_env_file "$distro")"
  profile_json_path="$(chroot_service_desktop_rootfs_profile_json_file "$distro")"

  tmp_launcher="$CHROOT_TMP_DIR/aurora-desktop-launch.$$"
  tmp_env="$CHROOT_TMP_DIR/aurora-desktop-profile.$$"
  tmp_json="$CHROOT_TMP_DIR/aurora-desktop-profile.$$.json"

  chroot_service_desktop_launch_script_content >"$tmp_launcher"
  cat >"$tmp_env" <<EOF_ENV
AURORA_DESKTOP_PROFILE_ID="$profile_id"
AURORA_DESKTOP_PROFILE_NAME="$profile_name"
AURORA_DESKTOP_EXEC="$profile_exec"
AURORA_DESKTOP_SESSION="$session_slug"
AURORA_DESKTOP_FAMILY="$distro_family"
DESKTOP_SESSION="$session_slug"
XDG_SESSION_DESKTOP="$session_slug"
XDG_CURRENT_DESKTOP="$profile_name"
EOF_ENV

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$tmp_json" "$profile_id" "$profile_name" "$distro_family" "$profile_exec" <<'PY'
import json
import sys

target, profile_id, profile_name, family, command = sys.argv[1:]
doc = {
    "profile_id": profile_id,
    "profile_name": profile_name,
    "distro_family": family,
    "service_name": "desktop",
    "command": command,
}
with open(target, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2, sort_keys=True)
PY

  chroot_run_root mkdir -p "$rootfs_cfg_dir" "$(dirname "$launcher_path")" || chroot_die "failed to prepare desktop asset directories for $distro"
  chroot_run_root install -m 0755 "$tmp_launcher" "$launcher_path" || chroot_die "failed to install desktop launcher into $distro"
  chroot_run_root install -m 0644 "$tmp_env" "$profile_env_path" || chroot_die "failed to install desktop profile env into $distro"
  chroot_run_root install -m 0644 "$tmp_json" "$profile_json_path" || chroot_die "failed to install desktop profile json into $distro"

  rm -f -- "$tmp_launcher" "$tmp_env" "$tmp_json"
}

chroot_service_desktop_refresh_assets_from_config() {
  local distro="$1"
  local profile_id distro_family

  profile_id="$(chroot_service_desktop_config_get "$distro" "profile_id" 2>/dev/null || true)"
  distro_family="$(chroot_service_desktop_config_get "$distro" "distro_family" 2>/dev/null || true)"
  [[ -n "$profile_id" && -n "$distro_family" ]] || return 1

  chroot_service_desktop_profile_is_valid "$profile_id" || return 1
  chroot_service_desktop_write_profile_assets "$distro" "$distro_family" "$profile_id"
}

chroot_service_desktop_prepare_reinstall() {
  local distro="$1"
  local running_pid=""

  running_pid="$(chroot_service_get_pid "$distro" "$CHROOT_SERVICE_DESKTOP_SERVICE_NAME" 2>/dev/null || true)"
  if [[ -n "$running_pid" ]]; then
    chroot_info "Stopping running desktop service before reinstall/update..."
    chroot_service_desktop_stop "$distro"
  fi
}

chroot_service_desktop_install() {
  local distro="$1"
  local profile_id="${2:-}"
  local reinstall="${3:-0}"
  local distro_family row
  local profile_name supported can_install recommended blocked min_total min_available rec_total rec_available reason
  local total_kb total_mb available_kb available_mb
  local x11_enabled x11_requirement_met termux_x11_binary_found termux_x11_socket_dir_found all_requirements_met
  local existing_profile existing_installed install_started_at rootfs tmp_script chroot_script
  local install_rc=0

  if [[ -z "$profile_id" ]]; then
    if [[ ! -t 0 ]]; then
      chroot_die "service install desktop requires --profile <xfce|lxqt> in non-interactive mode"
    fi
    local pick_rc=0
    profile_id="$(chroot_service_desktop_prompt_profile "$distro")" || pick_rc=$?
    case "$pick_rc" in
      0) ;;
      *) chroot_die "desktop install aborted" ;;
    esac
  fi

  chroot_service_desktop_require_profile_id "$profile_id"
  profile_name="$(chroot_service_desktop_profile_name "$profile_id")"
  distro_family="$(chroot_service_desktop_detect_distro_family "$distro")"
  row="$(chroot_service_desktop_profile_row_tsv "$distro" "$profile_id")"
  [[ -n "$row" ]] || chroot_die "failed to evaluate desktop profile '$profile_id'"

  IFS=$'\t' read -r _ profile_name supported can_install recommended blocked min_total min_available rec_total rec_available reason <<<"$row"
  IFS=$'\t' read -r total_kb total_mb available_kb available_mb <<<"$(chroot_service_desktop_memory_info_tsv)"
  IFS=$'\t' read -r x11_enabled x11_requirement_met termux_x11_binary_found termux_x11_socket_dir_found all_requirements_met <<<"$(chroot_service_desktop_requirements_tsv)"

  chroot_info "Host RAM: total=${total_mb}MB available=${available_mb}MB"
  chroot_service_desktop_selection_summary "$distro"

  if [[ "$supported" != "true" ]]; then
    chroot_die "$reason"
  fi
  if [[ "$all_requirements_met" != "true" ]]; then
    chroot_die "$reason"
  fi
  if [[ "$can_install" != "true" ]]; then
    chroot_die "$reason"
  fi

  if [[ "$recommended" == "true" ]]; then
    chroot_info "$reason"
  else
    chroot_warn "$reason"
  fi

  existing_profile="$(chroot_service_desktop_config_get "$distro" "profile_id" 2>/dev/null || true)"
  existing_installed="$(chroot_service_desktop_config_get "$distro" "installed" 2>/dev/null || true)"
  if [[ -n "$existing_profile" && "$existing_profile" != "$profile_id" && "$existing_installed" == "true" && "$reinstall" != "1" ]]; then
    if [[ -t 0 ]]; then
      chroot_confirm_typed_y "Switch desktop profile from $existing_profile to $profile_id? Type y and press Enter to continue" || chroot_die "desktop reinstall aborted"
    else
      chroot_die "desktop is already installed with profile '$existing_profile'; rerun with --reinstall to switch to '$profile_id'"
    fi
  fi

  if [[ "$existing_installed" == "true" ]]; then
    chroot_service_desktop_prepare_reinstall "$distro"
  fi

  install_started_at="$(chroot_now_ts)"
  chroot_service_desktop_config_set_fields "$distro" \
    "profile_id" "$profile_id" \
    "profile_name" "$profile_name" \
    "distro_family" "$distro_family" \
    "installed" "false" \
    "incomplete" "true" \
    "display_backend" "termux-x11" \
    "x11_required" "true" \
    "installed_at" "$install_started_at" \
    "last_started_at" "" \
    "last_stopped_at" "" \
    "last_error" ""

  rootfs="$(chroot_distro_rootfs_dir "$distro")"
  chroot_log_run_internal_command core mount "$distro" mount "$distro" -- chroot_cmd_mount "$distro"

  tmp_script="$CHROOT_TMP_DIR/aurora-desktop-install.$$"
  chroot_script="$rootfs/tmp/aurora-desktop-install.sh"
  chroot_service_desktop_install_script_content >"$tmp_script"
  chroot_run_root install -m 0755 "$tmp_script" "$chroot_script" || {
    rm -f -- "$tmp_script"
    chroot_service_desktop_config_set_fields "$distro" "installed" "false" "incomplete" "true" "last_error" "failed to copy desktop installer into $distro"
    chroot_die "failed to copy desktop installer into $distro"
  }
  rm -f -- "$tmp_script"

  set +e
  chroot_run_chroot_env "$rootfs" \
    "HOME=/root" \
    "TERM=${TERM:-xterm-256color}" \
    "PATH=$(chroot_chroot_default_path)" \
    "LANG=${LANG:-C.UTF-8}" \
    -- /bin/bash /tmp/aurora-desktop-install.sh "$distro_family" "$profile_id"
  install_rc=$?
  set -e
  chroot_run_root rm -f -- "$chroot_script" 2>/dev/null || true
  if (( install_rc != 0 )); then
    chroot_service_desktop_config_set_fields "$distro" "installed" "false" "incomplete" "true" "last_error" "desktop package install failed for $profile_id (exit code: $install_rc)"
    chroot_die "desktop package install failed inside $distro (exit code: $install_rc)"
  fi

  chroot_service_desktop_write_profile_assets "$distro" "$distro_family" "$profile_id"

  chroot_service_add_def "$distro" "$CHROOT_SERVICE_DESKTOP_SERVICE_NAME" "$CHROOT_SERVICE_DESKTOP_COMMAND"
  chroot_service_desktop_config_set_fields "$distro" \
    "profile_id" "$profile_id" \
    "profile_name" "$profile_name" \
    "distro_family" "$distro_family" \
    "installed" "true" \
    "incomplete" "false" \
    "display_backend" "termux-x11" \
    "x11_required" "true" \
    "installed_at" "$install_started_at" \
    "last_error" ""

  chroot_info "Installed desktop profile '$profile_id' for $distro"
}
