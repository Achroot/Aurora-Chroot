#!/usr/bin/env bash

if [[ "${CHROOT_SERVICE_DESKTOP_LOADED:-}" != "1" ]]; then
  chroot_service_desktop_parts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/desktop"
  chroot_service_desktop_parts=("$chroot_service_desktop_parts_dir"/[0-9][0-9][0-9]_*.sh)

  if [[ -f "${chroot_service_desktop_parts[0]:-}" ]]; then
    for chroot_service_desktop_part in "${chroot_service_desktop_parts[@]}"; do
      # shellcheck source=/dev/null
      source "$chroot_service_desktop_part"
    done
  fi

  unset chroot_service_desktop_parts_dir chroot_service_desktop_parts chroot_service_desktop_part
fi
