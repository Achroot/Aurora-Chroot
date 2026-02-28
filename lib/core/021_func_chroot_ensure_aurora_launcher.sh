chroot_ensure_aurora_launcher() {
  if chroot_is_inside_chroot || ! chroot_is_termux_env; then
    return 0
  fi

  local bin_dir launcher target tmp_launcher
  launcher="$(chroot_aurora_launcher_path)"
  bin_dir="${launcher%/*}"
  mkdir -p "$bin_dir" || return 1

  target="$(chroot_resolve_self_path)"
  if [[ ! -f "$target" ]]; then
    target="$bin_dir/chroot"
  fi
  if [[ -f "$target" && -O "$target" ]]; then
    chmod 755 "$target" >/dev/null 2>&1 || true
  fi

  tmp_launcher="$bin_dir/.${CHROOT_AURORA_LAUNCHER_NAME}.tmp.$$"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    # Use bash explicitly so launcher works even when target script lives on noexec storage mounts.
    printf 'exec bash %q "$@"\n' "$target"
  } >"$tmp_launcher" || return 1
  chmod 755 "$tmp_launcher" || {
    rm -f -- "$tmp_launcher"
    return 1
  }
  mv -f -- "$tmp_launcher" "$launcher" || {
    rm -f -- "$tmp_launcher"
    return 1
  }
  chmod 755 "$launcher" >/dev/null 2>&1 || true
}
