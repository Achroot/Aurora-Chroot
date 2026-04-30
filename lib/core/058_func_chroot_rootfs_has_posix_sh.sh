chroot_rootfs_has_posix_sh() {
  local dir="$1"
  chroot_rootfs_resolve_executable_path "$dir" "/bin/sh" >/dev/null 2>&1 || chroot_rootfs_resolve_executable_path "$dir" "/usr/bin/sh" >/dev/null 2>&1
}

chroot_rootfs_resolve_executable_path() {
  local rootfs="$1"
  local internal_path="$2"

  [[ -n "$rootfs" && -n "$internal_path" ]] || return 1
  chroot_require_python
  chroot_run_root "$CHROOT_PYTHON_BIN" -c '
import os
import posixpath
import stat
import sys

rootfs = os.path.realpath(sys.argv[1])
requested = sys.argv[2]
max_depth = 40

if not rootfs or not os.path.isdir(rootfs):
    raise SystemExit(1)


def clean_internal(path):
    text = str(path or "")
    if not text.startswith("/"):
        text = "/" + text
    return posixpath.normpath(text)


def path_parts(path):
    path = clean_internal(path)
    return [part for part in path.split("/") if part and part != "."]


def combine_relative(parent_parts, target):
    parts = list(parent_parts)
    for part in str(target or "").split("/"):
        if not part or part == ".":
            continue
        if part == "..":
            if not parts:
                return None
            parts.pop()
            continue
        parts.append(part)
    return "/" + "/".join(parts)


def host_path(parts):
    candidate = os.path.abspath(os.path.join(rootfs, *parts))
    root_prefix = rootfs.rstrip(os.sep) + os.sep
    if candidate != rootfs and not candidate.startswith(root_prefix):
        return None
    return candidate


pending = path_parts(requested)
resolved = []
seen_links = set()
depth = 0

while pending:
    part = pending.pop(0)
    if part == "..":
        if not resolved:
            raise SystemExit(1)
        resolved.pop()
        continue

    candidate_parts = resolved + [part]
    candidate = host_path(candidate_parts)
    if candidate is None:
        raise SystemExit(1)
    try:
        st = os.lstat(candidate)
    except OSError:
        raise SystemExit(1)

    if stat.S_ISLNK(st.st_mode):
        depth += 1
        if depth > max_depth:
            raise SystemExit(1)
        link_key = "/" + "/".join(candidate_parts)
        if link_key in seen_links:
            raise SystemExit(1)
        seen_links.add(link_key)
        try:
            target = os.readlink(candidate)
        except OSError:
            raise SystemExit(1)
        if target.startswith("/"):
            next_internal = clean_internal(target)
        else:
            next_internal = combine_relative(resolved, target)
            if next_internal is None:
                raise SystemExit(1)
        pending = path_parts(next_internal) + pending
        resolved = []
        continue

    resolved.append(part)

final_path = host_path(resolved)
if final_path is None:
    raise SystemExit(1)
try:
    st = os.stat(final_path)
except OSError:
    raise SystemExit(1)

if not stat.S_ISREG(st.st_mode):
    raise SystemExit(1)
if st.st_mode & 0o111 == 0:
    raise SystemExit(1)

print(final_path)
' "$rootfs" "$internal_path"
}

chroot_rootfs_shell_selftest_rows() {
  local tmp_dir rootfs actual expected status

  tmp_dir="$(mktemp -d "${CHROOT_TMP_DIR:-/tmp}/rootfs-shell-selftest.XXXXXX" 2>/dev/null || mktemp -d "/tmp/rootfs-shell-selftest.XXXXXX")"
  rootfs="$tmp_dir/rootfs"

  mkdir -p "$rootfs/bin"
  printf '#!/bin/sh\nexit 0\n' >"$rootfs/bin/sh"
  chmod 755 "$rootfs/bin/sh"
  if chroot_rootfs_has_posix_sh "$rootfs"; then
    actual="true"
  else
    actual="false"
  fi
  expected="true"
  status="pass"
  [[ "$actual" == "$expected" ]] || status="fail"
  printf '%s\t%s\t%s\t%s\n' "regular_bin_sh" "$expected" "$actual" "$status"
  rm -rf -- "$rootfs"

  mkdir -p "$rootfs/bin"
  printf '#!/bin/sh\nexit 0\n' >"$rootfs/bin/busybox"
  chmod 755 "$rootfs/bin/busybox"
  ln -s /bin/busybox "$rootfs/bin/sh"
  if chroot_rootfs_has_posix_sh "$rootfs"; then
    actual="true"
  else
    actual="false"
  fi
  expected="true"
  status="pass"
  [[ "$actual" == "$expected" ]] || status="fail"
  printf '%s\t%s\t%s\t%s\n' "absolute_symlink_bin_sh" "$expected" "$actual" "$status"
  rm -rf -- "$rootfs"

  mkdir -p "$rootfs/bin" "$rootfs/usr/bin"
  printf '#!/bin/sh\nexit 0\n' >"$rootfs/bin/busybox"
  chmod 755 "$rootfs/bin/busybox"
  ln -s ../../bin/busybox "$rootfs/usr/bin/sh"
  if chroot_rootfs_has_posix_sh "$rootfs"; then
    actual="true"
  else
    actual="false"
  fi
  expected="true"
  status="pass"
  [[ "$actual" == "$expected" ]] || status="fail"
  printf '%s\t%s\t%s\t%s\n' "relative_symlink_usr_bin_sh" "$expected" "$actual" "$status"
  rm -rf -- "$rootfs"

  mkdir -p "$rootfs/bin"
  ln -s /bin/missing "$rootfs/bin/sh"
  if chroot_rootfs_has_posix_sh "$rootfs"; then
    actual="true"
  else
    actual="false"
  fi
  expected="false"
  status="pass"
  [[ "$actual" == "$expected" ]] || status="fail"
  printf '%s\t%s\t%s\t%s\n' "broken_symlink_bin_sh" "$expected" "$actual" "$status"
  rm -rf -- "$rootfs"

  mkdir -p "$rootfs/bin"
  ln -s /bin/sh2 "$rootfs/bin/sh"
  ln -s /bin/sh "$rootfs/bin/sh2"
  if chroot_rootfs_has_posix_sh "$rootfs"; then
    actual="true"
  else
    actual="false"
  fi
  expected="false"
  status="pass"
  [[ "$actual" == "$expected" ]] || status="fail"
  printf '%s\t%s\t%s\t%s\n' "symlink_loop_bin_sh" "$expected" "$actual" "$status"
  rm -rf -- "$rootfs"

  mkdir -p "$rootfs/bin"
  ln -s ../../outside "$rootfs/bin/sh"
  if chroot_rootfs_has_posix_sh "$rootfs"; then
    actual="true"
  else
    actual="false"
  fi
  expected="false"
  status="pass"
  [[ "$actual" == "$expected" ]] || status="fail"
  printf '%s\t%s\t%s\t%s\n' "escaping_relative_symlink_bin_sh" "$expected" "$actual" "$status"
  rm -rf -- "$tmp_dir"
}
