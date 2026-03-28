chroot_service_desktop_detect_distro_family() {
  local distro="$1"
  local rootfs os_release distro_id="" distro_like=""
  rootfs="$(chroot_distro_rootfs_dir "$distro")"

  os_release="$rootfs/etc/os-release"
  if [[ -r "$os_release" ]]; then
    distro_id="$(
      awk -F= '$1 == "ID" {gsub(/"/, "", $2); print tolower($2); exit}' "$os_release" 2>/dev/null || true
    )"
    distro_like="$(
      awk -F= '$1 == "ID_LIKE" {gsub(/"/, "", $2); print tolower($2); exit}' "$os_release" 2>/dev/null || true
    )"
  fi

  case " $distro_id $distro_like " in
    *" arch "*)
      printf 'arch\n'
      return 0
      ;;
    *" ubuntu "*)
      printf 'ubuntu\n'
      return 0
      ;;
  esac

  if [[ -x "$rootfs/usr/bin/pacman" ]]; then
    printf 'arch\n'
    return 0
  fi
  if [[ -x "$rootfs/usr/bin/apt" || -x "$rootfs/usr/bin/apt-get" ]]; then
    printf 'ubuntu\n'
    return 0
  fi

  if [[ -n "$distro_id" ]]; then
    printf '%s\n' "$distro_id"
    return 0
  fi
  printf 'unknown\n'
}
