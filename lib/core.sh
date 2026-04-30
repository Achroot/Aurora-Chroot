#!/usr/bin/env bash

chroot_core_parts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/core"
chroot_core_parts=("$chroot_core_parts_dir"/[0-9][0-9][0-9]_*.sh)
if [[ ! -f "${chroot_core_parts[0]:-}" ]]; then
  printf 'ERROR: missing core parts under %s\n' "$chroot_core_parts_dir" >&2
  if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    return 1
  fi
  exit 1
fi

for chroot_core_part in "${chroot_core_parts[@]}"; do
  # shellcheck source=/dev/null
  source "$chroot_core_part"
done

unset chroot_core_parts_dir chroot_core_parts chroot_core_part
