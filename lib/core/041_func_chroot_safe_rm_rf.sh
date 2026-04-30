chroot_safe_rm_rf() {
  local path="$1"
  local ok
  local path_real runtime_real
  ok="$(chroot_path_is_within_runtime "$path")"
  [[ "$ok" == "yes" ]] || chroot_die "refusing to delete path outside runtime root: $path"
  path_real="$(chroot_path_realpath "$path")"
  runtime_real="$(chroot_path_realpath "$CHROOT_RUNTIME_ROOT")"
  [[ "$path_real" != "$runtime_real" ]] || chroot_die "refusing to delete runtime root"
  chroot_run_root rm -rf -- "$path"
}

