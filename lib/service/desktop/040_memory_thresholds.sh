chroot_service_desktop_memory_info_tsv() {
  local total_kb=0 available_kb=0 line key value
  while IFS= read -r line; do
    key="${line%%:*}"
    value="${line#*:}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%% *}"
    case "$key" in
      MemTotal) total_kb="${value:-0}" ;;
      MemAvailable) available_kb="${value:-0}" ;;
    esac
  done < /proc/meminfo

  printf '%s\t%s\t%s\t%s\n' \
    "$total_kb" "$(( total_kb / 1024 ))" \
    "$available_kb" "$(( available_kb / 1024 ))"
}

chroot_service_desktop_profile_thresholds_tsv() {
  case "${1:-}" in
    lxqt)
      printf '2048\t800\t3072\t1400\n'
      ;;
    xfce)
      printf '4096\t1600\t6144\t2800\n'
      ;;
    *)
      return 1
      ;;
  esac
}

chroot_service_desktop_profile_is_blocked() {
  local profile_id="$1"
  local total_mb="$2"
  local available_mb="$3"
  local min_total_mb min_available_mb rec_total_mb rec_available_mb

  IFS=$'\t' read -r min_total_mb min_available_mb rec_total_mb rec_available_mb <<<"$(chroot_service_desktop_profile_thresholds_tsv "$profile_id")"
  if (( total_mb < min_total_mb || available_mb < min_available_mb )); then
    return 0
  fi
  return 1
}

chroot_service_desktop_profile_meets_recommended() {
  local profile_id="$1"
  local total_mb="$2"
  local available_mb="$3"
  local min_total_mb min_available_mb rec_total_mb rec_available_mb

  IFS=$'\t' read -r min_total_mb min_available_mb rec_total_mb rec_available_mb <<<"$(chroot_service_desktop_profile_thresholds_tsv "$profile_id")"
  if (( total_mb >= rec_total_mb && available_mb >= rec_available_mb )); then
    return 0
  fi
  return 1
}

chroot_service_desktop_profile_block_reason() {
  local profile_id="$1"
  local total_mb="$2"
  local available_mb="$3"
  local min_total_mb min_available_mb rec_total_mb rec_available_mb
  local profile_name total_low=0 available_low=0

  profile_name="$(chroot_service_desktop_profile_name "$profile_id")"
  IFS=$'\t' read -r min_total_mb min_available_mb rec_total_mb rec_available_mb <<<"$(chroot_service_desktop_profile_thresholds_tsv "$profile_id")"

  (( total_mb < min_total_mb )) && total_low=1
  (( available_mb < min_available_mb )) && available_low=1

  if (( total_low == 1 && available_low == 1 )); then
    printf 'Blocked: total RAM and available RAM are below the required thresholds for %s.\n' "$profile_name"
    return 0
  fi
  if (( total_low == 1 )); then
    printf 'Blocked: total RAM is below the required threshold for %s.\n' "$profile_name"
    return 0
  fi
  printf 'Blocked: available RAM is below the required threshold for %s.\n' "$profile_name"
}

chroot_service_desktop_recommended_profile_id() {
  local can_lxqt="$1"
  local can_xfce="$2"
  local recommended_lxqt="$3"
  local recommended_xfce="$4"

  if [[ "$can_lxqt" != "true" && "$can_xfce" != "true" ]]; then
    return 1
  fi
  if [[ "$can_lxqt" == "true" && "$can_xfce" != "true" ]]; then
    printf 'lxqt\n'
    return 0
  fi
  if [[ "$can_lxqt" != "true" && "$can_xfce" == "true" ]]; then
    printf 'xfce\n'
    return 0
  fi

  if [[ "$recommended_xfce" == "true" && "$recommended_lxqt" == "true" ]]; then
    printf 'xfce\n'
    return 0
  fi
  if [[ "$recommended_xfce" == "true" ]]; then
    printf 'xfce\n'
    return 0
  fi
  if [[ "$recommended_lxqt" == "true" ]]; then
    printf 'lxqt\n'
    return 0
  fi

  printf 'lxqt\n'
}
