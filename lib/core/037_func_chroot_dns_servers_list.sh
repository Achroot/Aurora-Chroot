chroot_dns_servers_list() {
  local -a out=()
  local -A seen=()
  local v key

  for key in net.dns1 net.dns2 net.dns3 net.dns4; do
    v="$(getprop "$key" 2>/dev/null || true)"
    v="${v//$'\r'/}"
    v="${v//$'\n'/}"
    if chroot_dns_valid_server "$v" && [[ -z "${seen[$v]:-}" ]]; then
      out+=("$v")
      seen["$v"]=1
    fi
  done

  if [[ -f /etc/resolv.conf ]]; then
    while IFS= read -r v; do
      [[ -n "$v" ]] || continue
      if chroot_dns_valid_server "$v" && [[ -z "${seen[$v]:-}" ]]; then
        out+=("$v")
        seen["$v"]=1
      fi
    done < <(awk '/^[[:space:]]*nameserver[[:space:]]+/ {print $2}' /etc/resolv.conf 2>/dev/null || true)
  fi

  if (( ${#out[@]} == 0 )); then
    out=("1.1.1.1" "8.8.8.8")
  fi

  printf '%s\n' "${out[@]}"
}

