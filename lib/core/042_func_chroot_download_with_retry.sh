chroot_download_with_retry() {
  local url="$1"
  local out_file="$2"
  local retries="${3:-$CHROOT_DOWNLOAD_RETRIES_DEFAULT}"
  local timeout="${4:-$CHROOT_DOWNLOAD_TIMEOUT_SEC_DEFAULT}"
  local total_bytes="${5:-0}"
  local attempt=1
  local tmp_file

  tmp_file="$out_file.tmp"
  rm -f -- "$tmp_file"

  while (( attempt <= retries )); do
    if chroot_curl_download "$url" "$tmp_file" "$timeout" "$total_bytes"; then
      mv -f -- "$tmp_file" "$out_file"
      return 0
    fi
    sleep "$attempt"
    attempt=$((attempt + 1))
  done

  rm -f -- "$tmp_file"
  return 1
}
