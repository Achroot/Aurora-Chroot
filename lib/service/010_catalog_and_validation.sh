chroot_service_name_is_valid() {
  local name="${1:-}"
  [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

chroot_require_service_name() {
  local name="${1:-}"
  [[ -n "$name" ]] || chroot_die "service name is required"
  chroot_service_name_is_valid "$name" || chroot_die "invalid service name: $name"
}

chroot_service_dir() {
  local distro="$1"
  printf '%s/state/%s/services' "$CHROOT_RUNTIME_ROOT" "$distro"
}

chroot_service_def_file() {
  local distro="$1"
  local name="$2"
  printf '%s/%s.json' "$(chroot_service_dir "$distro")" "$name"
}

chroot_service_list_defs() {
  local distro="$1"
  local sdir
  sdir="$(chroot_service_dir "$distro")"
  [[ -d "$sdir" ]] || return 0
  find "$sdir" -maxdepth 1 -type f -name '*.json' -exec basename {} .json \; | sort | while IFS= read -r name; do
    chroot_service_name_is_valid "$name" || continue
    printf '%s\n' "$name"
  done
}

chroot_service_builtin_ids() {
  printf 'desktop\n'
  printf 'pcbridge\n'
  printf 'sshd\n'
  printf 'zsh\n'
}

chroot_service_builtin_resolve() {
  local builtin_id="${1:-}"
  builtin_id="${builtin_id,,}"
  case "$builtin_id" in
    desktop)
      printf 'desktop\t%s\t%s\n' "$CHROOT_SERVICE_DESKTOP_COMMAND" "$(chroot_service_desktop_description)"
      ;;
    pcbridge)
      printf 'pcbridge\t/usr/local/sbin/aurora-pcbridge-start\tWSL-first file bridge (bootstrap + key-only SFTP + TUI client)\n'
      ;;
    sshd)
      printf 'sshd\t/usr/local/sbin/aurora-sshd-start\tOpenSSH daemon wrapper (installs aurora-sshd-start + service definition)\n'
      ;;
    zsh)
      printf 'zsh\tinstall-only\tZsh shell setup with autocomplete + autosuggestions (Arch/Ubuntu only, install-only)\n'
      ;;
    *)
      return 1
      ;;
  esac
}

chroot_service_builtin_catalog_json() {
  cat <<'JSON'
[
  {
    "id": "desktop",
    "service_name": "desktop",
    "command": "/usr/local/sbin/aurora-desktop-launch",
    "description": "Managed desktop session (XFCE or LXQt over Termux-X11)",
    "requires_profile": true
  },
  {
    "id": "pcbridge",
    "service_name": "pcbridge",
    "command": "/usr/local/sbin/aurora-pcbridge-start",
    "description": "WSL-first file bridge (bootstrap + key-only SFTP + TUI client)"
  },
  {
    "id": "sshd",
    "service_name": "sshd",
    "command": "/usr/local/sbin/aurora-sshd-start",
    "description": "OpenSSH daemon wrapper (installs aurora-sshd-start + service definition)"
  },
  {
    "id": "zsh",
    "service_name": "zsh",
    "command": "install-only",
    "description": "Zsh shell setup with autocomplete + autosuggestions (Arch/Ubuntu only, install-only)",
    "install_only": true
  }
]
JSON
}
