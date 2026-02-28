chroot_ensure_runtime_layout_as_user() {
  local d
  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    mkdir -p "$d" || return 1
  done < <(chroot_runtime_layout_dirs)
}

