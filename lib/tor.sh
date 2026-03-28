#!/usr/bin/env bash

chroot_tor_parts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tor"
chroot_tor_parts=("$chroot_tor_parts_dir"/[0-9][0-9][0-9]_*.sh)
if [[ ! -f "${chroot_tor_parts[0]:-}" ]]; then
  printf 'ERROR: missing tor parts under %s\n' "$chroot_tor_parts_dir" >&2
  if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    return 1
  fi
  exit 1
fi

for chroot_tor_part in "${chroot_tor_parts[@]}"; do
  # shellcheck source=/dev/null
  source "$chroot_tor_part"
done

unset chroot_tor_parts_dir chroot_tor_parts chroot_tor_part
