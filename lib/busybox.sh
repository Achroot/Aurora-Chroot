#!/usr/bin/env bash

chroot_busybox_parts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/busybox"
chroot_busybox_parts=("$chroot_busybox_parts_dir"/[0-9][0-9][0-9]_*.sh)
if [[ ! -f "${chroot_busybox_parts[0]:-}" ]]; then
  printf 'ERROR: missing busybox parts under %s\n' "$chroot_busybox_parts_dir" >&2
  if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    return 1
  fi
  exit 1
fi

for chroot_busybox_part in "${chroot_busybox_parts[@]}"; do
  # shellcheck source=/dev/null
  source "$chroot_busybox_part"
done

unset chroot_busybox_parts_dir chroot_busybox_parts chroot_busybox_part
