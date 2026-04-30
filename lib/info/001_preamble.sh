CHROOT_INFO_SCHEMA_VERSION=1

chroot_info_section_ids() {
  cat <<'SECTIONS'
overview
device
resources
storage
distro
network
aurora
hint
SECTIONS
}

chroot_info_slow_section_ids() {
  cat <<'SECTIONS'
storage
distro
SECTIONS
}

chroot_info_normalize_section_id() {
  local wanted="${1:-}"
  local normalized="${wanted,,}"
  [[ -n "$normalized" ]] || return 1

  case "$normalized" in
    overview|device|resources|storage|network|aurora)
      printf '%s\n' "$normalized"
      return 0
      ;;
    distro|distros)
      printf 'distro\n'
      return 0
      ;;
    hint|hints)
      printf 'hint\n'
      return 0
      ;;
  esac

  return 1
}

chroot_info_has_section_id() {
  chroot_info_normalize_section_id "$1" >/dev/null 2>&1
}

chroot_info_section_usage_ids() {
  local out=""
  local section_id
  while IFS= read -r section_id; do
    [[ -n "$section_id" ]] || continue
    if [[ -n "$out" ]]; then
      out+="|"
    fi
    out+="$section_id"
  done < <(chroot_info_section_ids)
  printf '%s\n' "$out"
}

chroot_info_render_width() {
  local cols="${COLUMNS:-}"
  if [[ ! "$cols" =~ ^[0-9]+$ ]] || (( cols <= 0 )); then
    if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
      cols="$(tput cols 2>/dev/null || true)"
    fi
  fi
  if [[ ! "$cols" =~ ^[0-9]+$ ]] || (( cols <= 0 )); then
    cols=96
  fi
  if (( cols > 8 )); then
    cols=$((cols - 6))
  fi
  if (( cols < 54 )); then
    cols=54
  elif (( cols > 96 )); then
    cols=96
  fi
  printf '%s\n' "$cols"
}
