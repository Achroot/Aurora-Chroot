chroot_resolve_host_ipv4() {
  local host="$1"
  local ip=""
  ip="$(ping -c 1 "$host" 2>/dev/null | awk -F'[()]' 'NR==1 {print $2; exit}' | awk -F: '{print $1}')"
  if [[ -n "$ip" ]]; then
    printf '%s\n' "$ip"
    return 0
  fi
  ip="$(chroot_run_root ping -c 1 "$host" 2>/dev/null | awk -F'[()]' 'NR==1 {print $2; exit}' | awk -F: '{print $1}')"
  printf '%s\n' "$ip"
}

