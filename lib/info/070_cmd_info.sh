chroot_cmd_info_refresh() {
  local payload
  payload="$(chroot_info_collect_json full)"
  chroot_log_info info "refresh"
  chroot_info "info-hub refreshed."
  chroot_info_render_human "$payload"
}

chroot_cmd_info() {
  local json=0
  local section=""
  local verb="${1:-}"
  verb="${verb,,}"

  chroot_info_collect_env_prepare

  if [[ "$verb" == "refresh" ]]; then
    shift || true
    [[ $# -eq 0 ]] || chroot_die "info refresh does not accept extra arguments"
    chroot_cmd_info_refresh
    return 0
  fi

  if [[ "$verb" == "section" ]]; then
    shift || true
    [[ -n "${1:-}" ]] || chroot_die "info section requires value"
    section="$(chroot_info_normalize_section_id "${1:-}" || true)"
    [[ -n "$section" ]] || chroot_die "unknown info section: ${1:-}"
    shift || true
    [[ $# -eq 0 ]] || chroot_die "info section does not accept extra arguments"
    local section_payload
    section_payload="$(chroot_info_collect_json section "$section")"
    chroot_info_render_human "$section_payload"
    return 0
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) json=1 ;;
      *)
        chroot_die "unknown info arg: $1"
        ;;
    esac
    shift || true
  done

  local payload
  payload="$(chroot_info_collect_json full)"
  if [[ "$json" == "1" ]]; then
    printf '%s\n' "$payload"
    return 0
  fi

  chroot_info_render_human "$payload"
}
