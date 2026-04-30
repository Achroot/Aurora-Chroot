chroot_info_resolve_existing_runtime_root() {
  local explicit candidate
  local -a existing_scan=()

  explicit="${CHROOT_RUNTIME_ROOT:-}"
  if [[ "${CHROOT_RUNTIME_ROOT_FROM_ENV:-0}" == "1" ]]; then
    return 1
  fi

  if [[ -n "$explicit" ]]; then
    existing_scan+=("$explicit")
  fi
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    existing_scan+=("$candidate")
  done < <(chroot_runtime_root_priority_candidates)

  for candidate in "${existing_scan[@]}"; do
    chroot_runtime_root_is_absolute "$candidate" || continue
    chroot_runtime_root_is_safe_path "$candidate" || continue
    chroot_runtime_root_has_layout "$candidate" || continue
    chroot_set_runtime_root "$candidate"
    CHROOT_RUNTIME_ROOT_RESOLVED=1
    return 0
  done

  return 1
}
