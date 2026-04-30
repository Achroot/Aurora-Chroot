#!/usr/bin/env bash

chroot_backup_default_out() {
  local distro="$1"
  local mode="$2"
  local ext
  if [[ -n "$CHROOT_ZSTD_BIN" ]]; then
    ext="tar.zst"
  else
    ext="tar.xz"
  fi
  printf '%s/%s-%s-%s.%s' "$CHROOT_BACKUPS_DIR" "$distro" "$mode" "$(chroot_now_compact)" "$ext"
}

chroot_backup_join_dir_file() {
  local dir="$1"
  local file_name="$2"
  dir="${dir%/}"
  [[ -n "$dir" ]] || dir="/"
  if [[ "$dir" == "/" ]]; then
    printf '/%s\n' "$file_name"
    return
  fi
  printf '%s/%s\n' "$dir" "$file_name"
}

chroot_backup_resolve_out_path() {
  local distro="$1"
  local mode="$2"
  local out_raw="${3:-}"
  local default_name out_dir

  if [[ -z "$out_raw" ]]; then
    chroot_backup_default_out "$distro" "$mode"
    return
  fi

  default_name="$(basename "$(chroot_backup_default_out "$distro" "$mode")")"
  out_dir="${out_raw%/}"
  [[ -n "$out_dir" ]] || out_dir="/"
  chroot_backup_join_dir_file "$out_dir" "$default_name"
}

chroot_backup_cleanup_failed_out() {
  local out_file="$1"
  [[ -e "$out_file" && ! -d "$out_file" ]] || return 0
  rm -f -- "$out_file" >/dev/null 2>&1 || true
}

chroot_backup_make_archive() {
  local distro="$1"
  local mode="$2"
  local out_file="$3"

  local tmp_tar
  tmp_tar="$CHROOT_TMP_DIR/backup-$distro-$mode-$$.tar"

  local items=()
  case "$mode" in
    rootfs)
      items+=("rootfs/$distro")
      ;;
    state)
      items+=("state/$distro")
      [[ -f "$CHROOT_SETTINGS_FILE" ]] && items+=("state/settings.json")
      ;;
    full)
      items+=("rootfs/$distro" "state/$distro")
      [[ -f "$CHROOT_SETTINGS_FILE" ]] && items+=("state/settings.json")
      ;;
    *) chroot_die "unknown backup mode: $mode" ;;
  esac

  local rel
  for rel in "${items[@]}"; do
    [[ -e "$CHROOT_RUNTIME_ROOT/$rel" ]] || chroot_die "missing backup source: $rel"
  done

  if ! chroot_run_root "$CHROOT_TAR_BIN" -C "$CHROOT_RUNTIME_ROOT" -cf "$tmp_tar" "${items[@]}"; then
    rm -f -- "$tmp_tar"
    chroot_die "backup tar creation failed"
  fi

  if [[ -n "$CHROOT_ZSTD_BIN" ]]; then
    if ! "$CHROOT_ZSTD_BIN" -T0 -f "$tmp_tar" -o "$out_file"; then
      rm -f -- "$tmp_tar"
      chroot_backup_cleanup_failed_out "$out_file"
      chroot_die "backup compression failed (zstd)"
    fi
  else
    if ! "$CHROOT_XZ_BIN" -z -f -c "$tmp_tar" >"$out_file"; then
      rm -f -- "$tmp_tar"
      chroot_backup_cleanup_failed_out "$out_file"
      chroot_die "backup compression failed (xz)"
    fi
  fi
  rm -f -- "$tmp_tar"

  local sha
  sha="$(chroot_sha256_file "$out_file")"
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$out_file.meta.json" "$distro" "$mode" "$(chroot_now_ts)" "$(basename "$out_file")" "$sha" <<'PY'
import json
import sys

meta_path, distro, mode, created_at, archive_name, sha256 = sys.argv[1:7]
payload = {
    "distro": distro,
    "mode": mode,
    "created_at": created_at,
    "archive": archive_name,
    "sha256": sha256,
}
with open(meta_path, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY
}

chroot_backup_files_for_distro() {
  local distro="$1"
  [[ -d "$CHROOT_BACKUPS_DIR" ]] || return 0
  find "$CHROOT_BACKUPS_DIR" -maxdepth 1 -type f -name "${distro}-*" 2>/dev/null | awk '/\.tar(\.zst|\.xz)?$/ {print $0}' | sort -r
}

chroot_backup_parse_distro_from_archive_name() {
  local name="$1"
  local stem mode

  case "$name" in
    *.tar.zst) stem="${name%.tar.zst}" ;;
    *.tar.xz) stem="${name%.tar.xz}" ;;
    *.tar) stem="${name%.tar}" ;;
    *) return 1 ;;
  esac

  # Parse the default archive name first: <distro>-<mode>-YYYYMMDD-HHMMSS.tar.*
  if [[ "$stem" =~ ^(.+)-(full|rootfs|state)-[0-9]{8}-[0-9]{6}$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  # If that fails, fall back to older or custom names that still include "-<mode>-".
  for mode in full rootfs state; do
    if [[ "$stem" == *"-$mode-"* ]]; then
      printf '%s\n' "${stem%%-$mode-*}"
      return 0
    fi
  done

  return 1
}

chroot_backup_distros_with_archives() {
  [[ -d "$CHROOT_BACKUPS_DIR" ]] || return 0
  local name distro
  local -A seen=()
  for name in "$CHROOT_BACKUPS_DIR"/*; do
    [[ -f "$name" ]] || continue
    name="$(basename "$name")"
    [[ "$name" =~ \.tar(\.zst|\.xz)?$ ]] || continue
    distro="$(chroot_backup_parse_distro_from_archive_name "$name" || true)"
    [[ -n "$distro" && -z "${seen[$distro]:-}" ]] || continue
    seen["$distro"]=1
    printf '%s\n' "$distro"
  done | sort
}

chroot_restore_select_backup_distro() {
  local -a distros=()
  local distro
  while IFS= read -r distro; do
    [[ -n "$distro" ]] || continue
    distros+=("$distro")
  done < <(chroot_backup_distros_with_archives || true)

  if (( ${#distros[@]} == 0 )); then
    chroot_warn "No backups found."
    return 2
  fi

  printf '\nBackups available for distros:\n'
  local idx=1 count
  for distro in "${distros[@]}"; do
    count="$(chroot_backup_files_for_distro "$distro" | wc -l | tr -d ' ')"
    printf '  %2d) %-16s backups=%s\n' "$idx" "$distro" "${count:-0}"
    idx=$((idx + 1))
  done

  local pick
  while true; do
    printf 'Select backup distro (1-%s, q=cancel): ' "${#distros[@]}" >&2
    read -r pick
    case "$pick" in
      q|Q|'')
        return 1
        ;;
      *)
        if [[ "$pick" =~ ^[0-9]+$ ]] && (( pick >= 1 && pick <= ${#distros[@]} )); then
          printf '%s\n' "${distros[$((pick - 1))]}"
          return 0
        fi
        ;;
    esac
    printf 'Invalid selection.\n' >&2
  done
}

chroot_restore_select_backup_file() {
  local distro="$1"
  local -a files=()
  local f
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    files+=("$f")
  done < <(chroot_backup_files_for_distro "$distro" || true)

  if (( ${#files[@]} == 0 )); then
    chroot_warn "No backup archives found for distro '$distro'."
    return 2
  fi

  printf '\nBackups for %s:\n' "$distro"
  local idx=1 file_name
  for f in "${files[@]}"; do
    file_name="$(basename "$f")"
    printf '  %2d) %s\n' "$idx" "$file_name"
    idx=$((idx + 1))
  done

  local pick
  while true; do
    printf 'Select backup archive (1-%s, q=cancel): ' "${#files[@]}" >&2
    read -r pick
    case "$pick" in
      q|Q|'')
        return 1
        ;;
      *)
        if [[ "$pick" =~ ^[0-9]+$ ]] && (( pick >= 1 && pick <= ${#files[@]} )); then
          printf '%s\n' "${files[$((pick - 1))]}"
          return 0
        fi
        ;;
    esac
    printf 'Invalid selection.\n' >&2
  done
}

chroot_cmd_backup() {
  local distro=""
  if [[ $# -gt 0 && "$1" != --* ]]; then
    distro="$1"
    shift || true
  fi

  local out=""
  local mode="full"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --out)
        shift
        [[ $# -gt 0 ]] || chroot_die "--out needs value"
        out="$1"
        ;;
      --mode)
        shift
        [[ $# -gt 0 ]] || chroot_die "--mode needs value"
        mode="$1"
        ;;
      *) chroot_die "unknown backup arg: $1" ;;
    esac
    shift
  done

  if [[ -z "$distro" ]]; then
    local pick_rc=0
    distro="$(chroot_select_installed_distro "Select distro to backup")" || pick_rc=$?
    case "$pick_rc" in
      0) ;;
      2) chroot_die "no installed distros found" ;;
      *) chroot_die "backup aborted" ;;
    esac
  fi

  chroot_require_distro_arg "$distro"
  chroot_preflight_hard_fail

  local sessions
  sessions="$(chroot_session_count "$distro" 2>/dev/null || echo 0)"
  if (( sessions > 0 )); then
    chroot_die "backup blocked; active sessions=$sessions"
  fi

  if [[ "$mode" != "state" ]]; then
    local mounts
    mounts="$(chroot_mount_count_for_distro "$distro" 2>/dev/null || echo 0)"
    if (( mounts > 0 )); then
      chroot_die "backup blocked; distro has active mounts ($mounts). Run unmount first."
    fi
  fi

  out="$(chroot_backup_resolve_out_path "$distro" "$mode" "$out")"
  mkdir -p "$(dirname "$out")"

  chroot_lock_acquire "distro-$distro" || chroot_die "failed distro lock"
  chroot_backup_make_archive "$distro" "$mode" "$out"
  chroot_lock_release "distro-$distro"

  chroot_log_info backup "distro=$distro mode=$mode out=$out"
  chroot_info "Backup created: $out"
}

chroot_restore_verify_meta_checksum() {
  local file="$1"
  local meta expected archive_name got
  meta="${file}.meta.json"

  [[ -f "$meta" ]] || {
    chroot_warn "No restore metadata file found for checksum verification: $meta"
    return 0
  }

  chroot_require_python
  if ! expected="$("$CHROOT_PYTHON_BIN" - "$meta" "$file" <<'PY'
import json
import os
import sys

meta_path, archive_path = sys.argv[1:3]
with open(meta_path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
if not isinstance(data, dict):
    print("invalid meta format", file=sys.stderr)
    sys.exit(2)

sha = str(data.get("sha256", "")).strip()
if not sha:
    print("missing sha256 in restore metadata", file=sys.stderr)
    sys.exit(3)

archive = str(data.get("archive", "")).strip()
base = os.path.basename(archive_path)
if archive and archive != base:
    print(f"metadata archive mismatch: expected {archive}, got {base}", file=sys.stderr)
    sys.exit(4)

print(sha)
PY
)"; then
    chroot_die "restore metadata verification failed: $meta"
  fi

  archive_name="$(basename "$file")"
  got="$(chroot_sha256_file "$file")"
  [[ "$got" == "$expected" ]] || chroot_die "restore checksum mismatch for $archive_name"
}

chroot_restore_decompress_to_tar() {
  local in_file="$1"
  local out_tar="$2"

  case "$in_file" in
    *.tar.zst)
      [[ -n "$CHROOT_ZSTD_BIN" ]] || chroot_die "zstd not available to restore .zst"
      "$CHROOT_ZSTD_BIN" -d -c "$in_file" >"$out_tar"
      ;;
    *.tar.xz)
      [[ -n "$CHROOT_XZ_BIN" ]] || chroot_die "xz not available to restore .xz"
      "$CHROOT_XZ_BIN" -d -c "$in_file" >"$out_tar"
      ;;
    *.tar)
      cp -f -- "$in_file" "$out_tar"
      ;;
    *)
      chroot_die "unsupported restore file extension: $in_file"
      ;;
  esac
}

chroot_restore_validate_tar() {
  local distro="$1"
  local tar_file="$2"

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$tar_file" "$distro" <<'PY'
import pathlib
import posixpath
import sys
import tarfile

tar_path, distro = sys.argv[1:3]
rootfs_prefix = f"rootfs/{distro}"
state_prefix = f"state/{distro}"
allowed_exact = {rootfs_prefix, state_prefix, "state/settings.json"}

def in_prefix(path: str, prefix: str) -> bool:
    return path == prefix or path.startswith(prefix + "/")

def safe_name(name: str) -> bool:
    if not name:
        return False
    p = pathlib.PurePosixPath(name)
    if p.is_absolute():
        return False
    for part in p.parts:
        if part in ("", ".."):
            return False
    return True

def safe_restore_path(name: str) -> bool:
    if name in allowed_exact:
        return True
    if in_prefix(name, rootfs_prefix):
        return True
    if in_prefix(name, state_prefix):
        return True
    return False

def allowed_restore_device_entry(name: str) -> bool:
    return in_prefix(name, f"{rootfs_prefix}/dev")

with tarfile.open(tar_path, mode="r:") as tf:
    for member in tf.getmembers():
        name = member.name
        if name in (".", "./"):
            continue
        if not safe_name(name):
            print(f"restore archive contains unsafe path entry: {name}", file=sys.stderr)
            sys.exit(1)
        if not safe_restore_path(name):
            print(f"restore archive contains out-of-scope entry: {name}", file=sys.stderr)
            sys.exit(1)
        if member.isdev():
            if not allowed_restore_device_entry(name):
                print(f"restore archive contains unsupported device entry: {name}", file=sys.stderr)
                sys.exit(1)

        if member.issym() or member.islnk():
            target = member.linkname or ""
            if in_prefix(name, rootfs_prefix):
                if not target:
                    print(f"restore archive contains unsafe link target: {name} -> {target}", file=sys.stderr)
                    sys.exit(1)
                if member.islnk() and target.startswith("/"):
                    print(f"restore archive contains unsafe hardlink target: {name} -> {target}", file=sys.stderr)
                    sys.exit(1)
                if target.startswith("/"):
                    resolved = posixpath.normpath(
                        posixpath.join(rootfs_prefix, posixpath.normpath(target).lstrip("/"))
                    )
                else:
                    resolved = posixpath.normpath(posixpath.join(posixpath.dirname(name), target))
                if not in_prefix(resolved, rootfs_prefix):
                    print(f"restore archive link escapes rootfs scope: {name} -> {target}", file=sys.stderr)
                    sys.exit(1)
            elif in_prefix(name, state_prefix):
                if not target or target.startswith("/"):
                    print(f"restore archive contains unsafe link target: {name} -> {target}", file=sys.stderr)
                    sys.exit(1)
                resolved = posixpath.normpath(posixpath.join(posixpath.dirname(name), target))
                if not in_prefix(resolved, state_prefix):
                    print(f"restore archive link escapes state scope: {name} -> {target}", file=sys.stderr)
                    sys.exit(1)
            else:
                # Reject links here because state/settings.json must stay a real file.
                print(f"restore archive contains disallowed link entry: {name}", file=sys.stderr)
                sys.exit(1)
PY
  local rc=$?
  (( rc == 0 )) || chroot_die "restore archive validation failed"
}

chroot_cmd_restore() {
  local distro=""
  if [[ $# -gt 0 && "$1" != --* ]]; then
    distro="$1"
    shift || true
  fi

  local file=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file)
        shift
        [[ $# -gt 0 ]] || chroot_die "--file needs value"
        file="$1"
        ;;
      *) chroot_die "unknown restore arg: $1" ;;
    esac
    shift
  done

  if [[ -z "$distro" ]]; then
    local pick_rc=0
    distro="$(chroot_restore_select_backup_distro)" || pick_rc=$?
    case "$pick_rc" in
      0) ;;
      2) chroot_die "no backups found" ;;
      *) chroot_die "restore aborted" ;;
    esac
  fi

  if [[ -z "$file" ]]; then
    local file_pick_rc=0
    file="$(chroot_restore_select_backup_file "$distro")" || file_pick_rc=$?
    case "$file_pick_rc" in
      0) ;;
      2) chroot_die "no backups found for distro: $distro" ;;
      *) chroot_die "restore aborted" ;;
    esac
  fi

  [[ -f "$file" ]] || chroot_die "restore file not found: $file"
  chroot_require_distro_arg "$distro"

  chroot_preflight_hard_fail
  chroot_restore_verify_meta_checksum "$file"

  local rootfs state_dir
  rootfs="$(chroot_distro_rootfs_dir "$distro")"
  state_dir="$(chroot_distro_state_dir "$distro")"
  if [[ -e "$rootfs" || -e "$state_dir" ]]; then
    chroot_die "distro already exists; remove '$distro' first, then restore"
  fi

  chroot_lock_acquire "distro-$distro" || chroot_die "failed distro lock"

  local tmp_tar
  tmp_tar="$CHROOT_TMP_DIR/restore-$distro-$$.tar"
  chroot_restore_decompress_to_tar "$file" "$tmp_tar"
  chroot_restore_validate_tar "$distro" "$tmp_tar"

  chroot_run_root "$CHROOT_TAR_BIN" -C "$CHROOT_RUNTIME_ROOT" -xf "$tmp_tar"
  rm -f -- "$tmp_tar"
  local restored_rootfs=0 restored_state=0
  [[ -d "$rootfs" ]] && restored_rootfs=1
  [[ -d "$state_dir" ]] && restored_state=1
  (( restored_state == 1 )) || chroot_die "restore archive missing state data for $distro"

  if (( restored_rootfs == 1 )); then
    chroot_normalize_rootfs_layout "$distro" "$rootfs"
    chroot_set_distro_flag "$distro" "installed" "true"
    chroot_set_distro_flag "$distro" "incomplete" "false"
  else
    chroot_set_distro_flag "$distro" "installed" "false"
    chroot_set_distro_flag "$distro" "incomplete" "false"
    chroot_set_distro_flag "$distro" "release" ""
  fi

  chroot_set_distro_flag "$distro" "last_restore_at" "$(chroot_now_ts)"

  chroot_lock_release "distro-$distro"

  if (( restored_rootfs == 1 )); then
    local alias_rc=0
    chroot_alias_upsert_distro "$distro" || alias_rc=$?
    if (( alias_rc != 0 )); then
      chroot_warn "restore succeeded, but failed to update shell alias for $distro"
      chroot_log_warn restore "alias update failed distro=$distro rc=$alias_rc"
    else
      chroot_alias_print_upsert_notice "$distro"
    fi
    chroot_log_info restore "distro=$distro file=$file mode=full-or-rootfs"
    chroot_info "Restore completed for $distro"
  else
    chroot_log_info restore "distro=$distro file=$file mode=state-only"
    chroot_info "Restore completed for $distro (state-only; rootfs not restored)"
  fi
}
