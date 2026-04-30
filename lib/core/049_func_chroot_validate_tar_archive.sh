chroot_validate_tar_archive() {
  local tar_file="$1"
  local label="${2:-archive}"

  [[ -f "$tar_file" ]] || {
    chroot_err "$label not found: $tar_file"
    return 1
  }

  chroot_require_python
  if "$CHROOT_PYTHON_BIN" - "$tar_file" "$label" <<'PY'
import pathlib
import posixpath
import sys
import tarfile

tar_path, label = sys.argv[1:3]

def safe_entry_name(name: str) -> bool:
    if not name:
        return False
    p = pathlib.PurePosixPath(name)
    if p.is_absolute():
        return False
    for part in p.parts:
        if part in ("", ".."):
            return False
    return True

def safe_link_target(member_name: str, target: str, is_hardlink: bool) -> bool:
    if not target:
        return False
    if is_hardlink and target.startswith("/"):
        return False
    if not target.startswith("/"):
        joined = posixpath.normpath(posixpath.join(posixpath.dirname(member_name), target))
        if joined == ".." or joined.startswith("../"):
            return False
    return True

def allowed_device_entry(name: str) -> bool:
    normalized = posixpath.normpath(str(name or ""))
    parts = pathlib.PurePosixPath(normalized).parts
    if len(parts) >= 2 and parts[0] == "dev":
        return True
    if len(parts) >= 3 and parts[1] == "dev":
        return True
    return False

try:
    with tarfile.open(tar_path, mode="r:*") as tf:
        for member in tf.getmembers():
            name = member.name
            if name in (".", "./"):
                continue
            if not safe_entry_name(name):
                print(f"{label} contains unsafe path entry: {name}", file=sys.stderr)
                sys.exit(1)
            if member.isdev():
                if not allowed_device_entry(name):
                    print(f"{label} contains unsupported device entry: {name}", file=sys.stderr)
                    sys.exit(1)
            if member.issym() or member.islnk():
                target = member.linkname or ""
                if not safe_link_target(name, target, member.islnk()):
                    print(f"{label} contains unsafe link target: {name} -> {target}", file=sys.stderr)
                    sys.exit(1)
except tarfile.ReadError:
    # If Python's tar reader cannot handle this format here,
    # let the caller fall back to the more conservative tar CLI check.
    sys.exit(10)

print("ok")
PY
  then
    return 0
  fi

  local py_rc=$?
  if (( py_rc != 10 )); then
    return 1
  fi

  # Fall back to tar listing here to re-check path safety and reject risky links.
  if ! "$CHROOT_TAR_BIN" -tf "$tar_file" | "$CHROOT_PYTHON_BIN" - "$label" <<'PY'
import pathlib
import sys

label = sys.argv[1]

for raw in sys.stdin:
    name = raw.rstrip("\n")
    if name in ("", ".", "./"):
        continue
    p = pathlib.PurePosixPath(name)
    if p.is_absolute():
        print(f"{label} contains unsafe path entry: {name}", file=sys.stderr)
        sys.exit(1)
    for part in p.parts:
        if part in ("", ".."):
            print(f"{label} contains unsafe path entry: {name}", file=sys.stderr)
            sys.exit(1)
print("ok")
PY
  then
    return 1
  fi

  local line target
  while IFS= read -r line; do
    case "$line" in
      *" -> "*)
        target="${line##* -> }"
        if [[ -z "$target" || "$target" == .. || "$target" == ../* || "$target" == */../* ]]; then
          chroot_err "$label contains unsafe link target in fallback validation: $target"
          return 1
        fi
        ;;
      *" link to "*)
        target="${line##* link to }"
        if [[ -z "$target" || "$target" == /* || "$target" == .. || "$target" == ../* || "$target" == */../* ]]; then
          chroot_err "$label contains unsafe hardlink target in fallback validation: $target"
          return 1
        fi
        ;;
    esac
  done < <("$CHROOT_TAR_BIN" -tvf "$tar_file" 2>/dev/null || true)

  chroot_warn "limited archive validation used for $label (python metadata parser unavailable)"
  return 0
}
