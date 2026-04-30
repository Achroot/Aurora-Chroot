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

  # Do not delete runtime directories during repair.
  # If labels or permissions drift, limit the fix to mode and ownership changes.
  chroot_run_root chmod "$mode" "$d" >/dev/null 2>&1 || true
  chroot_run_root chown "$(id -u):$(id -g)" "$d" >/dev/null 2>&1 || true

  if touch "$probe" >/dev/null 2>&1; then
    rm -f -- "$probe" >/dev/null 2>&1 || true
    chmod "$mode" "$d" >/dev/null 2>&1 || true
    return 0
  fi

  return 1
}

