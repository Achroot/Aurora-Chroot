#!/usr/bin/env bash

CHROOT_BUSYBOX_CACHE_SCHEMA=1
CHROOT_BUSYBOX_REPO_RAW_BASE="https://raw.githubusercontent.com/Magisk-Modules-Repo/busybox-ndk/master"

chroot_busybox_dir() {
  printf '%s/busybox\n' "$CHROOT_RUNTIME_ROOT"
}

chroot_busybox_cache_file() {
  printf '%s/cache.json\n' "$(chroot_busybox_dir)"
}

chroot_busybox_active_binary_path() {
  printf '%s/busybox\n' "$(chroot_busybox_dir)"
}

chroot_busybox_active_applets_dir() {
  printf '%s/applets\n' "$(chroot_busybox_dir)"
}

chroot_busybox_required_tools_tsv() {
  cat <<'EOF_TSV'
chroot	CHROOT_CHROOT_BIN	chroot	chroot	1
mount	CHROOT_MOUNT_BIN	mount	mount	1
umount	CHROOT_UMOUNT_BIN	umount	umount	1
EOF_TSV
}

chroot_busybox_required_tool_ids() {
  local tool override applet_toybox applet_busybox required
  while IFS=$'\t' read -r tool override applet_toybox applet_busybox required; do
    [[ -n "$tool" && "$required" == "1" ]] || continue
    printf '%s\n' "$tool"
  done < <(chroot_busybox_required_tools_tsv)
}

chroot_busybox_required_tool_csv() {
  local out="" tool
  while IFS= read -r tool; do
    [[ -n "$tool" ]] || continue
    if [[ -n "$out" ]]; then
      out+=", "
    fi
    out+="$tool"
  done < <(chroot_busybox_required_tool_ids)
  printf '%s\n' "$out"
}

chroot_busybox_tool_tsv() {
  local wanted="$1"
  local tool override applet_toybox applet_busybox required
  while IFS=$'\t' read -r tool override applet_toybox applet_busybox required; do
    [[ "$tool" == "$wanted" ]] || continue
    printf '%s\t%s\t%s\t%s\t%s\n' "$tool" "$override" "$applet_toybox" "$applet_busybox" "$required"
    return 0
  done < <(chroot_busybox_required_tools_tsv)
  return 1
}

chroot_busybox_tool_busybox_applet() {
  local tool="$1"
  local _tool _override _toybox busybox _required
  IFS=$'\t' read -r _tool _override _toybox busybox _required <<<"$(chroot_busybox_tool_tsv "$tool" || true)"
  [[ -n "$busybox" ]] || return 1
  printf '%s\n' "$busybox"
}

chroot_busybox_tool_toybox_applet() {
  local tool="$1"
  local _tool _override toybox _busybox _required
  IFS=$'\t' read -r _tool _override toybox _busybox _required <<<"$(chroot_busybox_tool_tsv "$tool" || true)"
  [[ -n "$toybox" ]] || return 1
  printf '%s\n' "$toybox"
}

chroot_busybox_ensure_runtime_layout() {
  local dir
  if [[ "${CHROOT_RUNTIME_ROOT_RESOLVED:-0}" != "1" ]]; then
    chroot_resolve_runtime_root
  fi
  chroot_ensure_runtime_layout
  dir="$(chroot_busybox_dir)"
  mkdir -p "$dir" || chroot_die "failed preparing BusyBox runtime directory: $dir"
}

chroot_busybox_is_archive_path() {
  local p="${1,,}"
  case "$p" in
    *.zip|*.tar|*.tar.gz|*.tgz|*.tar.xz|*.txz|*.tar.zst|*.tzst|*.tar.bz2|*.tbz2|*.7z|*.rar|*.apk)
      return 0
      ;;
  esac
  return 1
}

chroot_busybox_now() {
  chroot_now_ts
}

chroot_busybox_cleanup_staging() {
  local dir
  dir="$(chroot_busybox_dir)"
  [[ -d "$dir" ]] || return 0
  find "$dir" -maxdepth 1 -type d -name 'import.staging.*' -exec rm -rf -- {} + 2>/dev/null || true
}
