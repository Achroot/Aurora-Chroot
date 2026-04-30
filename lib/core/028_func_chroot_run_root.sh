chroot_run_root() {
  if [[ "$(id -u)" == "0" ]]; then
    "$@"
    return $?
  fi

  local qcmd
  qcmd="$(chroot_quote_cmd "$@")"
  chroot_run_root_cmd "$qcmd"
}

