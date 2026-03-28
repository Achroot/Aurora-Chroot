chroot_su_supports_interactive() {
  if [[ "$CHROOT_SU_HAS_INTERACTIVE" == "1" ]]; then
    [[ -n "$CHROOT_SU_INTERACTIVE_FLAG" ]] || CHROOT_SU_INTERACTIVE_FLAG="-i"
    return 0
  fi
  if [[ "$CHROOT_SU_HAS_INTERACTIVE" == "0" ]]; then
    return 1
  fi

  local launcher subcmd help_text flag
  local -a launcher_cmd launcher_subcmd_parts
  launcher="${CHROOT_ROOT_LAUNCHER_BIN:-}"
  subcmd="${CHROOT_ROOT_LAUNCHER_SUBCMD:-}"
  [[ -n "$launcher" ]] || return 1

  launcher_cmd=("$launcher")
  if [[ -n "$subcmd" ]]; then
    read -r -a launcher_subcmd_parts <<<"$subcmd"
    if (( ${#launcher_subcmd_parts[@]} > 0 )); then
      launcher_cmd+=("${launcher_subcmd_parts[@]}")
    fi
  fi

  help_text="$("${launcher_cmd[@]}" -h 2>&1 || true)"

  for flag in "-i" "-P" "--pty" "--interactive" "-t"; do
    if printf '%s\n' "$help_text" | grep -q -- "$flag"; then
      CHROOT_SU_HAS_INTERACTIVE="1"
      CHROOT_SU_INTERACTIVE_FLAG="$flag"
      return 0
    fi
  done

  for flag in "-i" "-P" "-t"; do
    if "${launcher_cmd[@]}" "$flag" -c "id -u >/dev/null 2>&1" >/dev/null 2>&1; then
      CHROOT_SU_HAS_INTERACTIVE="1"
      CHROOT_SU_INTERACTIVE_FLAG="$flag"
      return 0
    fi
  done

  CHROOT_SU_HAS_INTERACTIVE="0"
  CHROOT_SU_INTERACTIVE_FLAG=""
  return 1
}
