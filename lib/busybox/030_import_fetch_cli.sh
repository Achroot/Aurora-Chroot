#!/usr/bin/env bash

chroot_busybox_detect_android_abi() {
  local getprop_bin=""
  if [[ -n "${CHROOT_BUSYBOX_TEST_ANDROID_ABI:-}" ]]; then
    printf '%s\n' "$CHROOT_BUSYBOX_TEST_ANDROID_ABI"
    return 0
  fi
  getprop_bin="$(command -v getprop 2>/dev/null || true)"
  if [[ -z "$getprop_bin" && -x "${CHROOT_SYSTEM_BIN_DEFAULT:-/system/bin}/getprop" ]]; then
    getprop_bin="${CHROOT_SYSTEM_BIN_DEFAULT:-/system/bin}/getprop"
  fi
  if [[ -n "$getprop_bin" ]]; then
    "$getprop_bin" ro.product.cpu.abi 2>/dev/null | tr -d '\r' | awk 'NF {print; exit}'
  fi
}

chroot_busybox_detect_android_api() {
  local getprop_bin=""
  if [[ -n "${CHROOT_BUSYBOX_TEST_ANDROID_API:-}" ]]; then
    printf '%s\n' "$CHROOT_BUSYBOX_TEST_ANDROID_API"
    return 0
  fi
  getprop_bin="$(command -v getprop 2>/dev/null || true)"
  if [[ -z "$getprop_bin" && -x "${CHROOT_SYSTEM_BIN_DEFAULT:-/system/bin}/getprop" ]]; then
    getprop_bin="${CHROOT_SYSTEM_BIN_DEFAULT:-/system/bin}/getprop"
  fi
  if [[ -n "$getprop_bin" ]]; then
    "$getprop_bin" ro.build.version.sdk 2>/dev/null | tr -d '\r' | awk 'NF {print; exit}'
  fi
}

chroot_busybox_detect_uname_m() {
  if [[ -n "${CHROOT_BUSYBOX_TEST_UNAME_M:-}" ]]; then
    printf '%s\n' "$CHROOT_BUSYBOX_TEST_UNAME_M"
    return 0
  fi
  uname -m 2>/dev/null || true
}

chroot_busybox_arch_repo_binary() {
  local abi="$1"
  local uname_m="$2"
  local api="$3"
  local key="${abi:-$uname_m}"
  local prefer_selinux=0
  local repo=""

  if [[ "$api" =~ ^[0-9]+$ ]] && (( api >= 26 )); then
    prefer_selinux=1
  fi

  case "${key,,}" in
    arm64-v8a|aarch64|arm64)
      if (( prefer_selinux == 1 )); then repo="busybox-arm64-selinux"; else repo="busybox-arm64"; fi
      ;;
    armeabi|armeabi-v7a|armv7*|armv8l|arm*)
      if (( prefer_selinux == 1 )); then repo="busybox-arm-selinux"; else repo="busybox-arm"; fi
      ;;
    x86)
      if (( prefer_selinux == 1 )); then repo="busybox-x86-selinux"; else repo="busybox-x86"; fi
      ;;
    x86_64|amd64)
      if (( prefer_selinux == 1 )); then repo="busybox-x86_64-selinux"; else repo="busybox-x86_64"; fi
      ;;
    mips64*)
      repo="busybox-mips64"
      ;;
    mips*)
      repo="busybox-mips"
      ;;
  esac

  [[ -n "$repo" ]] || return 1
  printf '%s\n' "$repo"
}

chroot_busybox_detect_arch_tsv() {
  local abi uname_m api repo arch_label
  abi="$(chroot_busybox_detect_android_abi || true)"
  uname_m="$(chroot_busybox_detect_uname_m || true)"
  api="$(chroot_busybox_detect_android_api || true)"
  repo="$(chroot_busybox_arch_repo_binary "$abi" "$uname_m" "$api" || true)"
  [[ -n "$repo" ]] || return 1
  arch_label="abi=${abi:-unknown} uname=${uname_m:-unknown} api=${api:-unknown}"
  printf '%s\t%s\t%s\t%s\n' "$repo" "$arch_label" "${abi:-}" "${api:-}"
}

chroot_busybox_fetch_url_for_binary() {
  local repo_binary="$1"
  printf '%s/%s\n' "$CHROOT_BUSYBOX_REPO_RAW_BASE" "$repo_binary"
}

chroot_busybox_install_binary_from_file() {
  local source_file="$1"
  local source_type="$2"
  local original_path="$3"
  local fetch_url="${4:-}"
  local repo_binary="${5:-}"
  local detected_arch="${6:-}"
  local busybox_dir stage staged_binary active_binary old_binary validation_file tool_paths_file version_line file_size sha validation_output

  busybox_dir="$(chroot_busybox_dir)"
  stage="$(mktemp -d "$busybox_dir/import.staging.XXXXXX")" || chroot_die "failed creating BusyBox import staging directory"
  staged_binary="$stage/busybox"
  active_binary="$(chroot_busybox_active_binary_path)"
  old_binary="$busybox_dir/busybox.old.$$"
  validation_file="$stage/validation.tsv"
  tool_paths_file="$stage/tool-paths.tsv"

  if ! cp -- "$source_file" "$staged_binary"; then
    rm -rf -- "$stage"
    chroot_die "failed copying BusyBox into staging"
  fi
  chmod 0755 "$staged_binary" || true

  if ! validation_output="$(chroot_busybox_validate_binary_tsv "$staged_binary")"; then
    printf '%s\n' "$validation_output" >"$validation_file"
    rm -rf -- "$stage"
    chroot_die "staged BusyBox validation failed:
$(printf '%s\n' "$validation_output" | chroot_busybox_validation_failed_lines)"
  fi
  printf '%s\n' "$validation_output" >"$validation_file"
  : >"$tool_paths_file"

  version_line="$(chroot_busybox_sanitize_line "$(chroot_busybox_binary_version_line "$staged_binary")")"
  file_size="$(chroot_file_size_bytes "$staged_binary")"
  sha="$(chroot_busybox_sha256_file "$staged_binary")"

  rm -f -- "$old_binary" 2>/dev/null || true
  if [[ -e "$active_binary" ]]; then
    mv -f -- "$active_binary" "$old_binary" || {
      rm -rf -- "$stage"
      chroot_die "failed staging previous managed BusyBox binary for replacement"
    }
  fi
  if ! mv -f -- "$staged_binary" "$active_binary"; then
    if [[ -e "$old_binary" ]]; then
      mv -f -- "$old_binary" "$active_binary" 2>/dev/null || true
    fi
    rm -rf -- "$stage"
    chroot_die "failed installing managed BusyBox binary"
  fi
  chmod 0755 "$active_binary" || true

  if ! chroot_busybox_write_metadata "$source_type" "$original_path" "$active_binary" "" "$fetch_url" "$repo_binary" "$detected_arch" "$version_line" "$file_size" "$sha" "valid" "$validation_file" "$tool_paths_file"; then
    rm -f -- "$active_binary" 2>/dev/null || true
    if [[ -e "$old_binary" ]]; then
      mv -f -- "$old_binary" "$active_binary" 2>/dev/null || true
    fi
    rm -rf -- "$stage"
    chroot_die "failed writing managed BusyBox metadata"
  fi
  rm -f -- "$old_binary" 2>/dev/null || true
  rm -rf -- "$(chroot_busybox_active_applets_dir)" 2>/dev/null || true
  rm -rf -- "$stage"
  chroot_busybox_cleanup_staging
}

chroot_busybox_import_file() {
  local source_file="$1"
  local validation_output
  if ! validation_output="$(chroot_busybox_validate_binary_tsv "$source_file")"; then
    chroot_die "BusyBox binary validation failed:
$(printf '%s\n' "$validation_output" | chroot_busybox_validation_failed_lines)"
  fi
  chroot_busybox_install_binary_from_file "$source_file" "path_file" "$source_file"
}

chroot_busybox_import_dir() {
  local source_dir="$1"
  local busybox_dir stage staged_applets active_applets validation_source validation_staged validation_file tool_paths_file
  local tool source_path staged_path file_size sha version_line

  if ! validation_source="$(chroot_busybox_validate_applet_dir_tsv "$source_dir")"; then
    chroot_die "BusyBox applet directory validation failed:
$(printf '%s\n' "$validation_source" | chroot_busybox_validation_failed_lines)"
  fi

  busybox_dir="$(chroot_busybox_dir)"
  stage="$(mktemp -d "$busybox_dir/import.staging.XXXXXX")" || chroot_die "failed creating BusyBox import staging directory"
  staged_applets="$stage/applets"
  active_applets="$(chroot_busybox_active_applets_dir)"
  validation_file="$stage/validation.tsv"
  tool_paths_file="$stage/tool-paths.tsv"
  : >"$tool_paths_file"
  mkdir -p "$staged_applets" || {
    rm -rf -- "$stage"
    chroot_die "failed creating staged BusyBox applets directory"
  }

  while IFS= read -r tool; do
    [[ -n "$tool" ]] || continue
    source_path="$source_dir/$tool"
    staged_path="$staged_applets/$tool"
    if ! cp -L -- "$source_path" "$staged_path"; then
      rm -rf -- "$stage"
      chroot_die "failed copying required BusyBox applet: $tool"
    fi
    chmod 0755 "$staged_path" || true
    printf '%s\t%s\n' "$tool" "$active_applets/$tool" >>"$tool_paths_file"
  done < <(chroot_busybox_required_tool_ids)

  if ! validation_staged="$(chroot_busybox_validate_applet_dir_tsv "$staged_applets")"; then
    printf '%s\n' "$validation_staged" >"$validation_file"
    rm -rf -- "$stage"
    chroot_die "staged BusyBox applets validation failed:
$(printf '%s\n' "$validation_staged" | chroot_busybox_validation_failed_lines)"
  fi
  printf '%s\n' "$validation_staged" >"$validation_file"

  file_size=0
  sha=""
  version_line="applet directory"
  rm -rf -- "$active_applets.old.$$" 2>/dev/null || true
  if [[ -e "$active_applets" ]]; then
    mv -f -- "$active_applets" "$active_applets.old.$$" || {
      rm -rf -- "$stage"
      chroot_die "failed replacing managed BusyBox applet directory"
    }
  fi
  if ! mv -f -- "$staged_applets" "$active_applets"; then
    if [[ -e "$active_applets.old.$$" ]]; then
      mv -f -- "$active_applets.old.$$" "$active_applets" 2>/dev/null || true
    fi
    rm -rf -- "$stage"
    chroot_die "failed installing managed BusyBox applet directory"
  fi
  rm -rf -- "$active_applets.old.$$" 2>/dev/null || true

  if ! chroot_busybox_write_metadata "path_dir" "$source_dir" "" "$active_applets" "" "" "" "$version_line" "$file_size" "$sha" "valid" "$validation_file" "$tool_paths_file"; then
    rm -rf -- "$active_applets" 2>/dev/null || true
    if [[ -e "$active_applets.old.$$" ]]; then
      mv -f -- "$active_applets.old.$$" "$active_applets" 2>/dev/null || true
    fi
    rm -rf -- "$stage"
    chroot_die "failed writing managed BusyBox metadata"
  fi
  rm -rf -- "$active_applets.old.$$" 2>/dev/null || true
  rm -f -- "$(chroot_busybox_active_binary_path)" 2>/dev/null || true
  rm -rf -- "$stage"
  chroot_busybox_cleanup_staging
}

chroot_busybox_import_path() {
  local source_path="$1"
  [[ -n "$source_path" ]] || chroot_die "BusyBox path is required"
  if [[ ! -e "$source_path" ]]; then
    chroot_die "BusyBox source path not found: $source_path"
  fi
  if [[ -d "$source_path" ]]; then
    chroot_busybox_import_dir "$source_path"
    printf 'BusyBox applet directory imported into Aurora runtime storage.\n'
    return 0
  fi
  if [[ -f "$source_path" ]]; then
    if chroot_busybox_is_archive_path "$source_path"; then
      chroot_die "Unsupported BusyBox source archive: $source_path. Provide a BusyBox binary path or an applet directory path; Aurora does not extract BusyBox archives."
    fi
    if [[ ! -x "$source_path" ]]; then
      chroot_die "Unsupported BusyBox source file: $source_path. Aurora cannot use a non-executable BusyBox binary by reference; provide an executable BusyBox binary path or an applet directory path."
    fi
    chroot_busybox_import_file "$source_path"
    printf 'BusyBox binary imported into Aurora runtime storage as busybox.\n'
    return 0
  fi
  chroot_die "Unsupported BusyBox source path: $source_path. Provide a BusyBox binary path or an applet directory path."
}

chroot_busybox_fetch() {
  local repo arch_label abi api url tmp_file retries timeout
  local arch_row
  arch_row="$(chroot_busybox_detect_arch_tsv || true)"
  [[ -n "$arch_row" ]] || chroot_die "unsupported architecture for BusyBox fetch: $(chroot_busybox_detect_uname_m)"
  IFS=$'\t' read -r repo arch_label abi api <<<"$arch_row"
  url="$(chroot_busybox_fetch_url_for_binary "$repo")"
  tmp_file="$CHROOT_TMP_DIR/$repo.$$"
  retries="$(chroot_setting_get download_retries "$CHROOT_DOWNLOAD_RETRIES_DEFAULT" 2>/dev/null || printf '%s\n' "$CHROOT_DOWNLOAD_RETRIES_DEFAULT")"
  timeout="$(chroot_setting_get download_timeout_sec "$CHROOT_DOWNLOAD_TIMEOUT_SEC_DEFAULT" 2>/dev/null || printf '%s\n' "$CHROOT_DOWNLOAD_TIMEOUT_SEC_DEFAULT")"

  [[ -n "${CHROOT_CURL_BIN:-}" ]] || CHROOT_CURL_BIN="$(command -v curl 2>/dev/null || true)"
  [[ -n "$CHROOT_CURL_BIN" ]] || chroot_die "curl is required for busybox fetch"
  printf 'Detected architecture: %s\n' "$arch_label"
  printf 'Selected repository binary: %s\n' "$repo"
  printf 'Fetching: %s\n' "$url"
  if ! chroot_download_with_retry "$url" "$tmp_file" "$retries" "$timeout"; then
    rm -f -- "$tmp_file"
    chroot_die "BusyBox fetch failed for allowed repository URL: $url"
  fi
  chmod 0755 "$tmp_file" || true
  chroot_busybox_install_binary_from_file "$tmp_file" "fetch" "" "$url" "$repo" "$arch_label"
  rm -f -- "$tmp_file"
  printf 'Fetched BusyBox registered in Aurora runtime storage.\n'
}

chroot_busybox_prepare_command() {
  chroot_detect_bins
  chroot_detect_python
  chroot_busybox_render_detection_banner
}

chroot_busybox_after_registration_message() {
  local missing
  missing="$(chroot_busybox_native_missing_tools)"
  if [[ -z "$missing" ]]; then
    printf 'Downloaded/imported BusyBox is registered as standby fallback and is not currently required.\n'
  else
    printf 'Managed BusyBox fallback is registered for missing backend tools.\n'
  fi
}

chroot_busybox_cmd_fetch() {
  chroot_busybox_prepare_command
  chroot_busybox_ensure_runtime_layout
  chroot_busybox_fetch
  chroot_detect_bins
  chroot_busybox_after_registration_message
}

chroot_busybox_cmd_path() {
  local source_path="$1"
  chroot_busybox_prepare_command
  chroot_busybox_ensure_runtime_layout
  chroot_busybox_import_path "$source_path"
  chroot_detect_bins
  chroot_busybox_after_registration_message
}

chroot_busybox_cmd_status() {
  chroot_busybox_prepare_command
  chroot_busybox_ensure_runtime_layout
  chroot_busybox_render_status
}

chroot_busybox_interactive() {
  local choice source_path
  chroot_busybox_prepare_command
  chroot_busybox_ensure_runtime_layout
  printf '%s\n' "$(chroot_busybox_requirement_summary)"
  if chroot_busybox_native_coverage_complete; then
    printf 'busybox fetch or busybox <path> is not required on this device.\n'
  fi
  printf '\nBusyBox actions:\n'
  printf '  f) fetch device BusyBox\n'
  printf '  p) paste/type a local BusyBox binary or applet directory path\n'
  printf '  s) status\n'
  printf '  q) quit\n'
  printf 'Choose [f/p/s/q]: '
  read -r choice || return 1
  case "${choice,,}" in
    f|fetch)
      chroot_busybox_cmd_fetch
      ;;
    p|path)
      printf 'BusyBox path: '
      read -r source_path || return 1
      chroot_busybox_cmd_path "$source_path"
      ;;
    s|status)
      chroot_busybox_cmd_status
      ;;
    q|quit|"")
      return 0
      ;;
    *)
      chroot_die "invalid BusyBox selection: $choice"
      ;;
  esac
}

chroot_cmd_busybox() {
  if [[ $# -eq 0 ]]; then
    chroot_busybox_interactive
    return 0
  fi

  case "${1:-}" in
    fetch)
      shift
      [[ $# -eq 0 ]] || chroot_die "usage: bash path/to/chroot busybox fetch"
      chroot_busybox_cmd_fetch
      ;;
    status)
      shift
      if [[ "${1:-}" == "--json" ]]; then
        chroot_busybox_prepare_command
        chroot_die "busybox status is human-readable only; use doctor --json for structured BusyBox diagnostics"
      fi
      [[ $# -eq 0 ]] || chroot_die "usage: bash path/to/chroot busybox status"
      chroot_busybox_cmd_status
      ;;
    --json|status\ --json)
      chroot_die "busybox status is human-readable only; use doctor --json for structured BusyBox diagnostics"
      ;;
    -*)
      chroot_die "unknown busybox arg: $1"
      ;;
    *)
      [[ $# -eq 1 ]] || chroot_die "usage: bash path/to/chroot busybox <path>"
      chroot_busybox_cmd_path "$1"
      ;;
  esac
}
