chroot_tor_is_active_distro() {
  local distro="$1"
  local active_distro active_at
  IFS='|' read -r active_distro active_at <<<"$(chroot_tor_global_active_tsv)"
  [[ -n "$active_distro" && "$active_distro" == "$distro" ]]
}

chroot_tor_session_is_tracked() {
  local distro="$1"
  local sf
  sf="$(chroot_distro_session_file "$distro")"
  [[ -f "$sf" ]] || return 1
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$sf" "$(chroot_tor_session_id)" <<'PY'
import json
import sys

path, wanted = sys.argv[1:3]
try:
    with open(path, "r", encoding="utf-8") as fh:
        rows = json.load(fh)
except Exception:
    rows = []

if not isinstance(rows, list):
    rows = []

for row in rows:
    if str(row.get("session_id", "")) == wanted:
        sys.exit(0)
sys.exit(1)
PY
}

chroot_tor_teardown_for_distro() {
  local distro="$1"
  if chroot_tor_is_active_distro "$distro" || chroot_tor_current_pid "$distro" >/dev/null 2>&1 || chroot_tor_session_is_tracked "$distro"; then
    chroot_tor_disable "$distro"
    return $?
  fi
  return 0
}

chroot_tor_locked_teardown_for_distro() {
  local distro="$1"
  local rc=0

  chroot_lock_acquire "global" || return 1
  chroot_lock_acquire "tor" || {
    chroot_lock_release "global"
    return 1
  }
  chroot_tor_teardown_for_distro "$distro" >/dev/null 2>&1 || rc=$?
  chroot_lock_release "tor"
  chroot_lock_release "global"
  return "$rc"
}

chroot_tor_remove_managed_files() {
  local distro="$1"
  local rootfs state_dir path

  rootfs="$(chroot_distro_rootfs_dir "$distro")"
  state_dir="$(chroot_tor_state_dir "$distro")"

  chroot_tor_teardown_for_distro "$distro" >/dev/null 2>&1 || true
  chroot_tor_performance_controller_stop "$distro" >/dev/null 2>&1 || true
  chroot_session_remove "$distro" "$(chroot_tor_session_id)" >/dev/null 2>&1 || true
  chroot_tor_targets_invalidate "$distro"
  chroot_tor_clear_global_active >/dev/null 2>&1 || true

  for path in \
    "$rootfs/etc/aurora-tor" \
    "$rootfs/var/lib/aurora-tor" \
    "$rootfs/etc/tor" \
    "$rootfs/var/lib/tor" \
    "$rootfs/var/log/tor" \
    "$rootfs/var/cache/tor"
  do
    if chroot_run_root test -e "$path" >/dev/null 2>&1; then
      chroot_run_root rm -rf -- "$path" >/dev/null 2>&1 || true
    fi
  done

  if [[ -d "$state_dir" ]]; then
    chroot_safe_rm_rf "$state_dir"
  fi
}
