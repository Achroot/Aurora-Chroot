#!/usr/bin/env bash

chroot_installed_distros() {
  if [[ -d "$CHROOT_ROOTFS_DIR" ]]; then
    local p
    for p in "$CHROOT_ROOTFS_DIR"/*; do
      [[ -d "$p" ]] || continue
      basename "$p"
    done | sort
  fi
}

chroot_select_installed_distro() {
  local prompt="${1:-Select distro}"
  local -a distros=()
  local distro

  while IFS= read -r distro; do
    [[ -n "$distro" ]] || continue
    distros+=("$distro")
  done < <(chroot_installed_distros || true)

  if (( ${#distros[@]} == 0 )); then
    chroot_warn "No installed distros found."
    return 2
  fi

  printf '\nInstalled distros:\n' >&2
  local idx=1 release sessions mounts
  for distro in "${distros[@]}"; do
    release="$(chroot_get_distro_flag "$distro" release 2>/dev/null || true)"
    sessions="$(chroot_session_count "$distro" 2>/dev/null || echo 0)"
    mounts="$(chroot_mount_count_for_distro "$distro" 2>/dev/null || echo 0)"
    printf '  %2d) %-16s release=%-8s sessions=%-3s mounts=%-3s\n' \
      "$idx" "$distro" "${release:-n/a}" "$sessions" "$mounts" >&2
    idx=$((idx + 1))
  done

  local pick
  while true; do
    printf '%s (1-%s, q=cancel): ' "$prompt" "${#distros[@]}" >&2
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

chroot_mount_count_for_distro() {
  local distro="$1"
  local log_file
  log_file="$(chroot_distro_mount_log "$distro")"
  [[ -f "$log_file" ]] || {
    printf '0\n'
    return 0
  }

  local count=0
  while IFS=$'\t' read -r _src target _kind; do
    [[ -n "$target" ]] || continue
    if chroot_is_mounted "$target"; then
      count=$((count + 1))
    fi
  done <"$log_file"

  printf '%s\n' "$count"
}

chroot_cmd_status() {
  local json=0
  local live=0
  local target_distro=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) json=1 ;;
      --live) live=1 ;;
      --all) ;;
      --distro)
        shift
        [[ $# -gt 0 ]] || chroot_die "--distro needs value"
        target_distro="$1"
        ;;
      *) chroot_die "unknown status arg: $1" ;;
    esac
    shift
  done

  chroot_preflight_hard_fail

  local installed_list
  installed_list="$(chroot_installed_distros || true)"
  if (( live == 1 && json == 0 )); then
    chroot_warn "--live is currently only applied to --json output"
  fi
  local prune_distro
  while IFS= read -r prune_distro; do
    [[ -n "$prune_distro" ]] || continue
    chroot_session_prune_stale "$prune_distro" >/dev/null 2>&1 || true
  done <<<"$installed_list"

  if (( json == 1 )); then
    chroot_require_python
    local installed_file
    installed_file="$CHROOT_TMP_DIR/status-installed.$$.txt"
    printf '%s\n' "$installed_list" >"$installed_file"

    "$CHROOT_PYTHON_BIN" - "$target_distro" "$CHROOT_RUNTIME_ROOT" "$CHROOT_CACHE_DIR" "$installed_file" "$CHROOT_BACKUPS_DIR" "$live" <<'PY'
import json
import os
import re
import sys

wanted, runtime_root, cache_dir, installed_file, backups_dir, live_text = sys.argv[1:7]
include_live = live_text == "1"
installed = []
if os.path.exists(installed_file):
    with open(installed_file, 'r', encoding='utf-8') as fh:
        installed = [x.strip() for x in fh if x.strip()]

mount_points = set()
try:
    with open('/proc/self/mountinfo', 'r', encoding='utf-8') as fh:
        for line in fh:
            parts = line.split()
            if len(parts) >= 5:
                mount_points.add(parts[4].replace('\\040', ' '))
except Exception:
    mount_points = set()


def path_under(path, base):
    base = str(base or '').rstrip('/') or '/'
    if base == '/':
        return str(path or '').startswith('/')
    return path == base or str(path or '').startswith(base + '/')


def filtered_rootfs_mount_count(mount_points, rootfs_base, logged_targets, bind_targets):
    count = 0
    active_bind_targets = [target for target in bind_targets if target in mount_points]
    for mount_point in mount_points:
        if not path_under(mount_point, rootfs_base):
            continue
        skip = False
        for target in active_bind_targets:
            if mount_point != target and path_under(mount_point, target) and mount_point not in logged_targets:
                skip = True
                break
        if not skip:
            count += 1
    return count


def pid_is_live(pid):
    try:
        os.kill(pid, 0)
        return True
    except PermissionError:
        return True
    except OSError:
        return False


def parse_backup_distro(name):
    m = re.match(r'^(?P<distro>.+)-(full|rootfs|state)-\d{8}-\d{6}\.tar(?:\.(?:zst|xz))?$', name)
    if m:
        return m.group('distro')
    for mode in ('full', 'rootfs', 'state'):
        marker = f'-{mode}-'
        idx = name.find(marker)
        if idx > 0:
            return name[:idx]
    return ''


rows = []
for distro in installed:
    if wanted and distro != wanted:
        continue
    sf = os.path.join(runtime_root, 'state', distro, 'sessions', 'current.json')
    mf = os.path.join(runtime_root, 'state', distro, 'mounts', 'current.log')
    state = os.path.join(runtime_root, 'state', distro, 'state.json')
    rootfs_base = os.path.join(runtime_root, 'rootfs', distro)
    sessions_file_entries = 0
    active_sessions = 0
    stale_sessions = 0
    mount_log_entries = 0
    active_mounts = 0
    rootfs_mounts = 0
    release = ''
    incomplete = False

    if os.path.exists(sf):
        try:
            with open(sf, 'r', encoding='utf-8') as fh:
                data = json.load(fh)
            if isinstance(data, list):
                sessions_file_entries = len(data)
                for row in data:
                    pid = row.get('pid')
                    if isinstance(pid, int) and pid > 0 and pid_is_live(pid):
                        active_sessions += 1
                    else:
                        stale_sessions += 1
        except Exception:
            sessions_file_entries = 0
            active_sessions = 0
            stale_sessions = 0

    mount_targets = []
    mount_kinds = {}
    if os.path.exists(mf):
        try:
            with open(mf, 'r', encoding='utf-8') as fh:
                for line in fh:
                    line = line.strip()
                    if not line:
                        continue
                    parts = line.split('\t')
                    if len(parts) < 2:
                        continue
                    target = parts[1].strip()
                    if target:
                        mount_targets.append(target)
                        mount_kinds[target] = parts[2].strip() if len(parts) >= 3 else ''
        except Exception:
            mount_targets = []
            mount_kinds = {}
    mount_log_entries = len(mount_targets)
    active_mounts = sum(1 for target in mount_targets if target in mount_points)
    stale_mounts = max(0, mount_log_entries - active_mounts)

    if os.path.exists(state):
        try:
            with open(state, 'r', encoding='utf-8') as fh:
                st = json.load(fh)
            release = str(st.get('release', ''))
            incomplete = bool(st.get('incomplete', False))
        except Exception:
            pass
    logged_targets = set(mount_targets)
    bind_targets = {target for target in mount_targets if mount_kinds.get(target) == 'bind'}
    rootfs_mounts = filtered_rootfs_mount_count(mount_points, rootfs_base, logged_targets, bind_targets)

    safe_to_remove = (active_sessions == 0 and active_mounts == 0 and rootfs_mounts == 0)
    row = {
        'distro': distro,
        'release': release,
        'sessions': active_sessions,
        'mount_entries': active_mounts,
        'rootfs_mounts': rootfs_mounts,
        'safe_to_remove': safe_to_remove,
        'incomplete': incomplete,
    }
    if include_live:
        row['live'] = {
            'sessions_file_entries': sessions_file_entries,
            'active_sessions': active_sessions,
            'stale_session_entries': stale_sessions,
            'mount_log_entries': mount_log_entries,
            'active_mounts': active_mounts,
            'stale_mount_log_entries': stale_mounts,
            'rootfs_mounts': rootfs_mounts,
        }
    rows.append(row)

cache_size = 0
if cache_dir and os.path.isdir(cache_dir):
    for root, _, files in os.walk(cache_dir):
        for f in files:
            p = os.path.join(root, f)
            try:
                cache_size += os.path.getsize(p)
            except OSError:
                pass

backup_index = {}
if backups_dir and os.path.isdir(backups_dir):
    for name in sorted(os.listdir(backups_dir), reverse=True):
        if not re.search(r'\.tar(\.zst|\.xz)?$', name):
            continue
        distro = parse_backup_distro(name)
        if not distro:
            continue
        backup_index.setdefault(distro, []).append(os.path.join(backups_dir, name))

print(json.dumps({
    'runtime_root': runtime_root,
    'installed_count': len(rows),
    'distros': rows,
    'cache_bytes': cache_size,
    'backup_index': backup_index,
}, indent=2))
PY
    rm -f -- "$installed_file"
    return 0
  fi

  printf 'Aurora status\n'
  printf 'Runtime root: %s\n\n' "$CHROOT_RUNTIME_ROOT"
  printf '%-14s %-10s %-8s %-8s %-11s %-10s %-10s\n' "distro" "release" "sessions" "mounts" "rootfs_mnts" "safe_rm" "incomplete"
  printf '%-14s %-10s %-8s %-8s %-11s %-10s %-10s\n' "------" "-------" "--------" "------" "-----------" "-------" "----------"

  local distro
  local details_found=0
  local details_buffer=""
  while IFS= read -r distro; do
    [[ -n "$distro" ]] || continue
    if [[ -n "$target_distro" && "$target_distro" != "$distro" ]]; then
      continue
    fi

    local sessions mounts rootfs_mounts release incomplete safe_remove
    sessions="$(chroot_session_count "$distro" 2>/dev/null || echo 0)"
    mounts="$(chroot_mount_count_for_distro "$distro")"
    rootfs_mounts="$(chroot_mount_count_under_rootfs "$distro" 2>/dev/null || echo 0)"
    release="$(chroot_get_distro_flag "$distro" release 2>/dev/null || true)"
    incomplete="$(chroot_get_distro_flag "$distro" incomplete 2>/dev/null || echo false)"
    safe_remove="no"
    if (( sessions == 0 && mounts == 0 && rootfs_mounts == 0 )); then
      safe_remove="yes"
    fi

    printf '%-14s %-10s %-8s %-8s %-11s %-10s %-10s\n' \
      "$distro" "${release:-n/a}" "$sessions" "$mounts" "$rootfs_mounts" "$safe_remove" "$incomplete"

    local detail_lines detail_idx detail_line sid pid mode started state cmd
    detail_lines="$(chroot_session_list_details_tsv "$distro" 2>/dev/null || true)"
    if [[ -n "$detail_lines" ]]; then
      details_found=1
      details_buffer+="[$distro]"$'\n'
      detail_idx=1
      while IFS= read -r detail_line; do
        [[ -n "$detail_line" ]] || continue
        IFS=$'\t' read -r sid pid mode started state cmd <<<"$detail_line"
        local detail_row
        printf -v detail_row '  %2d) %-28s pid=%-8s state=%-18s mode=%-8s started=%-25s cmd=%s\n' \
          "$detail_idx" "${sid:-"-"}" "${pid:-"-"}" "${state:-"-"}" "${mode:-"-"}" "${started:-"-"}" "${cmd:-"-"}"
        details_buffer+="$detail_row"
        detail_idx=$((detail_idx + 1))
      done <<<"$detail_lines"
      details_buffer+=$'\n'
    fi
  done <<<"$installed_list"

  local device_tz
  device_tz="$(chroot_device_timezone_name 2>/dev/null || printf 'UTC\n')"
  printf '\nSession details (local time: %s):\n' "$device_tz"
  if (( details_found == 1 )); then
    printf '%s' "$details_buffer"
  else
    printf '  (no active recorded sessions)\n'
  fi
}
