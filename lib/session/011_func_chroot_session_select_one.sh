chroot_session_select_one() {
  local distro="$1"
  local prompt="${2:-Select session to kill}"
  local -a rows=()
  local line sid pid mode started state cmd idx pick

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    rows+=("$line")
  done < <(chroot_session_list_details_tsv "$distro")

  if (( ${#rows[@]} == 0 )); then
    chroot_warn "No tracked sessions found for $distro."
    return 2
  fi

  printf '\nSessions in %s:\n' "$distro" >&2
  idx=1
  for line in "${rows[@]}"; do
    IFS=$'\t' read -r sid pid mode started state cmd <<<"$line"
    [[ -n "$sid" ]] || sid="-"
    [[ -n "$pid" ]] || pid="-"
    [[ -n "$mode" ]] || mode="-"
    [[ -n "$started" ]] || started="-"
    [[ -n "$state" ]] || state="-"
    [[ -n "$cmd" ]] || cmd="-"
    printf '  %2d) id=%-26s pid=%-8s mode=%-8s state=%-16s cmd=%s\n' "$idx" "$sid" "$pid" "$mode" "$state" "$cmd" >&2
    idx=$((idx + 1))
  done

  while true; do
    printf '%s (1-%s, q=cancel): ' "$prompt" "${#rows[@]}" >&2
    read -r pick
    case "$pick" in
      q|Q|'')
        return 1
        ;;
      *)
        if [[ "$pick" =~ ^[0-9]+$ ]] && (( pick >= 1 && pick <= ${#rows[@]} )); then
          IFS=$'\t' read -r sid _ <<<"${rows[$((pick - 1))]}"
          printf '%s\n' "$sid"
          return 0
        fi
        ;;
    esac
    printf 'Invalid selection.\n' >&2
  done
}

