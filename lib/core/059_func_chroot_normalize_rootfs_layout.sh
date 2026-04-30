chroot_normalize_rootfs_layout() {
  local distro="$1"
  local rootfs="$2"
  local entry nested_rootfs nested_count tmp
  local -a top_entries=()

  [[ -d "$rootfs" ]] || chroot_die "rootfs missing for $distro: $rootfs"
  if chroot_rootfs_has_posix_sh "$rootfs"; then
    return 0
  fi

  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    top_entries+=("$entry")
  done < <(chroot_run_root find "$rootfs" -mindepth 1 -maxdepth 1 -print 2>/dev/null || true)

  nested_rootfs=""
  nested_count=0
  for entry in "${top_entries[@]}"; do
    if chroot_run_root test -d "$entry" >/dev/null 2>&1 && chroot_rootfs_has_posix_sh "$entry"; then
      nested_rootfs="$entry"
      nested_count=$((nested_count + 1))
    fi
  done

  if (( nested_count != 1 )); then
    chroot_die "invalid rootfs layout for $distro: expected /bin/sh at $rootfs or exactly one nested rootfs, found $nested_count"
  fi
  if (( ${#top_entries[@]} != 1 )) || [[ "${top_entries[0]}" != "$nested_rootfs" ]]; then
    chroot_die "invalid rootfs layout for $distro: nested rootfs detected but top-level has extra entries under $rootfs"
  fi

  tmp="$CHROOT_ROOTFS_DIR/.normalize-${distro}-$(chroot_now_compact)-$$"
  chroot_run_root rm -rf -- "$tmp" >/dev/null 2>&1 || true
  chroot_run_root mv "$nested_rootfs" "$tmp"
  chroot_run_root rmdir "$rootfs"
  chroot_run_root mv "$tmp" "$rootfs"

  chroot_rootfs_has_posix_sh "$rootfs" || chroot_die "rootfs normalization failed for $distro: /bin/sh still missing"
  chroot_info "Normalized rootfs layout for $distro (flattened ${nested_rootfs##*/})"
}

