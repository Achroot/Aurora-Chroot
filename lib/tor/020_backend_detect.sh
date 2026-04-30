chroot_tor_detect_iptables_bin() {
  chroot_detect_pick_path "${CHROOT_TOR_IPTABLES_OVERRIDE:-${CHROOT_TOR_IPTABLES_BIN:-}}" "iptables" \
    "/system/bin/iptables" "/system/xbin/iptables" "$CHROOT_TERMUX_BIN/iptables" "/usr/sbin/iptables" "/usr/bin/iptables" "/sbin/iptables" "/bin/iptables" || true
}

chroot_tor_detect_ip6tables_bin() {
  chroot_detect_pick_path "${CHROOT_TOR_IP6TABLES_OVERRIDE:-${CHROOT_TOR_IP6TABLES_BIN:-}}" "ip6tables" \
    "/system/bin/ip6tables" "/system/xbin/ip6tables" "$CHROOT_TERMUX_BIN/ip6tables" "/usr/sbin/ip6tables" "/usr/bin/ip6tables" "/sbin/ip6tables" "/bin/ip6tables" || true
}

chroot_tor_detect_ip_bin() {
  chroot_detect_pick_path "${CHROOT_TOR_IP_OVERRIDE:-${CHROOT_TOR_IP_BIN:-}}" "ip" \
    "/system/bin/ip" "$CHROOT_TERMUX_BIN/ip" "/usr/sbin/ip" "/usr/bin/ip" "/sbin/ip" "/bin/ip" || true
}

chroot_tor_detect_cmd_bin() {
  chroot_detect_pick_path "${CHROOT_TOR_CMD_OVERRIDE:-${CHROOT_TOR_CMD_BIN:-}}" "cmd" \
    "/system/bin/cmd" "$CHROOT_TERMUX_BIN/cmd" || true
}

chroot_tor_detect_pm_bin() {
  chroot_detect_pick_path "${CHROOT_TOR_PM_OVERRIDE:-${CHROOT_TOR_PM_BIN:-}}" "pm" \
    "/system/bin/pm" "$CHROOT_TERMUX_BIN/pm" || true
}

chroot_tor_detect_dumpsys_bin() {
  chroot_detect_pick_path "${CHROOT_TOR_DUMPSYS_OVERRIDE:-${CHROOT_TOR_DUMPSYS_BIN:-}}" "dumpsys" \
    "/system/bin/dumpsys" "$CHROOT_TERMUX_BIN/dumpsys" || true
}

chroot_tor_detect_backends() {
  local require_host_net="${1:-0}"

  CHROOT_TOR_IPTABLES_BIN="$(chroot_tor_detect_iptables_bin)"
  CHROOT_TOR_IP6TABLES_BIN="$(chroot_tor_detect_ip6tables_bin)"
  CHROOT_TOR_IP_BIN="$(chroot_tor_detect_ip_bin)"
  CHROOT_TOR_CMD_BIN="$(chroot_tor_detect_cmd_bin)"
  CHROOT_TOR_PM_BIN="$(chroot_tor_detect_pm_bin)"
  CHROOT_TOR_DUMPSYS_BIN="$(chroot_tor_detect_dumpsys_bin)"

  if [[ "$require_host_net" == "1" ]]; then
    [[ -n "$CHROOT_TOR_IPTABLES_BIN" ]] || chroot_die "iptables binary unavailable"
    [[ -n "$CHROOT_TOR_IP_BIN" ]] || chroot_die "ip binary unavailable"
  fi
}

chroot_tor_detect_distro_family() {
  local distro="$1"
  if declare -F chroot_service_desktop_detect_distro_family >/dev/null 2>&1; then
    chroot_service_desktop_detect_distro_family "$distro"
    return 0
  fi

  local rootfs
  rootfs="$(chroot_distro_rootfs_dir "$distro")"
  if [[ -x "$rootfs/usr/bin/pacman" ]]; then
    printf 'arch\n'
    return 0
  fi
  if [[ -x "$rootfs/usr/bin/apt" || -x "$rootfs/usr/bin/apt-get" ]]; then
    printf 'ubuntu\n'
    return 0
  fi
  printf 'unknown\n'
}

chroot_tor_detect_install_backend() {
  local distro="$1"
  local rootfs

  rootfs="$(chroot_distro_rootfs_dir "$distro")"

  if [[ -x "$rootfs/usr/bin/apt-get" || -x "$rootfs/usr/bin/apt" ]]; then
    printf 'apt\n'
    return 0
  fi
  if [[ -x "$rootfs/usr/bin/pacman" ]]; then
    printf 'pacman\n'
    return 0
  fi
  if [[ -x "$rootfs/usr/bin/dnf" ]]; then
    printf 'dnf\n'
    return 0
  fi
  if [[ -x "$rootfs/usr/bin/yum" ]]; then
    printf 'yum\n'
    return 0
  fi
  if [[ -x "$rootfs/usr/bin/zypper" ]]; then
    printf 'zypper\n'
    return 0
  fi
  if [[ -x "$rootfs/sbin/apk" || -x "$rootfs/usr/sbin/apk" || -x "$rootfs/usr/bin/apk" || -x "$rootfs/bin/apk" ]]; then
    printf 'apk\n'
    return 0
  fi
  if [[ -x "$rootfs/usr/bin/xbps-install" || -x "$rootfs/usr/sbin/xbps-install" || -x "$rootfs/sbin/xbps-install" ]]; then
    printf 'xbps\n'
    return 0
  fi

  printf '\n'
}

chroot_tor_install_backend_label() {
  local backend="$1"
  case "$backend" in
    apt) printf 'apt\n' ;;
    pacman) printf 'pacman\n' ;;
    dnf) printf 'dnf\n' ;;
    yum) printf 'yum\n' ;;
    zypper) printf 'zypper\n' ;;
    apk) printf 'apk\n' ;;
    xbps) printf 'xbps-install\n' ;;
    *) printf 'unknown\n' ;;
  esac
}

chroot_tor_can_auto_install() {
  local distro="$1"
  local backend

  backend="$(chroot_tor_detect_install_backend "$distro")"
  [[ -n "$backend" ]]
}

chroot_tor_install_support_note() {
  local distro="$1"
  local backend

  backend="$(chroot_tor_detect_install_backend "$distro")"
  if [[ -n "$backend" ]]; then
    printf 'automatic tor install supported via %s\n' "$(chroot_tor_install_backend_label "$backend")"
  else
    printf 'automatic tor install unavailable for this distro\n'
  fi
}

chroot_tor_install_in_distro() {
  local distro="$1"
  local backend

  backend="$(chroot_tor_detect_install_backend "$distro")"
  [[ -n "$backend" ]] || chroot_die "tor binary missing inside $distro and no supported package manager was detected"

  case "$backend" in
    apt)
      chroot_info "Installing tor inside $distro..."
      chroot_tor_run_in_distro "$distro" /bin/sh -c '
        set -eu
        export DEBIAN_FRONTEND=noninteractive
        if command -v apt-get >/dev/null 2>&1; then
          apt-get update
          apt-get install -y tor
        else
          apt update
          apt install -y tor
        fi
      '
      return 0
      ;;
    pacman)
      chroot_info "Installing tor inside $distro..."
      chroot_tor_run_in_distro "$distro" /bin/sh -c '
        set -eu
        pacman -Sy --noconfirm tor
      '
      return 0
      ;;
    dnf)
      chroot_info "Installing tor inside $distro..."
      chroot_tor_run_in_distro "$distro" /bin/sh -c '
        set -eu
        dnf install -y tor
      '
      return 0
      ;;
    yum)
      chroot_info "Installing tor inside $distro..."
      chroot_tor_run_in_distro "$distro" /bin/sh -c '
        set -eu
        yum install -y tor
      '
      return 0
      ;;
    zypper)
      chroot_info "Installing tor inside $distro..."
      chroot_tor_run_in_distro "$distro" /bin/sh -c '
        set -eu
        zypper --non-interactive refresh
        zypper --non-interactive install tor
      '
      return 0
      ;;
    apk)
      chroot_info "Installing tor inside $distro..."
      chroot_tor_run_in_distro "$distro" /bin/sh -c '
        set -eu
        apk add --no-cache tor
      '
      return 0
      ;;
    xbps)
      chroot_info "Installing tor inside $distro..."
      chroot_tor_run_in_distro "$distro" /bin/sh -c '
        set -eu
        xbps-install -Sy -y tor
      '
      return 0
      ;;
    *)
      chroot_die "tor binary missing inside $distro and no supported package manager was detected"
      ;;
  esac
}

chroot_tor_rootfs_tor_bin() {
  local distro="$1"
  local rootfs
  rootfs="$(chroot_distro_rootfs_dir "$distro")"
  if [[ -x "$rootfs/usr/bin/tor" ]]; then
    printf '%s\n' "$rootfs/usr/bin/tor"
    return 0
  fi
  if [[ -x "$rootfs/bin/tor" ]]; then
    printf '%s\n' "$rootfs/bin/tor"
    return 0
  fi
  return 1
}

chroot_tor_chroot_tor_bin() {
  local distro="$1"
  local rootfs
  rootfs="$(chroot_distro_rootfs_dir "$distro")"
  if [[ -x "$rootfs/usr/bin/tor" ]]; then
    printf '/usr/bin/tor\n'
    return 0
  fi
  if [[ -x "$rootfs/bin/tor" ]]; then
    printf '/bin/tor\n'
    return 0
  fi
  return 1
}

chroot_tor_run_in_distro() {
  local distro="$1"
  shift
  local rootfs
  rootfs="$(chroot_distro_rootfs_dir "$distro")"
  chroot_log_run_internal_command core mount "$distro" mount "$distro" -- chroot_cmd_mount "$distro"
  chroot_run_chroot_env "$rootfs" \
    "HOME=/root" \
    "TERM=${TERM:-xterm-256color}" \
    "PATH=$(chroot_chroot_default_path)" \
    "LANG=${LANG:-C.UTF-8}" \
    -- "$@"
}

chroot_tor_ensure_tor_installed() {
  local distro="$1"
  chroot_tor_rootfs_tor_bin "$distro" >/dev/null 2>&1 && return 0
  chroot_tor_install_in_distro "$distro" || chroot_die "failed to install tor inside $distro"
  chroot_tor_rootfs_tor_bin "$distro" >/dev/null 2>&1 || chroot_die "tor binary still missing inside $distro after install"
}
