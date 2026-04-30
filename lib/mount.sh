#!/usr/bin/env bash

chroot_is_mounted() {
  local target="$1"
  awk -v t="$target" '$5 == t {found=1} END{exit(found ? 0 : 1)}' /proc/self/mountinfo
}

chroot_mountinfo_exact_entry_from_file() {
  local target="$1"
  local mountinfo_file="${2:-/proc/self/mountinfo}"

  [[ -n "$target" && -r "$mountinfo_file" ]] || return 1
  awk -v t="$target" '
    {
      mountpoint=$5
      gsub(/\\040/, " ", mountpoint)
      if (mountpoint != t) {
        next
      }

      root=$4
      gsub(/\\040/, " ", root)

      for (i=6; i<=NF; i++) {
        if ($i == "-") {
          fstype=(i+1 <= NF ? $(i+1) : "")
          source=(i+2 <= NF ? $(i+2) : "")
          gsub(/\\040/, " ", source)
          record=mountpoint "\t" root "\t" fstype "\t" source
          found=1
          break
        }
      }
    }
    END {
      if (found) {
        print record
        exit 0
      }
      exit 1
    }
  ' "$mountinfo_file"
}

chroot_mountinfo_covering_entry_from_file() {
  local path="$1"
  local mountinfo_file="${2:-/proc/self/mountinfo}"

  [[ -n "$path" && -r "$mountinfo_file" ]] || return 1
  awk -v p="$path" '
    function matches(mp, candidate) {
      if (mp == "/") {
        return (substr(candidate, 1, 1) == "/")
      }
      return (candidate == mp || index(candidate, mp "/") == 1)
    }
    {
      mountpoint=$5
      gsub(/\\040/, " ", mountpoint)
      if (!matches(mountpoint, p)) {
        next
      }

      root=$4
      gsub(/\\040/, " ", root)

      for (i=6; i<=NF; i++) {
        if ($i == "-") {
          fstype=(i+1 <= NF ? $(i+1) : "")
          source=(i+2 <= NF ? $(i+2) : "")
          gsub(/\\040/, " ", source)
          record=mountpoint "\t" root "\t" fstype "\t" source
          found=1
          break
        }
      }
    }
    END {
      if (found) {
        print record
        exit 0
      }
      exit 1
    }
  ' "$mountinfo_file"
}

chroot_mountinfo_record_from_file() {
  local target="$1"
  local mountinfo_file="${2:-/proc/self/mountinfo}"
  local entry mountpoint root fstype source

  entry="$(chroot_mountinfo_exact_entry_from_file "$target" "$mountinfo_file" || true)"
  [[ -n "$entry" ]] || return 1
  IFS=$'\t' read -r mountpoint root fstype source <<<"$entry"
  printf '%s\t%s\t%s\n' "$root" "$fstype" "$source"
}

chroot_mountinfo_record() {
  chroot_mountinfo_record_from_file "$1" "/proc/self/mountinfo"
}

chroot_mount_path_signature() {
  local path="$1"
  chroot_require_python
  chroot_run_root "$CHROOT_PYTHON_BIN" -c 'import os, sys; st = os.stat(sys.argv[1]); print(f"{st.st_dev}:{st.st_ino}")' "$path" 2>/dev/null
}

chroot_mount_target_matches_fstype_from_file() {
  local target="$1"
  local expected_fstype="$2"
  local expected_source="${3:-}"
  local mountinfo_file="${4:-/proc/self/mountinfo}"
  local record mount_root actual_fstype actual_source

  record="$(chroot_mountinfo_record_from_file "$target" "$mountinfo_file" || true)"
  [[ -n "$record" ]] || return 1
  IFS=$'\t' read -r mount_root actual_fstype actual_source <<<"$record"

  [[ "$actual_fstype" == "$expected_fstype" ]] || return 1
  if [[ -n "$expected_source" && "$actual_source" != "$expected_source" ]]; then
    return 1
  fi
  return 0
}

chroot_mount_target_matches_fstype() {
  chroot_mount_target_matches_fstype_from_file "$1" "$2" "${3:-}" "/proc/self/mountinfo"
}

chroot_mount_expected_root_for_path() {
  local path="$1"
  local mountpoint="$2"
  local root="$3"

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$path" "$mountpoint" "$root" <<'PY'
import posixpath
import sys

path, mountpoint, root = sys.argv[1:4]

if path == mountpoint:
    print(root)
    raise SystemExit(0)

rel = posixpath.relpath(path, mountpoint)
if rel in {".", ""}:
    print(root)
else:
    print(posixpath.normpath(posixpath.join(root, rel)))
PY
}

chroot_mountinfo_exact_peer_count_from_file() {
  local mountpoint="$1"
  local root="$2"
  local fstype="$3"
  local source="$4"
  local exclude_mountpoint="${5:-}"
  local mountinfo_file="${6:-/proc/self/mountinfo}"

  [[ -n "$mountpoint" && -r "$mountinfo_file" ]] || return 1
  awk -v mp="$mountpoint" -v exclude_mp="$exclude_mountpoint" -v want_root="$root" -v want_fstype="$fstype" -v want_source="$source" '
    {
      cur_mp=$5
      gsub(/\\040/, " ", cur_mp)
      if (cur_mp == mp || (exclude_mp != "" && cur_mp == exclude_mp)) {
        next
      }

      cur_root=$4
      gsub(/\\040/, " ", cur_root)

      for (i=6; i<=NF; i++) {
        if ($i == "-") {
          cur_fstype=(i+1 <= NF ? $(i+1) : "")
          cur_source=(i+2 <= NF ? $(i+2) : "")
          gsub(/\\040/, " ", cur_source)
          if (cur_root == want_root && cur_fstype == want_fstype && cur_source == want_source) {
            count++
          }
          break
        }
      }
    }
    END { print count+0 }
  ' "$mountinfo_file"
}

chroot_mount_bind_record_matches_source() {
  local source="$1"
  local target="$2"
  local mountinfo_file="${3:-/proc/self/mountinfo}"
  local target_entry covering_entry
  local target_mountpoint target_root target_fstype target_source
  local source_mountpoint source_root source_fstype source_source
  local source_real="" source_path expected_root="" peer_count=0

  target_entry="$(chroot_mountinfo_exact_entry_from_file "$target" "$mountinfo_file" || true)"
  [[ -n "$target_entry" ]] || return 1
  IFS=$'\t' read -r target_mountpoint target_root target_fstype target_source <<<"$target_entry"

  case "$target_fstype" in
    proc|sysfs|tmpfs)
      return 1
      ;;
  esac

  source_real="$(chroot_path_realpath "$source" 2>/dev/null || true)"
  source_path="$source"
  [[ -n "$source_real" ]] && source_path="$source_real"

  covering_entry="$(chroot_mountinfo_covering_entry_from_file "$source_path" "$mountinfo_file" || true)"
  if [[ -n "$covering_entry" ]]; then
    IFS=$'\t' read -r source_mountpoint source_root source_fstype source_source <<<"$covering_entry"
    expected_root="$(chroot_mount_expected_root_for_path "$source_path" "$source_mountpoint" "$source_root" 2>/dev/null || true)"
    if [[ -n "$expected_root" ]]; then
      case "$target_root" in
        "$expected_root"|"$source"|"$source_real") ;;
        *) return 1 ;;
      esac
    fi
    if [[ "$source_path" == "$source_mountpoint" ]]; then
      peer_count="$(chroot_mountinfo_exact_peer_count_from_file "$source_mountpoint" "$source_root" "$source_fstype" "$source_source" "$target_mountpoint" "$mountinfo_file" 2>/dev/null || echo 0)"
      if [[ "$peer_count" =~ ^[0-9]+$ ]] && (( peer_count > 0 )); then
        return 1
      fi
    fi
    [[ -z "$source_source" || "$target_source" == "$source_source" ]]
    return $?
  fi

  [[ "$target_root" == "$source" || ( -n "$source_real" && "$target_root" == "$source_real" ) ]]
}

chroot_mount_bind_matches() {
  local source="$1"
  local target="$2"
  local source_sig target_sig

  source_sig="$(chroot_mount_path_signature "$source" || true)"
  target_sig="$(chroot_mount_path_signature "$target" || true)"
  if [[ -n "$source_sig" && "$source_sig" == "$target_sig" ]]; then
    return 0
  fi

  chroot_mount_bind_record_matches_source "$source" "$target" "/proc/self/mountinfo"
}

chroot_mount_rollback_target() {
  local target="$1"
  local distro="$2"
  local kind="$3"

  if ! chroot_is_mounted "$target"; then
    return 0
  fi

  if chroot_run_umount_cmd "$target"; then
    chroot_log_warn mount "rolled back failed $kind target=$target distro=$distro"
    return 0
  fi
  if chroot_run_umount_cmd -l "$target"; then
    chroot_log_warn mount "lazy-rolled-back failed $kind target=$target distro=$distro"
    return 0
  fi
  chroot_log_error mount "rollback failed kind=$kind target=$target distro=$distro"
  return 1
}

chroot_mount_count_under_path() {
  local base="$1"
  [[ -n "$base" ]] || {
    printf '0\n'
    return 0
  }
  awk -v b="$base" '
    {
      mountpoint=$5
      gsub(/\\040/, " ", mountpoint)
    }
    mountpoint == b || index(mountpoint, b "/") == 1 {count++}
    END {print count+0}
  ' /proc/self/mountinfo 2>/dev/null || printf '0\n'
}

chroot_mount_count_under_rootfs() {
  local distro="$1"
  local rootfs log_file
  rootfs="$(chroot_distro_rootfs_dir "$distro")"
  log_file="$(chroot_distro_mount_log "$distro")"

  [[ -f "$log_file" ]] || {
    chroot_mount_count_under_path "$rootfs"
    return 0
  }

  awk -F'\t' -v b="$rootfs" '
    function under(path, base) {
      return path == base || index(path, base "/") == 1
    }
    FNR == NR {
      target=$2
      kind=$3
      if (target == "") {
        next
      }
      logged[target]=1
      if (kind == "bind") {
        logged_bind[target]=1
      }
      next
    }
    {
      split($0, parts, " ")
      mountpoint=parts[5]
      gsub(/\\040/, " ", mountpoint)
      if (under(mountpoint, b)) {
        mountpoints[mountpoint]=1
      }
    }
    END {
      for (target in logged_bind) {
        if (target in mountpoints) {
          active_bind[target]=1
        }
      }
      for (mountpoint in mountpoints) {
        skip=0
        for (target in active_bind) {
          if (mountpoint != target && under(mountpoint, target) && !(mountpoint in logged)) {
            skip=1
            break
          }
        }
        if (!skip) {
          count++
        }
      }
      print count+0
    }
  ' "$log_file" /proc/self/mountinfo 2>/dev/null || printf '0\n'
}

chroot_mount_log_has_target() {
  local log_file="$1"
  local target="$2"
  [[ -f "$log_file" ]] || return 1
  awk -F'\t' -v t="$target" '$2==t {found=1} END{exit(found ? 0 : 1)}' "$log_file"
}

chroot_mount_log_append() {
  local log_file="$1"
  local source="$2"
  local target="$3"
  local kind="$4"

  mkdir -p "$(dirname "$log_file")"
  if ! chroot_mount_log_has_target "$log_file" "$target"; then
    printf '%s\t%s\t%s\n' "$source" "$target" "$kind" >>"$log_file"
  fi
}

chroot_mount_bind() {
  local distro="$1"
  local source="$2"
  local target_rel="$3"
  local log_file="$4"
  local rootfs target

  rootfs="$(chroot_distro_rootfs_dir "$distro")"
  target="$rootfs/$target_rel"

  chroot_run_root mkdir -p "$target"

  if chroot_is_mounted "$target"; then
    if chroot_mount_bind_matches "$source" "$target"; then
      chroot_mount_log_append "$log_file" "$source" "$target" "bind"
      return 0
    fi
    chroot_log_error mount "bind target already mounted to different source source=$source target=$target distro=$distro"
    return 1
  fi

  if ! chroot_run_mount_cmd --bind "$source" "$target"; then
    chroot_log_error mount "bind failed source=$source target=$target distro=$distro"
    return 1
  fi
  if ! chroot_mount_bind_matches "$source" "$target"; then
    chroot_mount_rollback_target "$target" "$distro" "bind" || true
    chroot_log_error mount "bind validation failed source=$source target=$target distro=$distro"
    return 1
  fi
  chroot_mount_log_append "$log_file" "$source" "$target" "bind"
}

chroot_mount_proc_like() {
  local distro="$1"
  local source="$2"
  local target_rel="$3"
  local fstype="$4"
  local log_file="$5"
  local rootfs target

  rootfs="$(chroot_distro_rootfs_dir "$distro")"
  target="$rootfs/$target_rel"

  chroot_run_root mkdir -p "$target"

  if chroot_is_mounted "$target"; then
    if chroot_mount_target_matches_fstype "$target" "$fstype" "$source"; then
      chroot_mount_log_append "$log_file" "$source" "$target" "$fstype"
      return 0
    fi
    chroot_log_error mount "target already mounted with unexpected fstype source=$source target=$target expected_fstype=$fstype distro=$distro"
    return 1
  fi

  if ! chroot_run_mount_cmd -t "$fstype" "$source" "$target"; then
    chroot_log_error mount "mount failed fstype=$fstype source=$source target=$target distro=$distro"
    return 1
  fi
  if ! chroot_mount_target_matches_fstype "$target" "$fstype" "$source"; then
    chroot_mount_rollback_target "$target" "$distro" "$fstype" || true
    chroot_log_error mount "mount validation failed fstype=$fstype source=$source target=$target distro=$distro"
    return 1
  fi
  chroot_mount_log_append "$log_file" "$source" "$target" "$fstype"
}

chroot_mount_dev_shm() {
  local distro="$1"
  local log_file="$2"
  local rootfs target

  rootfs="$(chroot_distro_rootfs_dir "$distro")"
  target="$rootfs/dev/shm"

  chroot_run_root mkdir -p "$target"
  if chroot_is_mounted "$target"; then
    if [[ -d "/dev/shm" ]]; then
      if chroot_mount_bind_matches "/dev/shm" "$target"; then
        chroot_mount_log_append "$log_file" "/dev/shm" "$target" "bind"
        return 0
      fi
      chroot_log_error mount "dev/shm target already mounted to different source target=$target distro=$distro"
      return 1
    fi
    if chroot_mount_target_matches_fstype "$target" "tmpfs" "tmpfs"; then
      chroot_mount_log_append "$log_file" "tmpfs" "$target" "tmpfs"
      return 0
    fi
    chroot_log_error mount "dev/shm target already mounted with unexpected fstype target=$target distro=$distro"
    return 1
  fi

  if [[ -d "/dev/shm" ]]; then
    if ! chroot_run_mount_cmd --bind "/dev/shm" "$target"; then
      chroot_log_error mount "bind failed source=/dev/shm target=$target distro=$distro"
      return 1
    fi
    if ! chroot_mount_bind_matches "/dev/shm" "$target"; then
      chroot_mount_rollback_target "$target" "$distro" "bind" || true
      chroot_log_error mount "bind validation failed source=/dev/shm target=$target distro=$distro"
      return 1
    fi
    chroot_mount_log_append "$log_file" "/dev/shm" "$target" "bind"
  else
    if ! chroot_run_mount_cmd -t tmpfs tmpfs "$target"; then
      chroot_log_error mount "tmpfs mount failed target=$target distro=$distro"
      return 1
    fi
    if ! chroot_mount_target_matches_fstype "$target" "tmpfs" "tmpfs"; then
      chroot_mount_rollback_target "$target" "$distro" "tmpfs" || true
      chroot_log_error mount "tmpfs validation failed target=$target distro=$distro"
      return 1
    fi
    chroot_mount_log_append "$log_file" "tmpfs" "$target" "tmpfs"
  fi
}

chroot_mount_prepare_pacman_env() {
  local distro="$1"
  local rootfs pacman_conf mtab tmp

  rootfs="$(chroot_distro_rootfs_dir "$distro")"
  pacman_conf="$rootfs/etc/pacman.conf"
  mtab="$rootfs/etc/mtab"

  [[ -f "$pacman_conf" ]] || return 0

  # Create /etc/mtab for package managers that still expect it.
  if ! chroot_run_root test -e "$mtab" >/dev/null 2>&1; then
    chroot_run_root ln -s /proc/mounts "$mtab" >/dev/null 2>&1 || true
  fi

  chroot_require_python
  tmp="$CHROOT_TMP_DIR/pacman-conf.$$.tmp"
  "$CHROOT_PYTHON_BIN" - "$pacman_conf" "$tmp" <<'PY'
import sys

src, dst = sys.argv[1:3]
with open(src, "r", encoding="utf-8") as fh:
    lines = fh.readlines()

changed = False
out = []
for line in lines:
    stripped = line.lstrip()
    if stripped.startswith("#"):
        out.append(line)
        continue
    token = stripped.strip().split()[0] if stripped.strip() else ""
    if token == "CheckSpace":
        out.append("#CheckSpace\n")
        changed = True
    else:
        out.append(line)

if not changed:
    sys.exit(3)

with open(dst, "w", encoding="utf-8") as fh:
    fh.writelines(out)
PY
  local rc=$?
  if (( rc == 3 )); then
    rm -f -- "$tmp"
    return 0
  fi
  if (( rc != 0 )); then
    rm -f -- "$tmp"
    chroot_log_warn mount "failed to patch pacman.conf CheckSpace for $distro"
    return 1
  fi

  chroot_run_root cp "$tmp" "$pacman_conf" || {
    rm -f -- "$tmp"
    chroot_log_warn mount "failed to update pacman.conf for $distro"
    return 1
  }
  chroot_run_root chmod 644 "$pacman_conf" >/dev/null 2>&1 || true
  rm -f -- "$tmp"
  chroot_log_info mount "disabled pacman CheckSpace for $distro"
}

chroot_mount_fix_profile_scripts() {
  local distro="$1"
  local rootfs gpm_sh

  rootfs="$(chroot_distro_rootfs_dir "$distro")"
  gpm_sh="$rootfs/etc/profile.d/gpm.sh"

  [[ -f "$gpm_sh" ]] || return 0

  if chroot_run_root grep -q '\[ -t 0 \]' "$gpm_sh" 2>/dev/null; then
    return 0
  fi

  local tmp
  tmp="$CHROOT_TMP_DIR/gpm-fix-$$.sh"
  cat > "$tmp" <<'GPMSH'
if [ -t 0 ]; then
    case "$(/usr/bin/tty 2>/dev/null)" in
        /dev/tty[0-9]*) [ -n "$(pidof -s gpm)" ] && /usr/bin/disable-paste ;;
    esac
fi
GPMSH
  chroot_run_root cp "$tmp" "$gpm_sh" || {
    rm -f -- "$tmp"
    chroot_log_warn mount "failed to patch gpm.sh for $distro"
    return 0
  }
  chroot_run_root chmod 644 "$gpm_sh" >/dev/null 2>&1 || true
  rm -f -- "$tmp"
  chroot_log_info mount "patched gpm.sh tty guard for $distro"
}

chroot_mount_ensure_dns() {
  local distro="$1"
  local rootfs resolv tmp dns wrote_any=0
  local current_ns desired_ns

  rootfs="$(chroot_distro_rootfs_dir "$distro")"
  resolv="$rootfs/etc/resolv.conf"
  tmp="$CHROOT_TMP_DIR/resolv.$$.conf"

  : >"$tmp"
  while IFS= read -r dns; do
    [[ -n "$dns" ]] || continue
    printf 'nameserver %s\n' "$dns" >>"$tmp"
    wrote_any=1
  done < <(chroot_dns_servers_list)

  if (( wrote_any == 0 )); then
    rm -f -- "$tmp"
    return 0
  fi

  current_ns="$(chroot_run_root awk '/^[[:space:]]*nameserver[[:space:]]+/ {print $2}' "$resolv" 2>/dev/null | sed '/^$/d' | sort -u || true)"
  desired_ns="$(awk '/^[[:space:]]*nameserver[[:space:]]+/ {print $2}' "$tmp" 2>/dev/null | sed '/^$/d' | sort -u || true)"

  if [[ -n "$current_ns" && "$current_ns" == "$desired_ns" ]]; then
    rm -f -- "$tmp"
    return 0
  fi

  chroot_run_root mkdir -p "$rootfs/etc" || {
    rm -f -- "$tmp"
    return 1
  }
  chroot_run_root cp "$tmp" "$resolv" || {
    rm -f -- "$tmp"
    return 1
  }
  chroot_run_root chmod 644 "$resolv" || {
    rm -f -- "$tmp"
    return 1
  }
  rm -f -- "$tmp"
  chroot_log_info mount "updated resolv.conf for $distro"
}

chroot_mount_emit_existing_dir() {
  local path="${1:-}"
  [[ -n "$path" && -d "$path" ]] || return 0
  printf '%s\n' "$path"
}

chroot_mount_emit_colon_dirs() {
  local raw="${1:-}"
  local entry
  local -a items=()
  local old_ifs="$IFS"

  [[ -n "$raw" ]] || return 0
  IFS=':'
  read -r -a items <<<"$raw"
  IFS="$old_ifs"

  for entry in "${items[@]}"; do
    entry="${entry#"${entry%%[![:space:]]*}"}"
    entry="${entry%"${entry##*[![:space:]]}"}"
    chroot_mount_emit_existing_dir "$entry"
  done
}

chroot_android_storage_sources() {
  local path name resolved=""

  chroot_mount_emit_existing_dir "/sdcard"
  if chroot_cmd_exists realpath; then
    resolved="$(realpath "/sdcard" 2>/dev/null || true)"
  elif chroot_cmd_exists readlink; then
    resolved="$(readlink -f "/sdcard" 2>/dev/null || true)"
  fi
  chroot_mount_emit_existing_dir "$resolved"

  chroot_mount_emit_existing_dir "/mnt/sdcard"
  chroot_mount_emit_existing_dir "/storage/self/primary"
  chroot_mount_emit_existing_dir "${EXTERNAL_STORAGE:-}"
  chroot_mount_emit_colon_dirs "${SECONDARY_STORAGE:-}"
  chroot_mount_emit_existing_dir "${EMULATED_STORAGE_SOURCE:-}"
  chroot_mount_emit_existing_dir "${EMULATED_STORAGE_TARGET:-}"

  if [[ -d "/storage/emulated" ]]; then
    for path in /storage/emulated/*; do
      [[ -d "$path" ]] || continue
      printf '%s\n' "$path"
    done
  fi

  if [[ -d "/mnt/user" ]]; then
    for path in /mnt/user/[0-9]*/primary; do
      [[ -d "$path" ]] || continue
      printf '%s\n' "$path"
    done
  fi

  if [[ -d "/storage" ]]; then
    for path in /storage/*; do
      [[ -d "$path" ]] || continue
      name="$(basename "$path")"
      case "$name" in
        emulated|self) continue ;;
      esac
      printf '%s\n' "$path"
    done
  fi
}

chroot_android_full_bind_sources() {
  cat <<'EOF_ANDROID_PARTS'
/apex
/cust
/my_product
/odm
/odm_dlkm
/oem
/product
/system
/system_dlkm
/system_ext
/vendor
/vendor_dlkm
EOF_ANDROID_PARTS

  chroot_android_full_bind_sources_from_file "/proc/self/mountinfo"
}

chroot_android_full_bind_sources_from_file() {
  local mountinfo_file="${1:-}"

  if [[ -r "$mountinfo_file" ]]; then
    awk '
      {
        mountpoint=$5
        gsub(/\\040/, " ", mountpoint)
        if (mountpoint !~ "^/[[:alnum:]_.-]+$") {
          next
        }
        name=substr(mountpoint, 2)
        if (name ~ /^(apex|cust([_.-][[:alnum:]_.-]+)?|my_[[:alnum:]_.-]+|odm([_.-][[:alnum:]_.-]+)?|oem([_.-][[:alnum:]_.-]+)?|product([_.-][[:alnum:]_.-]+)?|system([_.-][[:alnum:]_.-]+)?|vendor([_.-][[:alnum:]_.-]+)?)$/ || name ~ /_dlkm$/) {
          print mountpoint
        }
      }
    ' "$mountinfo_file" 2>/dev/null || true
  fi
}

chroot_termux_home_source() {
  local candidate=""
  local candidate_prefix=""

  if [[ -n "$CHROOT_TERMUX_HOME_DEFAULT" && "$CHROOT_TERMUX_HOME_DEFAULT" != "/root" && -d "$CHROOT_TERMUX_HOME_DEFAULT" ]]; then
    printf '%s\n' "$CHROOT_TERMUX_HOME_DEFAULT"
    return 0
  fi

  if [[ -n "$CHROOT_TERMUX_PREFIX" && "$CHROOT_TERMUX_PREFIX" == */usr && "$CHROOT_TERMUX_PREFIX" != "/usr" && -e "$CHROOT_TERMUX_PREFIX/bin/pkg" ]]; then
    candidate="${CHROOT_TERMUX_PREFIX%/usr}/home"
    if [[ -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  local nullglob_was_set=0
  if shopt -q nullglob; then
    nullglob_was_set=1
  fi
  shopt -s nullglob
  for candidate in /data/data/*/files/home /data/user/*/*/files/home; do
    candidate_prefix="${candidate%/home}/usr"
    if [[ -d "$candidate" && -e "${candidate_prefix}/bin/pkg" ]]; then
      printf '%s\n' "$candidate"
      if (( nullglob_was_set == 0 )); then
        shopt -u nullglob
      fi
      return 0
    fi
  done
  if (( nullglob_was_set == 0 )); then
    shopt -u nullglob
  fi

  if chroot_is_termux_env && [[ -n "${HOME:-}" && -d "${HOME:-}" ]]; then
    printf '%s\n' "${HOME:-}"
    return 0
  fi
  return 1
}

chroot_mount_apply_defaults() {
  local distro="$1"
  local log_file
  log_file="$(chroot_distro_mount_log "$distro")"

  chroot_ensure_distro_dirs "$distro"

  chroot_mount_bind "$distro" "/dev" "dev" "$log_file" || return 1
  chroot_mount_proc_like "$distro" "proc" "proc" "proc" "$log_file" || return 1
  chroot_mount_proc_like "$distro" "sysfs" "sys" "sysfs" "$log_file" || return 1
  chroot_mount_bind "$distro" "/dev/pts" "dev/pts" "$log_file" || return 1
  chroot_mount_dev_shm "$distro" "$log_file" || return 1

  if chroot_is_true "$(chroot_setting_get android_storage_bind)"; then
    local src rel
    while IFS= read -r src; do
      [[ -n "$src" ]] || continue
      rel="${src#/}"
      if ! chroot_mount_bind "$distro" "$src" "$rel" "$log_file"; then
        chroot_warn "skipped storage bind: $src"
      fi
    done < <(chroot_android_storage_sources | sort -u)
  fi

  if chroot_is_true "$(chroot_setting_get termux_home_bind)"; then
    local termux_home_src
    termux_home_src="$(chroot_termux_home_source || true)"
    if [[ -n "$termux_home_src" ]]; then
      if ! chroot_mount_bind "$distro" "$termux_home_src" "root/termux-home" "$log_file"; then
        chroot_warn "skipped termux-home bind: $termux_home_src"
      fi
    else
      chroot_warn "termux-home bind enabled but no Termux home path was detected"
    fi
  fi

  if chroot_is_true "$(chroot_setting_get data_bind)"; then
    if [[ -d "/data" ]]; then
      if ! chroot_mount_bind "$distro" "/data" "data" "$log_file"; then
        chroot_warn "skipped optional bind: /data"
      fi
    fi
  fi

  if chroot_is_true "$(chroot_setting_get android_full_bind)"; then
    local android_part
    while IFS= read -r android_part; do
      [[ -n "$android_part" && -d "$android_part" ]] || continue
      if ! chroot_mount_bind "$distro" "$android_part" "${android_part#/}" "$log_file"; then
        chroot_warn "skipped optional bind: $android_part"
      fi
    done < <(chroot_android_full_bind_sources | sort -u)
  fi

  if chroot_x11_enabled; then
    local x11_source
    x11_source="$(chroot_x11_socket_dir)"

    if ! chroot_x11_enable_display0 12; then
      chroot_warn "x11 enabled but display :0 is not ready yet; GUI apps may fail until Termux:X11 starts"
    fi

    if [[ -d "$x11_source" ]]; then
      if ! chroot_mount_bind "$distro" "$x11_source" "tmp/.X11-unix" "$log_file"; then
        chroot_warn "failed x11 socket bind for $distro"
      fi
    else
      chroot_warn "x11 socket directory not found: $x11_source"
    fi
  fi

  chroot_mount_prepare_pacman_env "$distro" || return 1
  chroot_mount_fix_profile_scripts "$distro"
  chroot_mount_ensure_dns "$distro" || return 1
}

chroot_cmd_mount() {
  local distro=""
  if [[ $# -gt 0 && "$1" != --* ]]; then
    distro="$1"
    shift || true
  fi
  [[ $# -eq 0 ]] || chroot_die "unknown mount arg: $1"

  if [[ -z "$distro" ]]; then
    local pick_rc=0
    distro="$(chroot_select_installed_distro "Select distro to mount")" || pick_rc=$?
    case "$pick_rc" in
      0) ;;
      2) chroot_die "no installed distros found" ;;
      *) chroot_die "mount aborted" ;;
    esac
  fi
  chroot_require_distro_arg "$distro"

  chroot_preflight_hard_fail
  [[ -d "$(chroot_distro_rootfs_dir "$distro")" ]] || chroot_die "distro not installed: $distro"

  chroot_lock_acquire "distro-$distro" || chroot_die "failed distro lock"
  if ! chroot_mount_apply_defaults "$distro"; then
    chroot_lock_release "distro-$distro"
    chroot_die "mount failed"
  fi
  chroot_lock_release "distro-$distro"

  chroot_log_info mount "mounted distro=$distro"
  chroot_info "Mounted $distro"
}

chroot_removal_check_probe() {
  local distro="$1"
  local sessions mounts rootfs_mounts safe=0

  sessions="$(chroot_session_count "$distro" 2>/dev/null || echo 0)"
  mounts="$(chroot_mount_count_for_distro "$distro" 2>/dev/null || echo 0)"
  rootfs_mounts="$(chroot_mount_count_under_rootfs "$distro" 2>/dev/null || echo 0)"

  if (( sessions == 0 && mounts == 0 && rootfs_mounts == 0 )); then
    safe=1
  fi

  printf '%s\t%s\t%s\t%s\n' "$sessions" "$mounts" "$rootfs_mounts" "$safe"
}

chroot_removal_check_report() {
  local distro="$1"
  local json="${2:-0}"
  local probe sessions mounts rootfs_mounts safe
  local safe_text safe_json

  probe="$(chroot_removal_check_probe "$distro")"
  IFS=$'\t' read -r sessions mounts rootfs_mounts safe <<<"$probe"

  safe_text="no"
  safe_json="false"
  if (( safe == 1 )); then
    safe_text="yes"
    safe_json="true"
  fi

  if (( json == 1 )); then
    printf '{\n'
    printf '  "distro": "%s",\n' "$distro"
    printf '  "sessions": %s,\n' "$sessions"
    printf '  "mount_entries": %s,\n' "$mounts"
    printf '  "rootfs_mounts": %s,\n' "$rootfs_mounts"
    printf '  "safe_to_remove": %s\n' "$safe_json"
    printf '}\n'
  else
    chroot_info "Removal check: distro=$distro sessions=$sessions mounts=$mounts rootfs_mounts=$rootfs_mounts safe_to_remove=$safe_text"
    if (( safe == 1 )); then
      chroot_info "$distro is safe to remove."
    else
      chroot_warn "$distro is not safe to remove yet. Run 'status --json --live --distro $distro' for details."
    fi
  fi

  (( safe == 1 ))
}

chroot_unmount_confirm_yes_no() {
  local prompt="$1"
  local answer
  while true; do
    printf '%s [y/N]: ' "$prompt" >&2
    read -r answer
    case "$answer" in
      y|Y|yes|YES)
        return 0
        ;;
      n|N|no|NO|'')
        return 1
        ;;
    esac
    printf 'Please answer y or n.\n' >&2
  done
}

chroot_cmd_unmount() {
  local distro=""
  local kill_sessions=-1
  local selected_interactive=0

  if [[ $# -gt 0 && "$1" != --* ]]; then
    distro="$1"
    shift || true
  fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --kill-sessions) kill_sessions=1 ;;
      --no-kill-sessions) kill_sessions=0 ;;
      *) chroot_die "unknown unmount arg: $1" ;;
    esac
    shift
  done

  if [[ -z "$distro" ]]; then
    selected_interactive=1
    local pick_rc=0
    distro="$(chroot_select_installed_distro "Select distro to unmount")" || pick_rc=$?
    case "$pick_rc" in
      0) ;;
      2) chroot_die "no installed distros found" ;;
      *) chroot_die "unmount aborted" ;;
    esac
  fi

  if (( kill_sessions < 0 )); then
    if (( selected_interactive == 1 )); then
      if chroot_unmount_confirm_yes_no "Kill active sessions for '$distro' before unmount?"; then
        kill_sessions=1
      else
        kill_sessions=0
      fi
    else
      kill_sessions=0
    fi
  fi

  local log_file rootfs_path rootfs_real
  local rc=0
  local sessions_remaining=0

  chroot_require_distro_arg "$distro"
  chroot_preflight_hard_fail
  rootfs_path="$(chroot_distro_rootfs_dir "$distro")"
  [[ -d "$rootfs_path" ]] || chroot_die "distro not installed: $distro"
  rootfs_real="$(chroot_path_realpath "$rootfs_path" 2>/dev/null || true)"
  [[ -n "$rootfs_real" ]] || chroot_die "failed to resolve distro rootfs path for unmount: $rootfs_path"

  log_file="$(chroot_distro_mount_log "$distro")"
  if (( kill_sessions == 1 )); then
    if declare -F chroot_tor_locked_teardown_for_distro >/dev/null 2>&1; then
      chroot_tor_locked_teardown_for_distro "$distro" >/dev/null 2>&1 || true
    fi
  fi
  chroot_lock_acquire "distro-$distro" || chroot_die "failed distro lock"

  if (( kill_sessions == 1 )); then
    if chroot_service_desktop_session_is_tracked "$distro"; then
      chroot_info "Stopping desktop service before session cleanup..."
      chroot_service_desktop_stop "$distro"
    fi
    local kill_out kill_rc targeted term_sent kill_sent cleaned skipped_identity
    kill_rc=0
    kill_out="$(chroot_session_kill_all "$distro" 3)" || kill_rc=$?
    IFS=$'\t' read -r targeted term_sent kill_sent sessions_remaining cleaned skipped_identity <<<"$kill_out"
    targeted="${targeted:-0}"
    term_sent="${term_sent:-0}"
    kill_sent="${kill_sent:-0}"
    sessions_remaining="${sessions_remaining:-0}"
    cleaned="${cleaned:-0}"
    skipped_identity="${skipped_identity:-0}"
    chroot_log_info unmount "session-kill distro=$distro targeted=$targeted term=$term_sent kill=$kill_sent remaining=$sessions_remaining cleaned=$cleaned skipped_identity=$skipped_identity"
    chroot_info "Session cleanup for $distro: targeted=$targeted term=$term_sent kill=$kill_sent remaining=$sessions_remaining cleaned=$cleaned"
    if (( skipped_identity > 0 )); then
      chroot_warn "Skipped $skipped_identity session entries for $distro (missing identity metadata)."
    fi
    if (( kill_rc != 0 || sessions_remaining > 0 )); then
      chroot_warn "Some sessions are still active for $distro after kill attempt."
      rc=1
    fi
  fi

  [[ -f "$log_file" ]] || {
    local verify_rc=0
    chroot_info "No mount log for $distro"
    chroot_lock_release "distro-$distro"
    chroot_removal_check_report "$distro" 0 || verify_rc=$?
    if (( rc == 0 && verify_rc != 0 )); then
      chroot_warn "Unmount completed but '$distro' is not safe_to_remove yet; returning non-zero."
      rc=$verify_rc
    fi
    return "$rc"
  }

  local lines=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && lines+=("$line")
  done <"$log_file"

  local i
  for (( i=${#lines[@]}-1; i>=0; i-- )); do
    local source target kind target_real target_ok=0
    IFS=$'\t' read -r source target kind <<<"${lines[$i]}"
    [[ -n "$target" ]] || continue

    target_real="$(chroot_path_realpath "$target" 2>/dev/null || true)"
    if [[ -z "$target_real" ]]; then
      chroot_warn "skipped unmount entry with unresolved target: $target"
      chroot_log_warn unmount "skip-invalid-entry unresolved-target=$target distro=$distro"
      rc=1
      continue
    fi
    case "$target_real" in
      "$rootfs_real"|"$rootfs_real"/*) target_ok=1 ;;
    esac
    if (( target_ok == 0 )); then
      chroot_warn "skipped unmount entry outside distro rootfs: $target"
      chroot_log_warn unmount "skip-invalid-entry outside-rootfs target=$target target_real=$target_real rootfs_real=$rootfs_real distro=$distro"
      rc=1
      continue
    fi

    if chroot_is_mounted "$target"; then
      if ! chroot_run_umount_cmd "$target"; then
        # Fall back to lazy unmount here because Android mounts can stay busy briefly.
        if ! chroot_run_umount_cmd -l "$target"; then
          chroot_warn "failed unmount: $target"
          chroot_log_warn unmount "failed target=$target distro=$distro"
          rc=1
        else
          chroot_log_warn unmount "lazy-unmounted target=$target distro=$distro"
        fi
      fi
    fi
  done

  if (( rc == 0 )); then
    : >"$log_file"
    chroot_log_info unmount "unmounted distro=$distro"
    chroot_info "Unmounted $distro"
  else
    chroot_log_warn unmount "partial unmount distro=$distro"
    chroot_warn "Partial unmount; check busy mounts"
  fi

  chroot_lock_release "distro-$distro"

  local verify_rc=0
  chroot_removal_check_report "$distro" 0 || verify_rc=$?
  if (( rc == 0 && verify_rc != 0 )); then
    chroot_warn "Unmount completed but '$distro' is not safe_to_remove yet; returning non-zero."
    rc=$verify_rc
  fi
  return "$rc"
}
