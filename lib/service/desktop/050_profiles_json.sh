chroot_service_desktop_requirements_tsv() {
  local x11_enabled="false"
  local x11_requirement_met="false"
  local termux_x11_binary_found="false"
  local termux_x11_socket_dir_found="false"
  local all_requirements_met="false"

  if chroot_x11_enabled; then
    x11_enabled="true"
    x11_requirement_met="true"
  fi
  if chroot_x11_bin_path >/dev/null 2>&1; then
    termux_x11_binary_found="true"
  fi
  if [[ -d "$(chroot_x11_socket_dir)" ]]; then
    termux_x11_socket_dir_found="true"
  fi

  if [[ "$x11_requirement_met" == "true" && "$termux_x11_binary_found" == "true" ]]; then
    all_requirements_met="true"
  fi

  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$x11_enabled" \
    "$x11_requirement_met" \
    "$termux_x11_binary_found" \
    "$termux_x11_socket_dir_found" \
    "$all_requirements_met"
}

chroot_service_desktop_requirements_reason() {
  local x11_enabled="$1"
  local termux_x11_binary_found="$2"

  if [[ "$x11_enabled" != "true" ]]; then
    printf 'Unavailable: desktop requires settings x11=true.\n'
    return 0
  fi
  if [[ "$termux_x11_binary_found" != "true" ]]; then
    printf 'Unavailable: termux-x11 binary was not found on host.\n'
    return 0
  fi
  printf 'Unavailable: desktop requirements are not met.\n'
}

chroot_service_desktop_status_tsv() {
  local distro="$1"
  local desktop_installed="false"
  local installed_profile_id=""
  local service_defined="false"
  local service_running="false"
  local desktop_incomplete="false"
  local last_error=""
  local installed_flag incomplete_flag

  installed_flag="$(chroot_service_desktop_config_get "$distro" "installed" 2>/dev/null || true)"
  installed_profile_id="$(chroot_service_desktop_config_get "$distro" "profile_id" 2>/dev/null || true)"
  incomplete_flag="$(chroot_service_desktop_config_get "$distro" "incomplete" 2>/dev/null || true)"
  last_error="$(chroot_service_desktop_config_get "$distro" "last_error" 2>/dev/null || true)"
  if [[ "$installed_flag" == "true" ]]; then
    desktop_installed="true"
  fi
  if [[ "$incomplete_flag" == "true" ]]; then
    desktop_incomplete="true"
  fi
  if [[ -f "$(chroot_service_def_file "$distro" "$CHROOT_SERVICE_DESKTOP_SERVICE_NAME")" ]]; then
    service_defined="true"
  fi
  if chroot_service_get_pid "$distro" "$CHROOT_SERVICE_DESKTOP_SERVICE_NAME" >/dev/null 2>&1; then
    service_running="true"
  fi

  last_error="${last_error//$'\t'/ }"
  last_error="${last_error//$'\r'/ }"
  last_error="${last_error//$'\n'/ }"

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$desktop_installed" \
    "$installed_profile_id" \
    "$service_defined" \
    "$service_running" \
    "$desktop_incomplete" \
    "$last_error"
}

chroot_service_desktop_profile_rows_tsv() {
  local distro="$1"
  local family total_kb total_mb available_kb available_mb
  local x11_enabled x11_requirement_met termux_x11_binary_found termux_x11_socket_dir_found all_requirements_met
  local lxqt_supported="false" xfce_supported="false"
  local lxqt_blocked="false" xfce_blocked="false"
  local lxqt_can_install="false" xfce_can_install="false"
  local lxqt_meets_recommended="false" xfce_meets_recommended="false"
  local recommended_profile=""
  local lxqt_min_total lxqt_min_available lxqt_rec_total lxqt_rec_available
  local xfce_min_total xfce_min_available xfce_rec_total xfce_rec_available
  local installable_count=0
  local requirements_reason lxqt_reason xfce_reason

  family="$(chroot_service_desktop_detect_distro_family "$distro")"
  IFS=$'\t' read -r total_kb total_mb available_kb available_mb <<<"$(chroot_service_desktop_memory_info_tsv)"
  IFS=$'\t' read -r x11_enabled x11_requirement_met termux_x11_binary_found termux_x11_socket_dir_found all_requirements_met <<<"$(chroot_service_desktop_requirements_tsv)"
  IFS=$'\t' read -r lxqt_min_total lxqt_min_available lxqt_rec_total lxqt_rec_available <<<"$(chroot_service_desktop_profile_thresholds_tsv lxqt)"
  IFS=$'\t' read -r xfce_min_total xfce_min_available xfce_rec_total xfce_rec_available <<<"$(chroot_service_desktop_profile_thresholds_tsv xfce)"

  case "$family" in
    ubuntu|arch)
      lxqt_supported="true"
      xfce_supported="true"
      ;;
  esac

  if chroot_service_desktop_profile_is_blocked lxqt "$total_mb" "$available_mb"; then
    lxqt_blocked="true"
  fi
  if chroot_service_desktop_profile_is_blocked xfce "$total_mb" "$available_mb"; then
    xfce_blocked="true"
  fi

  if [[ "$lxqt_supported" == "true" && "$all_requirements_met" == "true" && "$lxqt_blocked" != "true" ]]; then
    lxqt_can_install="true"
    installable_count=$((installable_count + 1))
    if chroot_service_desktop_profile_meets_recommended lxqt "$total_mb" "$available_mb"; then
      lxqt_meets_recommended="true"
    fi
  fi
  if [[ "$xfce_supported" == "true" && "$all_requirements_met" == "true" && "$xfce_blocked" != "true" ]]; then
    xfce_can_install="true"
    installable_count=$((installable_count + 1))
    if chroot_service_desktop_profile_meets_recommended xfce "$total_mb" "$available_mb"; then
      xfce_meets_recommended="true"
    fi
  fi

  recommended_profile="$(chroot_service_desktop_recommended_profile_id "$lxqt_can_install" "$xfce_can_install" "$lxqt_meets_recommended" "$xfce_meets_recommended" || true)"
  requirements_reason="$(chroot_service_desktop_requirements_reason "$x11_enabled" "$termux_x11_binary_found")"

  if [[ "$lxqt_supported" != "true" ]]; then
    lxqt_reason="Unsupported distro family: $family."
  elif [[ "$all_requirements_met" != "true" ]]; then
    lxqt_reason="$requirements_reason"
  elif [[ "$lxqt_blocked" == "true" ]]; then
    lxqt_reason="$(chroot_service_desktop_profile_block_reason lxqt "$total_mb" "$available_mb")"
  elif [[ "$recommended_profile" == "lxqt" ]]; then
    if [[ "$lxqt_meets_recommended" == "true" ]]; then
      lxqt_reason="Recommended: current RAM comfortably fits LXQt."
    elif (( installable_count == 1 )); then
      lxqt_reason="Recommended: LXQt is the only installable profile on current device RAM."
    else
      lxqt_reason="Recommended: LXQt is the safer profile for current device RAM."
    fi
  else
    lxqt_reason="Allowed, but $(chroot_service_desktop_profile_name "$recommended_profile") is recommended on current device RAM."
  fi

  if [[ "$xfce_supported" != "true" ]]; then
    xfce_reason="Unsupported distro family: $family."
  elif [[ "$all_requirements_met" != "true" ]]; then
    xfce_reason="$requirements_reason"
  elif [[ "$xfce_blocked" == "true" ]]; then
    xfce_reason="$(chroot_service_desktop_profile_block_reason xfce "$total_mb" "$available_mb")"
  elif [[ "$recommended_profile" == "xfce" ]]; then
    if [[ "$xfce_meets_recommended" == "true" ]]; then
      xfce_reason="Recommended: current RAM comfortably fits XFCE."
    elif (( installable_count == 1 )); then
      xfce_reason="Recommended: XFCE is the only installable profile on current device RAM."
    else
      xfce_reason="Recommended: XFCE is the best fit for current device RAM."
    fi
  else
    xfce_reason="Allowed, but $(chroot_service_desktop_profile_name "$recommended_profile") is recommended on current device RAM."
  fi

  printf 'lxqt\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(chroot_service_desktop_profile_name lxqt)" \
    "$lxqt_supported" \
    "$lxqt_can_install" \
    "$([[ "$recommended_profile" == "lxqt" ]] && printf 'true' || printf 'false')" \
    "$lxqt_blocked" \
    "$lxqt_min_total" \
    "$lxqt_min_available" \
    "$lxqt_rec_total" \
    "$lxqt_rec_available" \
    "$lxqt_reason"
  printf 'xfce\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(chroot_service_desktop_profile_name xfce)" \
    "$xfce_supported" \
    "$xfce_can_install" \
    "$([[ "$recommended_profile" == "xfce" ]] && printf 'true' || printf 'false')" \
    "$xfce_blocked" \
    "$xfce_min_total" \
    "$xfce_min_available" \
    "$xfce_rec_total" \
    "$xfce_rec_available" \
    "$xfce_reason"
}

chroot_service_desktop_profile_row_tsv() {
  local distro="$1"
  local profile_id="$2"
  local line row_id
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    row_id="${line%%$'\t'*}"
    if [[ "$row_id" == "$profile_id" ]]; then
      printf '%s\n' "$line"
      return 0
    fi
  done < <(chroot_service_desktop_profile_rows_tsv "$distro")
  return 1
}

chroot_service_desktop_profiles_json() {
  local distro="$1"
  local family total_kb total_mb available_kb available_mb
  local x11_enabled x11_requirement_met termux_x11_binary_found termux_x11_socket_dir_found all_requirements_met
  local desktop_installed installed_profile_id service_defined service_running desktop_incomplete last_error
  local rows_file

  family="$(chroot_service_desktop_detect_distro_family "$distro")"
  IFS=$'\t' read -r total_kb total_mb available_kb available_mb <<<"$(chroot_service_desktop_memory_info_tsv)"
  IFS=$'\t' read -r x11_enabled x11_requirement_met termux_x11_binary_found termux_x11_socket_dir_found all_requirements_met <<<"$(chroot_service_desktop_requirements_tsv)"
  IFS=$'\t' read -r desktop_installed installed_profile_id service_defined service_running desktop_incomplete last_error <<<"$(chroot_service_desktop_status_tsv "$distro")"

  rows_file="$CHROOT_TMP_DIR/desktop-profiles.$$.tsv"
  chroot_service_desktop_profile_rows_tsv "$distro" >"$rows_file"

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - \
    "$distro" "$family" \
    "$desktop_installed" "$installed_profile_id" "$service_defined" "$service_running" "$desktop_incomplete" "$last_error" \
    "$total_kb" "$total_mb" "$available_kb" "$available_mb" \
    "$x11_enabled" "$x11_requirement_met" "$termux_x11_binary_found" "$termux_x11_socket_dir_found" "$all_requirements_met" \
    "$rows_file" <<'PY'
import json
import sys

(
    distro,
    family,
    desktop_installed,
    installed_profile_id,
    service_defined,
    service_running,
    desktop_incomplete,
    last_error,
    total_kb,
    total_mb,
    available_kb,
    available_mb,
    x11_enabled,
    x11_requirement_met,
    termux_x11_binary_found,
    termux_x11_socket_dir_found,
    all_requirements_met,
    rows_file,
) = sys.argv[1:]


def as_bool(value: str) -> bool:
    return value == "true"


profiles = []
with open(rows_file, "r", encoding="utf-8") as fh:
    for raw_line in fh:
        line = raw_line.rstrip("\n")
        if not line:
            continue
        parts = line.split("\t")
        if len(parts) != 11:
            continue
        (
            profile_id,
            name,
            supported,
            can_install,
            recommended,
            blocked,
            minimum_total_mb,
            minimum_available_mb,
            recommended_total_mb,
            recommended_available_mb,
            reason,
        ) = parts
        profiles.append(
            {
                "id": profile_id,
                "name": name,
                "supported": as_bool(supported),
                "can_install": as_bool(can_install),
                "recommended": as_bool(recommended),
                "blocked": as_bool(blocked),
                "minimum_total_mb": int(minimum_total_mb),
                "minimum_available_mb": int(minimum_available_mb),
                "recommended_total_mb": int(recommended_total_mb),
                "recommended_available_mb": int(recommended_available_mb),
                "reason": reason,
            }
        )

payload = {
    "distro": distro,
    "distro_family": family,
    "service": "desktop",
    "query": "install-profiles",
    "status": {
        "desktop_installed": as_bool(desktop_installed),
        "installed_profile_id": installed_profile_id,
        "service_defined": as_bool(service_defined),
        "service_running": as_bool(service_running),
        "incomplete": as_bool(desktop_incomplete),
        "last_error": last_error,
    },
    "memory": {
        "source": "/proc/meminfo",
        "total_kb": int(total_kb),
        "total_mb": int(total_mb),
        "available_kb": int(available_kb),
        "available_mb": int(available_mb),
    },
    "requirements": {
        "x11_required": True,
        "x11_enabled": as_bool(x11_enabled),
        "x11_requirement_met": as_bool(x11_requirement_met),
        "termux_x11_binary_found": as_bool(termux_x11_binary_found),
        "termux_x11_socket_dir_found": as_bool(termux_x11_socket_dir_found),
        "termux_home_bind_required": False,
        "android_storage_bind_required": False,
        "data_bind_required": False,
        "android_full_bind_required": False,
        "all_requirements_met": as_bool(all_requirements_met),
    },
    "profiles": profiles,
}

print(json.dumps(payload, indent=2))
PY

  rm -f -- "$rows_file"
}
