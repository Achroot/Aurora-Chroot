chroot_runtime_rebuild_dir_as_user() {
  local d="$1"
  local mode="${2:-755}"
  local probe="$d/.write-test.$$"

  mkdir -p "$d" >/dev/null 2>&1 || true
  if touch "$probe" >/dev/null 2>&1; then
    rm -f -- "$probe" >/dev/null 2>&1 || true
    chmod "$mode" "$d" >/dev/null 2>&1 || true
    return 0
  fi

  # Never delete runtime directories as a "repair" step.
  # If label/permission state is bad, try conservative mode/ownership fixes only.
  chroot_run_root chmod "$mode" "$d" >/dev/null 2>&1 || true
  chroot_run_root chown "$(id -u):$(id -g)" "$d" >/dev/null 2>&1 || true

  if touch "$probe" >/dev/null 2>&1; then
    rm -f -- "$probe" >/dev/null 2>&1 || true
    chmod "$mode" "$d" >/dev/null 2>&1 || true
    return 0
  fi

  return 1
}

