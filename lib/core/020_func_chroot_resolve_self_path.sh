chroot_resolve_self_path() {
  local p="${1:-${CHROOT_INVOKED_PATH:-$0}}"
  local resolved

  if [[ -z "$p" ]]; then
    p="$0"
  fi

  if [[ "$p" != */* ]]; then
    resolved="$(command -v "$p" 2>/dev/null || true)"
    if [[ -n "$resolved" ]]; then
      p="$resolved"
    fi
  fi

  if chroot_cmd_exists realpath; then
    resolved="$(realpath "$p" 2>/dev/null || true)"
    if [[ -n "$resolved" ]]; then
      p="$resolved"
    fi
  fi

  printf '%s\n' "$p"
}
