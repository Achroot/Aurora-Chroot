chroot_tor_uid_source_lines() {
  local out=""
  local pkg_list="" pkg uid_line uid line printed=0

  CHROOT_TOR_UID_SOURCE=""

  if [[ -n "$CHROOT_TOR_CMD_BIN" ]]; then
    out="$("$CHROOT_TOR_CMD_BIN" package list packages -U 2>/dev/null || true)"
    if [[ "$out" == *"package:"* && ( "$out" == *"uid:"* || "$out" == *"userId="* || "$out" == *"userId:"* ) ]]; then
      CHROOT_TOR_UID_SOURCE="cmd package list packages -U"
      printf '%s\n' "$out"
      return 0
    fi
  fi

  if [[ -n "$CHROOT_TOR_PM_BIN" ]]; then
    out="$("$CHROOT_TOR_PM_BIN" list packages -U 2>/dev/null || true)"
    if [[ "$out" == *"package:"* && ( "$out" == *"uid:"* || "$out" == *"userId="* || "$out" == *"userId:"* ) ]]; then
      CHROOT_TOR_UID_SOURCE="pm list packages -U"
      printf '%s\n' "$out"
      return 0
    fi
  fi

  if [[ -r /data/system/packages.list ]] || chroot_run_root test -r /data/system/packages.list >/dev/null 2>&1; then
    out="$(chroot_tor_root_text_file /data/system/packages.list || true)"
    if [[ -n "$out" ]]; then
      CHROOT_TOR_UID_SOURCE="/data/system/packages.list"
      printf '%s\n' "$out"
      return 0
    fi
  fi

  if [[ -r /data/system/packages.xml ]] || chroot_run_root test -r /data/system/packages.xml >/dev/null 2>&1; then
    out="$(chroot_tor_root_text_file /data/system/packages.xml || true)"
    if [[ "$out" == *"<package "* && ( "$out" == *"userId="* || "$out" == *"sharedUserId="* ) ]]; then
      CHROOT_TOR_UID_SOURCE="/data/system/packages.xml"
      printf '%s\n' "$out"
      return 0
    fi
  fi

  if [[ -n "$CHROOT_TOR_DUMPSYS_BIN" ]]; then
    if [[ -n "$CHROOT_TOR_CMD_BIN" ]]; then
      pkg_list="$("$CHROOT_TOR_CMD_BIN" package list packages 2>/dev/null || true)"
    fi
    if [[ -z "$pkg_list" && -n "$CHROOT_TOR_PM_BIN" ]]; then
      pkg_list="$("$CHROOT_TOR_PM_BIN" list packages 2>/dev/null || true)"
    fi
    if [[ -n "$pkg_list" ]]; then
      CHROOT_TOR_UID_SOURCE="package+dumpsys"
      while IFS= read -r line; do
        pkg="${line#package:}"
        pkg="${pkg%% *}"
        [[ -n "$pkg" ]] || continue
        uid_line="$("$CHROOT_TOR_DUMPSYS_BIN" package "$pkg" 2>/dev/null | awk 'match($0, /userId=([0-9]+)/, m) {print m[1]; exit} match($0, /userId:([0-9]+)/, m) {print m[1]; exit}' || true)"
        uid="$(printf '%s\n' "$uid_line" | tr -dc '0-9' | awk 'NF {print; exit}')"
        [[ "$uid" =~ ^[0-9]+$ ]] || continue
        printf '%s\t%s\n' "$pkg" "$uid"
        printed=1
      done <<<"$pkg_list"
      if (( printed == 1 )); then
        return 0
      fi
    fi
  fi

  return 1
}

chroot_tor_root_text_file() {
  local path="$1"
  local tmp
  tmp="$CHROOT_TMP_DIR/tor-root-text.$$.bin"
  chroot_run_root cat "$path" >"$tmp" 2>/dev/null || {
    rm -f -- "$tmp"
    return 1
  }
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$tmp" <<'PY'
import sys

path = sys.argv[1]
with open(path, "rb") as fh:
    data = fh.read().replace(b"\x00", b"")
sys.stdout.write(data.decode("utf-8", errors="replace"))
PY
  local rc=$?
  rm -f -- "$tmp"
  return "$rc"
}

chroot_tor_package_scope_lines() {
  local scope="$1"
  local out="" flag=""

  case "$scope" in
    user) flag="-3" ;;
    system) flag="-s" ;;
    *) return 1 ;;
  esac

  if [[ -n "$CHROOT_TOR_CMD_BIN" ]]; then
    out="$("$CHROOT_TOR_CMD_BIN" package list packages "$flag" 2>/dev/null || true)"
    if [[ "$out" == *"package:"* ]]; then
      printf '%s\n' "$out"
      return 0
    fi
  fi

  if [[ -n "$CHROOT_TOR_PM_BIN" ]]; then
    out="$("$CHROOT_TOR_PM_BIN" list packages "$flag" 2>/dev/null || true)"
    if [[ "$out" == *"package:"* ]]; then
      printf '%s\n' "$out"
      return 0
    fi
  fi

  return 1
}

chroot_tor_apps_refresh() {
  local distro="$1"
  local fatal="${2:-1}"
  local raw_file out_file source_label user_scope_file system_scope_file

  chroot_tor_detect_backends 0
  chroot_tor_ensure_state_layout "$distro"
  chroot_tor_config_ensure_file "$distro"
  chroot_require_python

  raw_file="$CHROOT_TMP_DIR/tor-apps-raw.$$.txt"
  out_file="$CHROOT_TMP_DIR/tor-apps.$$.json"
  user_scope_file="$CHROOT_TMP_DIR/tor-apps-user.$$.txt"
  system_scope_file="$CHROOT_TMP_DIR/tor-apps-system.$$.txt"

  if ! chroot_tor_uid_source_lines >"$raw_file"; then
    rm -f -- "$raw_file" "$out_file" "$user_scope_file" "$system_scope_file"
    if [[ "$fatal" == "0" ]]; then
      return 1
    fi
    chroot_die "failed to discover Android app UIDs"
  fi

  source_label="${CHROOT_TOR_UID_SOURCE:-unknown}"
  : >"$user_scope_file"
  : >"$system_scope_file"
  chroot_tor_package_scope_lines user >"$user_scope_file" 2>/dev/null || true
  chroot_tor_package_scope_lines system >"$system_scope_file" 2>/dev/null || true

  "$CHROOT_PYTHON_BIN" - "$raw_file" "$out_file" "$source_label" "$(chroot_tor_config_file "$distro")" "$user_scope_file" "$system_scope_file" "$(chroot_now_ts)" <<'PY'
import hashlib
import json
import re
import sys

raw_path, out_path, source_label, config_path, user_scope_path, system_scope_path, generated_at = sys.argv[1:8]

with open(raw_path, "r", encoding="utf-8", errors="replace") as fh:
    lines = [line.rstrip("\n") for line in fh]

try:
    with open(config_path, "r", encoding="utf-8") as fh:
        config = json.load(fh)
except Exception:
    config = {}

bypass = set(str(x).strip() for x in config.get("bypass_packages", []) if str(x).strip())
packages = set()
scope_by_package = {}

def load_scope(path):
    out = set()
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            for raw in fh:
                line = raw.strip()
                if not line.startswith("package:"):
                    continue
                pkg = line.split("package:", 1)[1].split()[0].strip()
                if pkg:
                    out.add(pkg)
    except Exception:
        return set()
    return out

user_packages = load_scope(user_scope_path)
system_packages = load_scope(system_scope_path)

if source_label in {"cmd package list packages -U", "pm list packages -U"}:
    for line in lines:
        m_pkg = re.search(r"package:([^\s]+)", line)
        m_uid = re.search(r"\b(?:uid|userId)[:=](\d+)\b", line)
        if not m_pkg or not m_uid:
            continue
        pkg = m_pkg.group(1).strip()
        uid = int(m_uid.group(1))
        if uid < 10000:
            continue
        packages.add((pkg, uid))
elif source_label == "/data/system/packages.xml":
    import xml.etree.ElementTree as ET
    try:
        root = ET.fromstring("\n".join(lines))
    except Exception:
        root = None
    if root is not None:
        for elem in root.iter():
            if elem.tag != "package":
                continue
            pkg = str(elem.attrib.get("name", "")).strip()
            uid_text = str(elem.attrib.get("userId", "") or elem.attrib.get("sharedUserId", "")).strip()
            if not pkg or not uid_text.isdigit():
                continue
            uid = int(uid_text)
            if uid < 10000:
                continue
            packages.add((pkg, uid))
elif source_label == "package+dumpsys":
    for line in lines:
        if "\t" not in line:
            continue
        pkg, uid_text = line.split("\t", 1)
        pkg = pkg.strip()
        uid_text = uid_text.strip()
        if not pkg or not uid_text.isdigit():
            continue
        uid = int(uid_text)
        if uid < 10000:
            continue
        packages.add((pkg, uid))
else:
    for line in lines:
        parts = line.split()
        if len(parts) < 2:
            continue
        pkg, uid_text = parts[0], parts[1]
        try:
            uid = int(uid_text)
        except Exception:
            continue
        if uid < 10000:
            continue
        packages.add((pkg, uid))
        if len(parts) >= 2:
            marker = str(parts[-1]).strip()
            if marker == "@system":
                scope_by_package[pkg] = "system"
            elif marker:
                scope_by_package[pkg] = "user"

uid_counts = {}
package_to_uid = {}
for pkg, uid in packages:
    uid_counts[uid] = uid_counts.get(uid, 0) + 1
    package_to_uid[pkg] = uid

selected_bypass_uids = set()
for pkg in bypass:
    uid = package_to_uid.get(pkg)
    if isinstance(uid, int):
        selected_bypass_uids.add(uid)

rows = []
for pkg, uid in sorted(packages):
    if pkg in user_packages:
        scope = "user"
    elif pkg in system_packages:
        scope = "system"
    else:
        scope = scope_by_package.get(pkg, "unknown")
    uid_package_count = int(uid_counts.get(uid, 1) or 1)
    rows.append(
        {
            "package": pkg,
            "uid": uid,
            "bypassed": uid in selected_bypass_uids,
            "scope": scope,
            "shared_uid": uid_package_count > 1,
            "uid_package_count": uid_package_count,
        }
    )

payload = {
    "schema_version": 1,
    "generated_at": generated_at,
    "uid_source": source_label,
    "package_count": len(rows),
    "packages_digest": hashlib.sha256(
        "\n".join(f"{pkg}\t{uid}" for pkg, uid in sorted(packages)).encode("utf-8")
    ).hexdigest(),
    "bypass_package_count": len([row for row in rows if row["bypassed"]]),
    "user_package_count": len([row for row in rows if row.get("scope") == "user"]),
    "system_package_count": len([row for row in rows if row.get("scope") == "system"]),
    "unknown_package_count": len([row for row in rows if row.get("scope") == "unknown"]),
    "shared_uid_group_count": len([uid for uid, count in uid_counts.items() if count > 1]),
    "packages": rows,
}

with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY

  mv -f -- "$out_file" "$(chroot_tor_apps_inventory_file "$distro")"
  rm -f -- "$raw_file" "$user_scope_file" "$system_scope_file"
}

chroot_tor_apps_ensure() {
  local distro="$1"
  local apps_file
  apps_file="$(chroot_tor_apps_inventory_file "$distro")"
  if [[ ! -f "$apps_file" ]]; then
    chroot_tor_apps_refresh "$distro"
  fi
}

chroot_tor_apps_list_json() {
  local distro="$1"
  local scope_filter="${2:-all}"
  local only_bypassed="${3:-0}"
  chroot_tor_apps_refresh "$distro"
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$(chroot_tor_apps_inventory_file "$distro")" "$scope_filter" "$only_bypassed" <<'PY'
import json
import sys

apps_path, scope_filter, only_bypassed_text = sys.argv[1:4]
scope_filter = str(scope_filter or "all").strip().lower() or "all"
only_bypassed = only_bypassed_text == "1"

try:
    with open(apps_path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {}

rows = []
for row in data.get("packages", []):
    if not isinstance(row, dict):
        continue
    scope = str(row.get("scope", "unknown") or "unknown").strip().lower() or "unknown"
    bypassed = bool(row.get("bypassed"))
    if scope_filter in {"user", "system"} and scope != scope_filter:
        continue
    if only_bypassed and not bypassed:
        continue
    rows.append(row)

payload = dict(data) if isinstance(data, dict) else {}
payload["package_count"] = len(rows)
payload["bypass_package_count"] = len([row for row in rows if bool(row.get("bypassed"))])
payload["user_package_count"] = len([row for row in rows if str(row.get("scope", "")).lower() == "user"])
payload["system_package_count"] = len([row for row in rows if str(row.get("scope", "")).lower() == "system"])
payload["unknown_package_count"] = len([row for row in rows if str(row.get("scope", "")).lower() == "unknown"])
payload["shared_uid_group_count"] = len({int(row.get("uid")) for row in rows if row.get("shared_uid") and str(row.get("uid", "")).isdigit()})
payload["packages"] = rows
print(json.dumps(payload, indent=2, sort_keys=True))
PY
}

chroot_tor_apps_search_json() {
  local distro="$1"
  local query="${2:-}"
  local only_bypassed="${3:-0}"
  local scope_filter="${4:-all}"

  chroot_tor_apps_refresh "$distro"
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$(chroot_tor_apps_inventory_file "$distro")" "$query" "$only_bypassed" "$scope_filter" <<'PY'
import json
import sys

apps_path, query, only_bypassed_text, scope_filter = sys.argv[1:5]
only_bypassed = only_bypassed_text == "1"
query = str(query or "").strip().lower()
scope_filter = str(scope_filter or "all").strip().lower() or "all"

try:
    with open(apps_path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {}

rows = []
for row in data.get("packages", []):
    if not isinstance(row, dict):
        continue
    package = str(row.get("package", "")).strip()
    if not package:
        continue
    bypassed = bool(row.get("bypassed"))
    if only_bypassed and not bypassed:
        continue
    scope = str(row.get("scope", "unknown") or "unknown").strip().lower() or "unknown"
    if scope_filter in {"user", "system"} and scope != scope_filter:
        continue
    if query and query not in package.lower():
        continue
    rows.append(
        {
            "package": package,
            "uid": row.get("uid"),
            "bypassed": bypassed,
            "scope": scope,
            "shared_uid": bool(row.get("shared_uid")),
            "uid_package_count": row.get("uid_package_count"),
        }
    )
print(json.dumps(rows, indent=2, sort_keys=True))
PY
}

chroot_tor_app_select_match() {
  local json_payload="$1"
  local prompt="${2:-Select app}"

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$json_payload" "$prompt" <<'PY'
import json
import sys

rows = json.loads(sys.argv[1])
prompt = sys.argv[2]

if not rows:
    sys.exit(2)

for idx, row in enumerate(rows, start=1):
    package = str(row.get("package", "") or "")
    uid = row.get("uid")
    bypassed = "bypass" if row.get("bypassed") else "tor"
    print(f"  {idx:2d}) {package:<40} uid={uid} mode={bypassed}", file=sys.stderr)

while True:
    try:
        pick = input(f"{prompt} (1-{len(rows)}, q=cancel): ")
    except EOFError:
        sys.exit(1)
    if pick in {"", "q", "Q"}:
        sys.exit(1)
    if pick.isdigit():
        idx = int(pick)
        if 1 <= idx <= len(rows):
            print(str(rows[idx - 1].get("package", "")))
            sys.exit(0)
    print("Invalid selection.", file=sys.stderr)
PY
}

chroot_tor_app_resolve_query() {
  local distro="$1"
  local query="$2"
  local only_bypassed="${3:-0}"
  local scope_filter="${4:-all}"
  local json_payload count exact_match package

  [[ -n "$query" ]] || chroot_die "app query is required"
  json_payload="$(chroot_tor_apps_search_json "$distro" "$query" "$only_bypassed" "$scope_filter")"

  chroot_require_python
  exact_match="$("$CHROOT_PYTHON_BIN" - "$json_payload" "$query" <<'PY'
import json
import sys

rows = json.loads(sys.argv[1])
query = str(sys.argv[2]).strip().lower()
for row in rows:
    package = str(row.get("package", "")).strip()
    if package.lower() == query:
        print(package)
        sys.exit(0)
sys.exit(1)
PY
  )" || true
  if [[ -n "$exact_match" ]]; then
    printf '%s\n' "$exact_match"
    return 0
  fi

  count="$(chroot_require_python >/dev/null 2>&1; "$CHROOT_PYTHON_BIN" - "$json_payload" <<'PY'
import json
import sys
rows = json.loads(sys.argv[1])
print(len(rows))
PY
)"
  [[ "$count" =~ ^[0-9]+$ ]] || count=0
  if (( count == 1 )); then
    package="$(chroot_require_python >/dev/null 2>&1; "$CHROOT_PYTHON_BIN" - "$json_payload" <<'PY'
import json
import sys
rows = json.loads(sys.argv[1])
print(str(rows[0].get("package", "")) if rows else "")
PY
)"
    [[ -n "$package" ]] || chroot_die "failed to resolve app query: $query"
    printf '%s\n' "$package"
    return 0
  fi
  if (( count == 0 )); then
    chroot_die "no app matches query: $query"
  fi

  if [[ ! -t 0 ]]; then
    chroot_die "multiple apps match '$query'; run 'tor $distro apps search $query' first or use an exact package name"
  fi

  chroot_tor_app_select_match "$json_payload" "Select app"
}

chroot_tor_app_uid_group_packages() {
  local distro="$1"
  local package_name="$2"

  [[ -n "$package_name" ]] || chroot_die "package name is required"
  chroot_tor_apps_refresh "$distro"
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$(chroot_tor_apps_inventory_file "$distro")" "$package_name" <<'PY'
import json
import sys

apps_path, package_name = sys.argv[1:3]

try:
    with open(apps_path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {}

rows = [row for row in data.get("packages", []) if isinstance(row, dict)]
target_uid = None
for row in rows:
    package = str(row.get("package", "")).strip()
    if package == package_name:
        try:
            target_uid = int(row.get("uid"))
        except Exception:
            target_uid = None
        break

if target_uid is None:
    raise SystemExit(f"failed to resolve app uid group for {package_name}")

packages = sorted(
    str(row.get("package", "")).strip()
    for row in rows
    if str(row.get("package", "")).strip() and str(row.get("uid", "")).strip().isdigit() and int(row.get("uid")) == target_uid
)
for package in packages:
    print(package)
PY
}

chroot_tor_targets_generate() {
  local distro="$1"
  local include_host_uid="${2:-0}"
  local use_saved_bypass="${3:-0}"
  local out_file host_uid

  chroot_tor_apps_ensure "$distro"
  out_file="$CHROOT_TMP_DIR/tor-targets.$$.json"
  host_uid="$(chroot_host_user_uid 2>/dev/null || true)"

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$(chroot_tor_apps_inventory_file "$distro")" "$(chroot_tor_config_file "$distro")" "$out_file" "$host_uid" "$include_host_uid" "$use_saved_bypass" "$(chroot_now_ts)" <<'PY'
import json
import sys

apps_path, config_path, out_path, host_uid_text, include_host_text, use_saved_bypass_text, generated_at = sys.argv[1:8]
try:
    with open(apps_path, "r", encoding="utf-8") as fh:
        apps = json.load(fh)
except Exception:
    apps = {}
try:
    with open(config_path, "r", encoding="utf-8") as fh:
        config = json.load(fh)
except Exception:
    config = {}

host_uid = None
try:
    host_uid = int(host_uid_text)
except Exception:
    host_uid = None
include_host = include_host_text == "1"
use_saved_bypass = use_saved_bypass_text == "1"

selected_bypass_packages = set(str(x).strip() for x in config.get("bypass_packages", []) if str(x).strip())
rows = []
app_uids = set()
target_uids = set()
bypass_uids = set()
selected_bypass_uids = set()

for row in apps.get("packages", []):
    if not isinstance(row, dict):
        continue
    package = str(row.get("package", "")).strip()
    if package not in selected_bypass_packages:
        continue
    try:
        uid = int(row.get("uid"))
    except Exception:
        continue
    if uid > 0:
        selected_bypass_uids.add(uid)

for row in apps.get("packages", []):
    if not isinstance(row, dict):
        continue
    package = str(row.get("package", "")).strip()
    try:
        uid = int(row.get("uid"))
    except Exception:
        continue
    if uid <= 0:
        continue
    bypassed = uid in selected_bypass_uids
    rows.append({"package": package, "uid": uid, "bypassed": bypassed})
    app_uids.add(uid)
    if bypassed:
        bypass_uids.add(uid)
    if use_saved_bypass and bypassed:
        continue
    target_uids.add(uid)

if include_host and isinstance(host_uid, int) and host_uid > 0:
    target_uids.add(host_uid)

ordered_target_uids = sorted(target_uids)
uid_ranges = []
for uid in ordered_target_uids:
    if not uid_ranges or uid != uid_ranges[-1]["end"] + 1:
        uid_ranges.append({"start": uid, "end": uid})
    else:
        uid_ranges[-1]["end"] = uid

payload = {
    "schema_version": 1,
    "generated_at": generated_at,
    "uid_source": str(apps.get("uid_source", "") or ""),
    "source_apps_generated_at": str(apps.get("generated_at", "") or ""),
    "source_package_count": int(apps.get("package_count", 0) or 0),
    "source_packages_digest": str(apps.get("packages_digest", "") or ""),
    "packages": rows,
    "app_uids": sorted(app_uids),
    "target_uids": ordered_target_uids,
    "uid_ranges": uid_ranges,
    "termux_uid": host_uid,
    "termux_uid_included": bool(include_host and isinstance(host_uid, int) and host_uid in target_uids),
    "root_uid_included": False,
    "app_uid_count": len(app_uids),
    "target_uid_count": len(ordered_target_uids),
    "uid_range_count": len(uid_ranges),
    "bypass_package_count": len([row for row in rows if row["bypassed"]]),
    "bypass_uid_count": len(selected_bypass_uids),
    "configured_bypass_applied": use_saved_bypass,
}

with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY

  mv -f -- "$out_file" "$(chroot_tor_targets_file "$distro")"

  local app_count
  app_count="$(chroot_tor_targets_summary_tsv "$distro" | awk -F'\t' '{print $1}')"
  [[ "$app_count" =~ ^[0-9]+$ ]] || app_count=0
  (( app_count > 0 )) || chroot_die "tor target generation found no Android app UIDs"
}

chroot_tor_targets_summary_tsv() {
  local distro="$1"
  local targets_file
  targets_file="$(chroot_tor_targets_file "$distro")"
  [[ -f "$targets_file" ]] || {
    printf '0\t0\t0\t0\t\t0\n'
    return 0
  }

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$targets_file" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {}

print(
    "\t".join(
        [
            str(int(data.get("app_uid_count", 0) or 0)),
            str(int(data.get("target_uid_count", 0) or 0)),
            str(int(data.get("uid_range_count", 0) or 0)),
            "1" if data.get("termux_uid_included") else "0",
            str(data.get("uid_source", "") or ""),
            str(int(data.get("bypass_package_count", 0) or 0)),
        ]
    )
)
PY
}

chroot_tor_target_uids() {
  local distro="$1"
  local targets_file
  targets_file="$(chroot_tor_targets_file "$distro")"
  [[ -f "$targets_file" ]] || return 0

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$targets_file" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {}

for uid in data.get("target_uids", []):
    try:
        parsed = int(uid)
    except Exception:
        continue
    if parsed > 0:
        print(parsed)
PY
}

chroot_tor_target_uid_specs() {
  local distro="$1"
  local targets_file
  targets_file="$(chroot_tor_targets_file "$distro")"
  [[ -f "$targets_file" ]] || return 0

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$targets_file" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {}

printed = False
for row in data.get("uid_ranges", []):
    if not isinstance(row, dict):
        continue
    try:
        start = int(row.get("start"))
        end = int(row.get("end"))
    except Exception:
        continue
    if start <= 0 or end < start:
        continue
    print(str(start) if start == end else f"{start}-{end}")
    printed = True

if printed:
    sys.exit(0)

for uid in data.get("target_uids", []):
    try:
        parsed = int(uid)
    except Exception:
        continue
    if parsed > 0:
        print(parsed)
PY
}

chroot_tor_targets_invalidate() {
  local distro="$1"
  rm -f -- "$(chroot_tor_targets_file "$distro")"
}
