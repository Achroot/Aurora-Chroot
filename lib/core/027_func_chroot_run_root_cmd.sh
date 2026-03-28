chroot_run_root_cmd() {
  local cmd="$1"
  local host_sh
  local -a launcher_cmd launcher_subcmd_parts

  host_sh="${CHROOT_HOST_SH:-}"
  if [[ -z "$host_sh" ]]; then
    host_sh="$(command -v sh 2>/dev/null || true)"
  fi
  [[ -n "$host_sh" ]] || host_sh="sh"

  if [[ "$(id -u)" == "0" ]]; then
    "$host_sh" -c "$cmd"
    return $?
  fi

  chroot_resolve_root_launcher || chroot_die "root backend unavailable; ${CHROOT_ROOT_DIAGNOSTICS:-no diagnostics}"

  launcher_cmd=("$CHROOT_ROOT_LAUNCHER_BIN")
  if [[ -n "${CHROOT_ROOT_LAUNCHER_SUBCMD:-}" ]]; then
    read -r -a launcher_subcmd_parts <<<"$CHROOT_ROOT_LAUNCHER_SUBCMD"
    if (( ${#launcher_subcmd_parts[@]} > 0 )); then
      launcher_cmd+=("${launcher_subcmd_parts[@]}")
    fi
  fi

  if "${launcher_cmd[@]}" -c "$cmd"; then
    return 0
  fi
  "${launcher_cmd[@]}" "$host_sh" -c "$cmd"
}
