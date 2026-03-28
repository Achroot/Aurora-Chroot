chroot_host_user_uid() {
  local target="${CHROOT_TERMUX_PREFIX:-}"
  [[ -n "$target" && -e "$target" ]] || target="${CHROOT_TERMUX_HOME_DEFAULT:-${HOME:-}}"
  [[ -n "$target" && -e "$target" ]] || return 1
  stat -c '%u' "$target" 2>/dev/null
}

chroot_host_user_gid() {
  local target="${CHROOT_TERMUX_PREFIX:-}"
  [[ -n "$target" && -e "$target" ]] || target="${CHROOT_TERMUX_HOME_DEFAULT:-${HOME:-}}"
  [[ -n "$target" && -e "$target" ]] || return 1
  stat -c '%g' "$target" 2>/dev/null
}

chroot_host_user_home() {
  local target="${CHROOT_TERMUX_HOME_DEFAULT:-${HOME:-}}"
  [[ -n "$target" && -d "$target" ]] || target="${HOME:-}"
  [[ -n "$target" && -d "$target" ]] || return 1
  printf '%s\n' "$target"
}

chroot_run_host_user() {
  if [[ "$(id -u)" != "0" ]]; then
    "$@"
    return $?
  fi

  local uid gid qcmd
  uid="$(chroot_host_user_uid || true)"
  gid="$(chroot_host_user_gid || true)"
  [[ "$uid" =~ ^[0-9]+$ ]] || {
    "$@"
    return $?
  }
  qcmd="$(chroot_quote_cmd "$@")"

  if chroot_cmd_exists runuser; then
    runuser -u "#$uid" -- "$@" && return 0 || true
  fi
  if chroot_cmd_exists setpriv && [[ "$gid" =~ ^[0-9]+$ ]]; then
    setpriv --reuid "$uid" --regid "$gid" --clear-groups "$@" && return 0 || true
  fi
  if chroot_cmd_exists su; then
    su "$uid" -c "$qcmd" && return 0 || true
    su -c "$qcmd" "$uid" && return 0 || true
    if [[ "$gid" =~ ^[0-9]+$ ]]; then
      su "${uid}:${gid}" -c "$qcmd" && return 0 || true
    fi
  fi

  "$@"
}
