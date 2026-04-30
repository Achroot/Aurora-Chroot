#!/usr/bin/env bash

chroot_service_parts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/service"
chroot_service_parts=("$chroot_service_parts_dir"/[0-9][0-9][0-9]_*.sh)
if [[ ! -f "${chroot_service_parts[0]:-}" ]]; then
  printf 'ERROR: missing service parts under %s\n' "$chroot_service_parts_dir" >&2
  if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    return 1
  fi
  exit 1
fi

for chroot_service_part in "${chroot_service_parts[@]}"; do
  # shellcheck source=/dev/null
  source "$chroot_service_part"
done

unset chroot_service_parts_dir chroot_service_parts chroot_service_part
