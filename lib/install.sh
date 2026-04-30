#!/usr/bin/env bash

chroot_install_archive_suffix_from_url() {
  local url="$1"
  local path base suffix=""

  path="${url%%\?*}"
  path="${path%%\#*}"
  base="${path##*/}"
  base="${base,,}"

  case "$base" in
    *.tar) suffix=".tar" ;;
    *.tar.*) suffix=".tar.${base#*.tar.}" ;;
    *.tgz|*.tbz|*.tbz2|*.txz|*.tzst|*.tlz|*.tlzma) suffix=".${base##*.}" ;;
    *) suffix=".tar" ;;
  esac

  printf '%s\n' "$suffix"
}

chroot_install_is_supported_archive_name() {
  local name="${1##*/}"
  name="${name,,}"
  case "$name" in
    *.tar|*.tar.*|*.tgz|*.tbz|*.tbz2|*.txz|*.tzst|*.tlz|*.tlzma) return 0 ;;
  esac
  return 1
}

chroot_install_tarball_for_entry() {
  local entry_json="$1"

  local distro release install_target cache_key url sha compression size_bytes size_text cache_name out_file retries timeout archive_suffix
  distro="$(chroot_manifest_entry_field "$entry_json" id)"
  release="$(chroot_manifest_entry_field "$entry_json" release)"
  install_target="$(chroot_manifest_entry_field "$entry_json" install_target)"
  url="$(chroot_manifest_entry_field "$entry_json" rootfs_url)"
  sha="$(chroot_manifest_entry_field "$entry_json" sha256)"
  compression="$(chroot_manifest_entry_field "$entry_json" compression)"
  size_bytes="$(chroot_manifest_entry_field "$entry_json" size_bytes)"

  [[ -n "$distro" && -n "$url" && -n "$sha" ]] || chroot_die "invalid manifest entry"
  [[ "$size_bytes" =~ ^[0-9]+$ ]] || size_bytes=0
  if (( size_bytes <= 0 )); then
    size_bytes="$(chroot_manifest_remote_size_bytes "$url" 15 2>/dev/null || printf '0')"
    [[ "$size_bytes" =~ ^[0-9]+$ ]] || size_bytes=0
  fi
  size_text="$(chroot_human_bytes "$size_bytes")"

  cache_key="$release"
  if [[ -n "$install_target" && "$install_target" != "$release" ]]; then
    cache_key="$install_target"
  fi
  cache_name="${distro}-${cache_key}"
  archive_suffix="$(chroot_install_archive_suffix_from_url "$url")"
  out_file="$CHROOT_CACHE_DIR/${cache_name}${archive_suffix}"

  local got
  if [[ -f "$out_file" ]]; then
    got="$(chroot_sha256_file "$out_file")"
    if [[ "$got" != "$sha" ]]; then
      chroot_warn "Cached tarball checksum mismatch; removing stale cache: $out_file"
      rm -f -- "$out_file"
    fi
  fi

  if [[ ! -f "$out_file" ]]; then
    retries="$(chroot_setting_get download_retries)"
    timeout="$(chroot_setting_get download_timeout_sec)"
    [[ -n "$retries" ]] || retries="$CHROOT_DOWNLOAD_RETRIES_DEFAULT"
    [[ -n "$timeout" ]] || timeout="$CHROOT_DOWNLOAD_TIMEOUT_SEC_DEFAULT"

    if [[ "$size_text" != "unknown" ]]; then
      chroot_info "Downloading $url (size: $size_text)" >&2
    else
      chroot_info "Downloading $url" >&2
    fi
    chroot_download_with_retry "$url" "$out_file" "$retries" "$timeout" "$size_bytes" || chroot_die "download failed: $url"
  else
    if [[ "$size_text" != "unknown" ]]; then
      chroot_info "Using cached file: $out_file (size: $size_text)" >&2
    else
      chroot_info "Using cached file: $out_file" >&2
    fi
  fi

  got="$(chroot_sha256_file "$out_file")"
  if [[ "$got" != "$sha" ]]; then
    chroot_warn "Downloaded tarball checksum mismatch; retrying once: $out_file"
    rm -f -- "$out_file"

    retries="$(chroot_setting_get download_retries)"
    timeout="$(chroot_setting_get download_timeout_sec)"
    [[ -n "$retries" ]] || retries="$CHROOT_DOWNLOAD_RETRIES_DEFAULT"
    [[ -n "$timeout" ]] || timeout="$CHROOT_DOWNLOAD_TIMEOUT_SEC_DEFAULT"

    chroot_download_with_retry "$url" "$out_file" "$retries" "$timeout" "$size_bytes" || chroot_die "download failed: $url"
    got="$(chroot_sha256_file "$out_file")"
    if [[ "$got" != "$sha" ]]; then
      rm -f -- "$out_file"
      chroot_die "checksum mismatch for $out_file"
    fi
  fi

  printf '%s\n' "$out_file"
}

chroot_install_extract_tarball() {
  local distro="$1"
  local tarball="$2"
  local release="$3"
  local source_desc="$4"

  local rootfs_final staging
  rootfs_final="$(chroot_distro_rootfs_dir "$distro")"
  staging="$CHROOT_ROOTFS_DIR/${distro}.staging.$(chroot_now_compact)"

  chroot_ensure_distro_dirs "$distro"

  if [[ -d "$rootfs_final" ]]; then
    chroot_warn "Distro already exists: $distro"
    chroot_confirm_typed_y "Reinstall will replace existing rootfs. Type y to continue" || chroot_die "install aborted"
  fi

  chroot_set_distro_flag "$distro" "incomplete" "true"
  chroot_set_distro_flag "$distro" "installed" "false"

  if ! chroot_validate_tar_archive "$tarball" "install tarball for $distro"; then
    chroot_log_error install "archive validation failed distro=$distro tar=$tarball"
    chroot_die "install tarball validation failed"
  fi

  chroot_run_root mkdir -p "$staging"

  if ! chroot_run_root "$CHROOT_TAR_BIN" --numeric-owner -xf "$tarball" -C "$staging"; then
    chroot_run_root rm -rf -- "$staging"
    chroot_log_error install "extract failed distro=$distro tar=$tarball"
    chroot_die "extract failed"
  fi

  if [[ -d "$rootfs_final" ]]; then
    chroot_safe_rm_rf "$rootfs_final"
  fi
  chroot_run_root mv "$staging" "$rootfs_final"
  chroot_normalize_rootfs_layout "$distro" "$rootfs_final"

  chroot_set_distro_flag "$distro" "installed" "true"
  chroot_set_distro_flag "$distro" "incomplete" "false"
  chroot_set_distro_flag "$distro" "release" "$release"
  chroot_set_distro_flag "$distro" "last_install_at" "$(chroot_now_ts)"
  chroot_set_distro_flag "$distro" "source" "$source_desc"

  local alias_rc=0
  chroot_alias_upsert_distro "$distro" || alias_rc=$?
  if (( alias_rc != 0 )); then
    chroot_warn "install succeeded, but failed to update shell alias for $distro"
    chroot_log_warn install "alias update failed distro=$distro rc=$alias_rc"
  else
    chroot_alias_print_upsert_notice "$distro"
  fi

  chroot_log_info install "installed distro=$distro release=$release source=$source_desc"
  chroot_info "Installed $distro ($release)"
}

chroot_install_manifest_entry_json() {
  local entry_json="$1"
  local distro release install_target state_release tarball

  distro="$(chroot_manifest_entry_field "$entry_json" id)"
  release="$(chroot_manifest_entry_field "$entry_json" release)"
  install_target="$(chroot_manifest_entry_field "$entry_json" install_target)"
  [[ -n "$distro" && -n "$release" ]] || chroot_die "invalid manifest entry for install"
  chroot_require_distro_arg "$distro"

  state_release="$release"
  if [[ -n "$install_target" && "$install_target" != "$release" ]]; then
    state_release="$install_target"
  fi

  chroot_preflight_hard_fail

  chroot_lock_acquire "global" || chroot_die "failed global lock"
  chroot_lock_acquire "distro-$distro" || {
    chroot_lock_release "global"
    chroot_die "failed distro lock"
  }

  tarball="$(chroot_install_tarball_for_entry "$entry_json")"
  chroot_install_extract_tarball "$distro" "$tarball" "$state_release" "manifest"

  chroot_lock_release "distro-$distro"
  chroot_lock_release "global"
}

chroot_download_manifest_entry_json() {
  local entry_json="$1"
  local distro release install_target state_release tarball

  distro="$(chroot_manifest_entry_field "$entry_json" id)"
  release="$(chroot_manifest_entry_field "$entry_json" release)"
  install_target="$(chroot_manifest_entry_field "$entry_json" install_target)"
  [[ -n "$distro" && -n "$release" ]] || chroot_die "invalid manifest entry for download"
  chroot_require_distro_arg "$distro"

  state_release="$release"
  if [[ -n "$install_target" && "$install_target" != "$release" ]]; then
    state_release="$install_target"
  fi

  chroot_lock_acquire "global" || chroot_die "failed global lock"
  chroot_lock_acquire "distro-$distro" || {
    chroot_lock_release "global"
    chroot_die "failed distro lock"
  }

  tarball="$(chroot_install_tarball_for_entry "$entry_json")"

  chroot_lock_release "distro-$distro"
  chroot_lock_release "global"

  chroot_log_info install "downloaded distro=$distro release=$state_release source=manifest path=$tarball"
  chroot_info "Downloaded $distro ($state_release)"
  chroot_info "Cached at $tarball"
}

chroot_install_local_resolve_file() {
  local distro="$1"
  local input_path="$2"
  local candidate newest=""
  local -a matches=()

  if [[ -d "$input_path" ]]; then
    shopt -s nullglob
    for candidate in "$input_path"/"$distro"-*; do
      [[ -f "$candidate" ]] || continue
      chroot_install_is_supported_archive_name "$candidate" || continue
      matches+=("$candidate")
    done
    shopt -u nullglob

    (( ${#matches[@]} > 0 )) || chroot_die "no cached archives for $distro under $input_path"

    newest="${matches[0]}"
    for candidate in "${matches[@]:1}"; do
      if [[ "$candidate" -nt "$newest" ]]; then
        newest="$candidate"
      fi
    done

    if (( ${#matches[@]} > 1 )); then
      chroot_warn "Multiple matching archives found under $input_path; using newest file: $newest"
    else
      chroot_info "Resolved cached archive: $newest"
    fi
    printf '%s\n' "$newest"
    return 0
  fi

  printf '%s\n' "$input_path"
}

chroot_install_local_scan_json() {
  local input_path="$1"
  "$CHROOT_PYTHON_BIN" - "$input_path" "$CHROOT_MANIFEST_FILE" "$CHROOT_RUNTIME_ROOT" <<'PY'
import json
import os
import re
import sys
import time

input_path, manifest_path, runtime_root = sys.argv[1:4]
SUPPORTED_SUFFIXES = (".tgz", ".tbz", ".tbz2", ".txz", ".tzst", ".tlz", ".tlzma")


def human_bytes(num):
    try:
        value = float(num)
    except Exception:
        return "unknown"
    if value <= 0:
        return "0B"
    units = ["B", "K", "M", "G", "T", "P"]
    idx = 0
    while value >= 1024.0 and idx < len(units) - 1:
        value /= 1024.0
        idx += 1
    if idx == 0:
        return f"{int(value)}{units[idx]}"
    if value >= 10:
        return f"{value:.0f}{units[idx]}"
    return f"{value:.1f}{units[idx]}"


def archive_suffix(name):
    lowered = str(name or "").strip().lower()
    if not lowered:
        return ""
    if lowered.endswith(".tar"):
        return ".tar"
    match = re.search(r"(\.tar\.[a-z0-9]+)$", lowered)
    if match:
        return match.group(1)
    for suffix in SUPPORTED_SUFFIXES:
        if lowered.endswith(suffix):
            return suffix
    return ""


def load_catalog(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            payload = json.load(fh)
    except Exception:
        return []
    distros = payload.get("distros", [])
    if not isinstance(distros, list):
        return []
    out = []
    grouped = {}
    for row in distros:
        if not isinstance(row, dict):
            continue
        distro_id = str(row.get("id", "") or "").strip()
        if not distro_id:
            continue
        normalized = dict(row)
        versions = normalized.get("versions", [])
        if isinstance(versions, list) and versions:
            normalized["versions"] = [dict(item) for item in versions if isinstance(item, dict)]
            out.append(normalized)
            continue

        version = {
            "install_target": str(row.get("install_target", row.get("release", "")) or ""),
            "release": str(row.get("release", "") or ""),
            "channel": str(row.get("channel", "") or ""),
            "arch": str(row.get("arch", "") or ""),
            "rootfs_url": str(row.get("rootfs_url", "") or ""),
            "sha256": str(row.get("sha256", "") or ""),
            "compression": str(row.get("compression", "") or ""),
            "source": str(row.get("source", "") or ""),
        }
        current = grouped.get(distro_id)
        if current is None:
            current = dict(row)
            current["versions"] = []
            grouped[distro_id] = current
        current["versions"].append(version)
    out.extend(grouped.values())
    return out


def split_unknown_stem(stem):
    text = str(stem or "").strip()
    if not text or "-" not in text:
        return text, ""
    prefix, suffix = text.rsplit("-", 1)
    if not prefix:
        return text, ""
    token = suffix.lower()
    looks_like_label = bool(
        re.fullmatch(
            r"(?:v?\d[\w.-]*|\d+(?:\.\d+){0,3}|rolling|stable|current|latest|release|lts|minimal|nano|full|base|slim|small|default)",
            token,
        )
    )
    if looks_like_label:
        return prefix, suffix
    return text, ""


def entry_from_path(path, catalog_rows):
    file_path = str(path or "").strip()
    if not file_path or not os.path.isfile(file_path):
        return None

    basename = os.path.basename(file_path)
    suffix = archive_suffix(basename)
    if not suffix:
        return None

    stem = basename[:-len(suffix)] if suffix else basename
    known_rows = []
    for row in catalog_rows:
        if not isinstance(row, dict):
            continue
        distro_id = str(row.get("id", "") or "").strip()
        if distro_id:
            known_rows.append((distro_id, row))
    known_rows.sort(key=lambda item: (-len(item[0]), item[0]))

    distro_id = ""
    distro_row = None
    for candidate_id, candidate_row in known_rows:
        if stem == candidate_id or stem.startswith(candidate_id + "-"):
            distro_id = candidate_id
            distro_row = candidate_row
            break

    label = ""
    if distro_id:
        prefix = distro_id + "-"
        if stem.startswith(prefix):
            label = stem[len(prefix):]
    else:
        distro_id, label = split_unknown_stem(stem)

    display_name = str(distro_row.get("name", "") or distro_id) if isinstance(distro_row, dict) else distro_id
    version_row = None
    versions = distro_row.get("versions", []) if isinstance(distro_row, dict) else []
    if not isinstance(versions, list):
        versions = []
    for row in versions:
        if not isinstance(row, dict):
            continue
        install_target = str(row.get("install_target", "") or "").strip()
        release = str(row.get("release", "") or "").strip()
        if label and (label == install_target or label == release):
            version_row = row
            break
    if version_row is None and not label and len(versions) == 1:
        version_row = versions[0]

    display_label = label
    if isinstance(version_row, dict):
        display_label = str(version_row.get("install_target", "") or version_row.get("release", "") or label).strip()

    try:
        stat_info = os.stat(file_path)
        size_bytes = max(0, int(getattr(stat_info, "st_size", 0) or 0))
        mtime = float(getattr(stat_info, "st_mtime", 0.0) or 0.0)
    except Exception:
        size_bytes = 0
        mtime = 0.0

    mtime_text = "unknown"
    if mtime > 0:
        try:
            mtime_text = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(mtime))
        except Exception:
            mtime_text = "unknown"

    compression = suffix.lstrip(".")
    if isinstance(version_row, dict):
        compression = str(version_row.get("compression", "") or compression).strip()

    return {
        "path": file_path,
        "basename": basename,
        "stem": stem,
        "distro": distro_id,
        "name": display_name or distro_id,
        "display_label": display_label,
        "size_bytes": size_bytes,
        "size_text": human_bytes(size_bytes),
        "mtime": mtime,
        "mtime_text": mtime_text,
        "compression": compression or suffix.lstrip("."),
        "archive_suffix": suffix,
        "archive_type": suffix.lstrip("."),
        "channel": str(version_row.get("channel", "") or "").strip() if isinstance(version_row, dict) else "",
        "arch": str(version_row.get("arch", "") or "").strip() if isinstance(version_row, dict) else "",
        "sha256": str(version_row.get("sha256", "") or "").strip() if isinstance(version_row, dict) else "",
        "manifest_match": bool(version_row),
        "known_distro": bool(distro_row),
    }


def payload(status="ok", message="", path_kind="missing", entries=None):
    return {
        "status": status,
        "message": message,
        "path": input_path,
        "path_kind": path_kind,
        "runtime_root": runtime_root,
        "entries": entries or [],
    }


catalog_rows = load_catalog(manifest_path)

if not input_path:
    print(json.dumps(payload(status="error", message="Tarball path is empty"), indent=2, sort_keys=True))
    raise SystemExit(0)

if not os.path.exists(input_path):
    print(json.dumps(payload(status="error", message=f"Path not found: {input_path}"), indent=2, sort_keys=True))
    raise SystemExit(0)

if os.path.isdir(input_path):
    try:
        entries = []
        with os.scandir(input_path) as scan:
            for item in scan:
                if not item.is_file():
                    continue
                entry = entry_from_path(item.path, catalog_rows)
                if entry is not None:
                    entries.append(entry)
    except Exception as exc:
        print(json.dumps(payload(status="error", message=f"Failed to scan path: {exc}", path_kind="directory"), indent=2, sort_keys=True))
        raise SystemExit(0)

    entries.sort(key=lambda row: (
        str(row.get("distro", "") or "").lower(),
        str(row.get("display_label", "") or "").lower(),
        str(row.get("basename", "") or "").lower(),
    ))
    message = f"Found {len(entries)} local archive(s)" if entries else "No installable tar archives found under this path"
    print(json.dumps(payload(status="ok", message=message, path_kind="directory", entries=entries), indent=2, sort_keys=True))
    raise SystemExit(0)

entry = entry_from_path(input_path, catalog_rows)
if entry is None:
    print(json.dumps(payload(status="error", message="Path is not a supported tar archive", path_kind="file"), indent=2, sort_keys=True))
    raise SystemExit(0)

print(json.dumps(payload(status="ok", message="Local archive loaded", path_kind="file", entries=[entry]), indent=2, sort_keys=True))
PY
}

chroot_cmd_install_local() {
  local distro="" file="" sha="" json_mode=0

  [[ $# -ge 1 ]] || chroot_die "usage: bash path/to/chroot install-local <distro> --file <path> [--sha256 <hex>] | bash path/to/chroot install-local --file <path> --json"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file)
        shift
        [[ $# -gt 0 ]] || chroot_die "--file requires value"
        file="$1"
        ;;
      --sha256)
        shift
        [[ $# -gt 0 ]] || chroot_die "--sha256 requires value"
        sha="$1"
        ;;
      --json)
        json_mode=1
        ;;
      --*)
        chroot_die "unknown install-local arg: $1"
        ;;
      *)
        if [[ -z "$distro" ]]; then
          distro="$1"
        else
          chroot_die "unknown install-local arg: $1"
        fi
        ;;
    esac
    shift
  done

  if (( json_mode == 1 )); then
    [[ -n "$file" ]] || chroot_die "--file is required with --json"
    [[ -z "$distro" ]] || chroot_die "--json scan does not accept a distro id"
    [[ -z "$sha" ]] || chroot_die "--json scan does not accept --sha256"
    chroot_install_local_scan_json "$file"
    return 0
  fi

  [[ -n "$distro" ]] || chroot_die "install-local requires distro"
  [[ -n "$file" ]] || chroot_die "--file is required"
  chroot_require_distro_arg "$distro"
  file="$(chroot_install_local_resolve_file "$distro" "$file")"
  [[ -f "$file" ]] || chroot_die "file not found: $file"

  chroot_preflight_hard_fail

  if [[ -n "$sha" ]]; then
    local got
    got="$(chroot_sha256_file "$file")"
    [[ "$got" == "$sha" ]] || chroot_die "local file checksum mismatch"
  else
    chroot_warn "No checksum provided for local install"
    chroot_confirm_typed_y "Proceed without checksum verification? Type y to continue" || chroot_die "install-local aborted"
  fi

  chroot_lock_acquire "distro-$distro" || chroot_die "failed distro lock"
  chroot_install_extract_tarball "$distro" "$file" "local" "local"
  chroot_lock_release "distro-$distro"
}
