#!/usr/bin/env bash

chroot_install_tarball_for_entry() {
  local entry_json="$1"

  local distro release url sha compression cache_name out_file retries timeout
  distro="$(chroot_manifest_entry_field "$entry_json" id)"
  release="$(chroot_manifest_entry_field "$entry_json" release)"
  url="$(chroot_manifest_entry_field "$entry_json" rootfs_url)"
  sha="$(chroot_manifest_entry_field "$entry_json" sha256)"
  compression="$(chroot_manifest_entry_field "$entry_json" compression)"

  [[ -n "$distro" && -n "$url" && -n "$sha" ]] || chroot_die "invalid manifest entry"

  cache_name="${distro}-${release}"
  if [[ "$url" == *.tar.gz ]]; then
    cache_name+=".tar.gz"
  elif [[ "$url" == *.tar.xz ]]; then
    cache_name+=".tar.xz"
  elif [[ "$url" == *.tar.zst ]]; then
    cache_name+=".tar.zst"
  else
    cache_name+=".tar"
  fi
  out_file="$CHROOT_CACHE_DIR/$cache_name"

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

    chroot_info "Downloading $url" >&2
    chroot_download_with_retry "$url" "$out_file" "$retries" "$timeout" || chroot_die "download failed: $url"
  else
    chroot_info "Using cached file: $out_file" >&2
  fi

  got="$(chroot_sha256_file "$out_file")"
  if [[ "$got" != "$sha" ]]; then
    chroot_warn "Downloaded tarball checksum mismatch; retrying once: $out_file"
    rm -f -- "$out_file"

    retries="$(chroot_setting_get download_retries)"
    timeout="$(chroot_setting_get download_timeout_sec)"
    [[ -n "$retries" ]] || retries="$CHROOT_DOWNLOAD_RETRIES_DEFAULT"
    [[ -n "$timeout" ]] || timeout="$CHROOT_DOWNLOAD_TIMEOUT_SEC_DEFAULT"

    chroot_download_with_retry "$url" "$out_file" "$retries" "$timeout" || chroot_die "download failed: $url"
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
    local alias_target_label
    alias_target_label="${CHROOT_ALIAS_LAST_TARGET_LABEL:-shell profiles}"
    chroot_info "Alias $distro added to $alias_target_label. Use '$distro' to login."
  fi

  chroot_log_info install "installed distro=$distro release=$release source=$source_desc"
  chroot_info "Installed $distro ($release)"
}

chroot_install_manifest_entry_json() {
  local entry_json="$1"
  local distro release tarball

  distro="$(chroot_manifest_entry_field "$entry_json" id)"
  release="$(chroot_manifest_entry_field "$entry_json" release)"
  [[ -n "$distro" && -n "$release" ]] || chroot_die "invalid manifest entry for install"
  chroot_require_distro_arg "$distro"

  chroot_preflight_hard_fail

  chroot_lock_acquire "global" || chroot_die "failed global lock"
  chroot_lock_acquire "distro-$distro" || {
    chroot_lock_release "global"
    chroot_die "failed distro lock"
  }

  tarball="$(chroot_install_tarball_for_entry "$entry_json")"
  chroot_install_extract_tarball "$distro" "$tarball" "$release" "manifest"

  chroot_lock_release "distro-$distro"
  chroot_lock_release "global"
}

chroot_cmd_install_local() {
  local distro file="" sha=""

  [[ $# -ge 1 ]] || chroot_die "usage: bash path/to/chroot install-local <distro> --file <path> [--sha256 <hex>]"
  distro="$1"
  shift

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
      *) chroot_die "unknown install-local arg: $1" ;;
    esac
    shift
  done

  [[ -n "$file" ]] || chroot_die "--file is required"
  [[ -f "$file" ]] || chroot_die "file not found: $file"
  chroot_require_distro_arg "$distro"

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
