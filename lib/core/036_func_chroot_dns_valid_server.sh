chroot_dns_valid_server() {
  local v="${1:-}"
  [[ -n "$v" ]] || return 1
  case "$v" in
    0.0.0.0|127.*|localhost) return 1 ;;
  esac
  [[ "$v" =~ ^[0-9a-fA-F:.]+$ ]] || return 1
  return 0
}

