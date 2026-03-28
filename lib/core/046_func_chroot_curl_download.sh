chroot_curl_download() {
  local url="$1"
  local out_file="$2"
  local timeout="${3:-$CHROOT_DOWNLOAD_TIMEOUT_SEC_DEFAULT}"
  local err_file host port ip

  err_file="$CHROOT_TMP_DIR/curl-err.$$.log"
  rm -f -- "$err_file"
  if "$CHROOT_CURL_BIN" --fail --location --connect-timeout "$timeout" --retry 1 --silent --show-error "$url" -o "$out_file" 2>"$err_file"; then
    rm -f -- "$err_file"
    return 0
  fi

  if grep -qi 'Could not resolve host' "$err_file"; then
    host="$(chroot_url_extract_host "$url")"
    port="$(chroot_url_extract_port "$url")"
    ip="$(chroot_resolve_host_ipv4 "$host")"
    if [[ -n "$host" && -n "$ip" ]]; then
      if "$CHROOT_CURL_BIN" --fail --location --connect-timeout "$timeout" --retry 1 --silent --show-error --resolve "$host:$port:$ip" "$url" -o "$out_file" 2>>"$err_file"; then
        rm -f -- "$err_file"
        return 0
      fi
    fi
  fi

  cat "$err_file" >&2 || true
  rm -f -- "$err_file"
  return 1
}

