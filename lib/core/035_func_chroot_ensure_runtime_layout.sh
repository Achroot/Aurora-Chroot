chroot_runtime_root_is_absolute() {
  local p="$1"
  [[ "$p" == /* ]]
}

chroot_runtime_root_is_safe_path() {
  local p="$1"
  case "$p" in
    ""|"/"|"/data"|"/data/local"|"/data/local/tmp"|"/proc"|"/sys"|"/dev"|"/storage"|"/sdcard"|"/system"|"/vendor"|"/product"|"/apex")
      return 1
      ;;
  esac
  return 0
}

chroot_runtime_root_has_layout() {
  local p="$1"
  [[ -d "$p" ]] || return 1

  if [[ -f "$p/$CHROOT_RUNTIME_ROOT_MARKER" ]]; then
    return 0
  fi

  if [[ -d "$p/rootfs" && -d "$p/state" ]]; then
    return 0
  fi

  return 1
}

chroot_runtime_root_is_writable_candidate() {
  local p="$1"
  local probe parent probe_dir

  if [[ -d "$p" ]]; then
    probe="$p/.write-test.$$"
    touch "$probe" >/dev/null 2>&1 || return 1
    rm -f -- "$probe" >/dev/null 2>&1 || true
    return 0
  fi

  parent="$(dirname "$p")"
  mkdir -p "$parent" >/dev/null 2>&1 || return 1
  probe_dir="$(mktemp -d "$parent/.aurora-probe.XXXXXX" 2>/dev/null || true)"
  [[ -n "$probe_dir" && -d "$probe_dir" ]] || return 1
  rm -rf -- "$probe_dir" >/dev/null 2>&1 || true
  return 0
}

chroot_runtime_home_fallback() {
  local home_dir
  home_dir="${HOME:-$CHROOT_TERMUX_HOME_DEFAULT}"
  [[ -n "$home_dir" && "$home_dir" == /* ]] || return 1
  printf '%s/%s\n' "$home_dir" "$CHROOT_RUNTIME_ROOT_FALLBACK_HOME_REL"
}

chroot_runtime_root_priority_candidates() {
  printf '%s\n' "$CHROOT_DEFAULT_RUNTIME_ROOT"
  printf '%s\n' "/data/adb/aurora-chroot"
  printf '%s\n' "/data/aurora-chroot"
  chroot_runtime_home_fallback || true
}

chroot_runtime_root_accept_candidate() {
  local p="$1"
  chroot_runtime_root_is_absolute "$p" || return 1
  chroot_runtime_root_is_safe_path "$p" || return 1
  chroot_runtime_root_is_writable_candidate "$p" || return 1
  printf '%s\n' "$p"
}

chroot_resolve_runtime_root() {
  local explicit candidate resolved
  local -a existing_scan

  explicit="${CHROOT_RUNTIME_ROOT:-}"
  if [[ "${CHROOT_RUNTIME_ROOT_FROM_ENV:-0}" == "1" ]]; then
    resolved="$(chroot_runtime_root_accept_candidate "$explicit" || true)"
    [[ -n "$resolved" ]] || chroot_die "invalid CHROOT_RUNTIME_ROOT override: $explicit (must be absolute, safe, and writable)"
    chroot_set_runtime_root "$resolved"
    CHROOT_RUNTIME_ROOT_RESOLVED=1
    return 0
  fi

  existing_scan=()
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
    resolved="$(chroot_runtime_root_accept_candidate "$candidate" || true)"
    if [[ -n "$resolved" ]]; then
      chroot_set_runtime_root "$resolved"
      CHROOT_RUNTIME_ROOT_RESOLVED=1
      return 0
    fi
  done

  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    resolved="$(chroot_runtime_root_accept_candidate "$candidate" || true)"
    if [[ -n "$resolved" ]]; then
      chroot_set_runtime_root "$resolved"
      CHROOT_RUNTIME_ROOT_RESOLVED=1
      return 0
    fi
  done < <(chroot_runtime_root_priority_candidates)

  chroot_die "unable to resolve runtime root; set CHROOT_RUNTIME_ROOT to an absolute writable path"
}

chroot_ensure_runtime_layout() {
  local d mode marker_file

  chroot_runtime_root_is_safe_path "$CHROOT_RUNTIME_ROOT" || chroot_die "unsafe runtime root path: $CHROOT_RUNTIME_ROOT"

  if chroot_ensure_runtime_layout_as_user && chroot_runtime_is_user_writable; then
    marker_file="$CHROOT_RUNTIME_ROOT/$CHROOT_RUNTIME_ROOT_MARKER"
    printf '%s\n' "$(chroot_now_ts)" >"$marker_file" 2>/dev/null || true
    return 0
  fi

  chroot_run_root mkdir -p "$CHROOT_RUNTIME_ROOT" || chroot_die "failed preparing runtime layout at $CHROOT_RUNTIME_ROOT"
  chroot_run_root chown "$(id -u):$(id -g)" "$CHROOT_RUNTIME_ROOT" >/dev/null 2>&1 || true
  chroot_run_root chmod 0755 "$CHROOT_RUNTIME_ROOT" >/dev/null 2>&1 || true
  mkdir -p "$CHROOT_RUNTIME_ROOT" >/dev/null 2>&1 || chroot_die "runtime root is not writable by this user: $CHROOT_RUNTIME_ROOT"

  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    mode=755
    [[ "$d" == "$CHROOT_ROOTFS_DIR" ]] && mode=755
    [[ "$d" == "$CHROOT_STATE_DIR" ]] && mode=700
    [[ "$d" == "$CHROOT_LOG_DIR" ]] && mode=700
    [[ "$d" == "$CHROOT_LOCK_DIR" ]] && mode=700
    [[ "$d" == "$CHROOT_TMP_DIR" ]] && mode=700
    chroot_runtime_rebuild_dir_as_user "$d" "$mode" || chroot_die "runtime root is not writable by this user: $CHROOT_RUNTIME_ROOT"
  done < <(chroot_runtime_subdirs)

  chroot_runtime_is_user_writable || chroot_die "runtime root is not writable by this user: $CHROOT_RUNTIME_ROOT"

  marker_file="$CHROOT_RUNTIME_ROOT/$CHROOT_RUNTIME_ROOT_MARKER"
  printf '%s\n' "$(chroot_now_ts)" >"$marker_file" 2>/dev/null || chroot_run_root touch "$marker_file" >/dev/null 2>&1 || true
}
