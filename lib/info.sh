#!/usr/bin/env bash

chroot_info_parts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/info"
chroot_info_parts=("$chroot_info_parts_dir"/[0-9][0-9][0-9]_*.sh)
if [[ ! -f "${chroot_info_parts[0]:-}" ]]; then
  printf 'ERROR: missing info parts under %s\n' "$chroot_info_parts_dir" >&2
  if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    return 1
  fi
  exit 1
fi

for chroot_info_part in "${chroot_info_parts[@]}"; do
  # shellcheck source=/dev/null
  source "$chroot_info_part"
done

unset chroot_info_parts_dir chroot_info_parts chroot_info_part
