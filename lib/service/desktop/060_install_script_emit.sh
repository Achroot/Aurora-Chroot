chroot_service_desktop_install_script_content() {
  cat <<'SH'
#!/usr/bin/env bash
set -euo pipefail

family="${1:-}"
profile="${2:-}"
export DEBIAN_FRONTEND=noninteractive

note() {
  printf '[desktop] %s\n' "$*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf '[desktop] ERROR: required command not found: %s\n' "$1" >&2
    exit 1
  }
}

repair_ubuntu_package_state() {
  note "Repairing interrupted dpkg state if needed..."
  if dpkg --configure -a; then
    return 0
  fi

  note "dpkg was interrupted; running apt-get -f install..."
  apt-get install -f -y
  dpkg --configure -a
}

case "$family" in
  ubuntu)
    require_cmd apt-get
    require_cmd dpkg
    repair_ubuntu_package_state
    note "Refreshing apt metadata..."
    apt-get update

    common_pkgs=(dbus dbus-x11 xauth xterm)
    case "$profile" in
      lxqt)
        profile_pkgs=(lxqt qterminal openbox)
        ;;
      xfce)
        profile_pkgs=(xfce4 xfce4-goodies xfce4-terminal)
        ;;
      *)
        printf '[desktop] ERROR: unsupported desktop profile: %s\n' "$profile" >&2
        exit 1
        ;;
    esac

    note "Installing Ubuntu desktop packages for $profile..."
    apt-get install -y "${common_pkgs[@]}" "${profile_pkgs[@]}"
    ;;
  arch)
    require_cmd pacman
    note "Refreshing pacman metadata..."
    pacman -Sy --noconfirm --needed archlinux-keyring
    pacman -Syu --noconfirm

    common_pkgs=(dbus xorg-xauth xterm)
    case "$profile" in
      lxqt)
        profile_pkgs=(lxqt qterminal)
        ;;
      xfce)
        profile_pkgs=(xfce4 xfce4-goodies xfce4-terminal)
        ;;
      *)
        printf '[desktop] ERROR: unsupported desktop profile: %s\n' "$profile" >&2
        exit 1
        ;;
    esac

    note "Installing Arch desktop packages for $profile..."
    pacman -S --noconfirm --needed "${common_pkgs[@]}" "${profile_pkgs[@]}"
    ;;
  *)
    printf '[desktop] ERROR: unsupported distro family: %s\n' "$family" >&2
    exit 1
    ;;
esac

case "$profile" in
  lxqt)
    command -v startlxqt >/dev/null 2>&1 || {
      printf '[desktop] ERROR: startlxqt is missing after install.\n' >&2
      exit 1
    }
    ;;
  xfce)
    command -v startxfce4 >/dev/null 2>&1 || {
      printf '[desktop] ERROR: startxfce4 is missing after install.\n' >&2
      exit 1
    }
    ;;
esac

note "Desktop packages ready for $profile."
SH
}
