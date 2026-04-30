chroot_file_size_bytes() {
  local path="$1"
  [[ -f "$path" ]] || {
    printf '0\n'
    return 0
  }
  stat -c '%s' "$path" 2>/dev/null || wc -c <"$path" 2>/dev/null || printf '0\n'
}

chroot_human_bytes() {
  local bytes="${1:-0}"
  local unit_index=0
  local -a units=("B" "K" "M" "G" "T" "P")
  local value="${bytes:-0}"
  local whole frac

  [[ "$value" =~ ^[0-9]+$ ]] || value=0
  if (( value <= 0 )); then
    printf 'unknown\n'
    return 0
  fi

  while (( value >= 1024 && unit_index < ${#units[@]} - 1 )); do
    frac=$(( (value % 1024) * 10 / 1024 ))
    whole=$(( value / 1024 ))
    value="$whole"
    unit_index=$((unit_index + 1))
  done

  if (( unit_index == 0 )); then
    printf '%s%s\n' "$value" "${units[$unit_index]}"
  elif (( value >= 10 )); then
    printf '%s%s\n' "$value" "${units[$unit_index]}"
  else
    frac="${frac:-0}"
    printf '%s.%s%s\n' "$value" "$frac" "${units[$unit_index]}"
  fi
}

chroot_progress_write_state() {
  local kind="$1"
  local downloaded_bytes="${2:-0}"
  local total_bytes="${3:-0}"
  local status="${4:-running}"
  local url="${5:-}"
  local progress_file="${CHROOT_PROGRESS_FILE:-}"

  [[ -n "$progress_file" ]] || return 0
  printf '%s\t%s\t%s\t%s\t%s\n' "$kind" "$downloaded_bytes" "$total_bytes" "$status" "$url" >"$progress_file" 2>/dev/null || true
}

chroot_progress_download_text() {
  local downloaded_bytes="${1:-0}"
  local total_bytes="${2:-0}"
  local downloaded_text total_text percent

  if [[ "$downloaded_bytes" =~ ^[0-9]+$ ]] && (( downloaded_bytes == 0 )); then
    downloaded_text="0B"
  else
    downloaded_text="$(chroot_human_bytes "$downloaded_bytes")"
  fi
  if [[ "$total_bytes" =~ ^[0-9]+$ ]] && (( total_bytes > 0 )); then
    total_text="$(chroot_human_bytes "$total_bytes")"
    percent=$(( downloaded_bytes * 100 / total_bytes ))
    if (( percent > 100 )); then
      percent=100
    fi
    printf 'download=%s/%s (%s%%)\n' "$downloaded_text" "$total_text" "$percent"
  else
    printf 'downloaded=%s\n' "$downloaded_text"
  fi
}

chroot_curl_download_once() {
  local url="$1"
  local out_file="$2"
  local timeout="$3"
  local err_file="$4"
  local resolve_arg="${5:-}"

  local -a cmd=("$CHROOT_CURL_BIN" --fail --location --connect-timeout "$timeout" --speed-time "$timeout" --speed-limit 1024 --retry 1 --silent --show-error)
  if [[ -n "$resolve_arg" ]]; then
    cmd+=(--resolve "$resolve_arg")
  fi
  cmd+=("$url" -o "$out_file")
  "${cmd[@]}" 2>"$err_file" &
  CHROOT_CURL_DOWNLOAD_LAST_PID="$!"
  return 0
}

chroot_curl_download() {
  local url="$1"
  local out_file="$2"
  local timeout="${3:-$CHROOT_DOWNLOAD_TIMEOUT_SEC_DEFAULT}"
  local total_bytes="${4:-0}"
  local err_file host port ip curl_pid resolve_arg progress_line previous_line downloaded_bytes rc

  err_file="$CHROOT_TMP_DIR/curl-err.$$.log"
  rm -f -- "$err_file"
  CHROOT_CURL_DOWNLOAD_LAST_PID=""
  progress_line=""
  previous_line=""

  chroot_progress_write_state "download" "0" "$total_bytes" "starting" "$url"
  chroot_curl_download_once "$url" "$out_file" "$timeout" "$err_file" || return 1
  curl_pid="${CHROOT_CURL_DOWNLOAD_LAST_PID:-}"
  [[ "$curl_pid" =~ ^[0-9]+$ ]] || {
    chroot_progress_write_state "download" "0" "$total_bytes" "error" "$url"
    cat "$err_file" >&2 || true
    rm -f -- "$err_file"
    return 1
  }

  while kill -0 "$curl_pid" 2>/dev/null; do
    downloaded_bytes="$(chroot_file_size_bytes "$out_file")"
    chroot_progress_write_state "download" "$downloaded_bytes" "$total_bytes" "running" "$url"
    if [[ -t 2 ]]; then
      progress_line="$(chroot_progress_download_text "$downloaded_bytes" "$total_bytes")"
      if (( ${#previous_line} > ${#progress_line} )); then
        printf '\r%s%*s' "$progress_line" "$(( ${#previous_line} - ${#progress_line} ))" '' >&2
      else
        printf '\r%s' "$progress_line" >&2
      fi
      previous_line="$progress_line"
    fi
    sleep 0.2
  done

  rc=0
  wait "$curl_pid" || rc=$?
  downloaded_bytes="$(chroot_file_size_bytes "$out_file")"
  if (( rc == 0 )); then
    chroot_progress_write_state "download" "$downloaded_bytes" "$total_bytes" "done" "$url"
    if [[ -t 2 ]]; then
      progress_line="$(chroot_progress_download_text "$downloaded_bytes" "$total_bytes")"
      if (( ${#previous_line} > ${#progress_line} )); then
        printf '\r%s%*s\n' "$progress_line" "$(( ${#previous_line} - ${#progress_line} ))" '' >&2
      else
        printf '\r%s\n' "$progress_line" >&2
      fi
    fi
    rm -f -- "$err_file"
    return 0
  fi

  if [[ -t 2 && -n "$previous_line" ]]; then
    printf '\n' >&2
  fi

  if grep -qi 'Could not resolve host' "$err_file"; then
    host="$(chroot_url_extract_host "$url")"
    port="$(chroot_url_extract_port "$url")"
    ip="$(chroot_resolve_host_ipv4 "$host")"
    if [[ -n "$host" && -n "$ip" ]]; then
      resolve_arg="$host:$port:$ip"
      rm -f -- "$err_file"
      chroot_progress_write_state "download" "0" "$total_bytes" "retry-resolve" "$url"
      CHROOT_CURL_DOWNLOAD_LAST_PID=""
      chroot_curl_download_once "$url" "$out_file" "$timeout" "$err_file" "$resolve_arg" || return 1
      curl_pid="${CHROOT_CURL_DOWNLOAD_LAST_PID:-}"
      [[ "$curl_pid" =~ ^[0-9]+$ ]] || {
        chroot_progress_write_state "download" "0" "$total_bytes" "error" "$url"
        cat "$err_file" >&2 || true
        rm -f -- "$err_file"
        return 1
      }
      previous_line=""
      while kill -0 "$curl_pid" 2>/dev/null; do
        downloaded_bytes="$(chroot_file_size_bytes "$out_file")"
        chroot_progress_write_state "download" "$downloaded_bytes" "$total_bytes" "running" "$url"
        if [[ -t 2 ]]; then
          progress_line="$(chroot_progress_download_text "$downloaded_bytes" "$total_bytes")"
          if (( ${#previous_line} > ${#progress_line} )); then
            printf '\r%s%*s' "$progress_line" "$(( ${#previous_line} - ${#progress_line} ))" '' >&2
          else
            printf '\r%s' "$progress_line" >&2
          fi
          previous_line="$progress_line"
        fi
        sleep 0.2
      done

      rc=0
      wait "$curl_pid" || rc=$?
      downloaded_bytes="$(chroot_file_size_bytes "$out_file")"
      if (( rc == 0 )); then
        chroot_progress_write_state "download" "$downloaded_bytes" "$total_bytes" "done" "$url"
        if [[ -t 2 ]]; then
          progress_line="$(chroot_progress_download_text "$downloaded_bytes" "$total_bytes")"
          if (( ${#previous_line} > ${#progress_line} )); then
            printf '\r%s%*s\n' "$progress_line" "$(( ${#previous_line} - ${#progress_line} ))" '' >&2
          else
            printf '\r%s\n' "$progress_line" >&2
          fi
        fi
        rm -f -- "$err_file"
        return 0
      fi
      if [[ -t 2 && -n "$previous_line" ]]; then
        printf '\n' >&2
      fi
    fi
  fi

  chroot_progress_write_state "download" "$(chroot_file_size_bytes "$out_file")" "$total_bytes" "error" "$url"
  cat "$err_file" >&2 || true
  rm -f -- "$err_file"
  return 1
}
