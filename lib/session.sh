#!/usr/bin/env bash

chroot_session_parts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/session"
chroot_session_parts=("$chroot_session_parts_dir"/[0-9][0-9][0-9]_*.sh)
if [[ ! -f "${chroot_session_parts[0]:-}" ]]; then
  printf 'ERROR: missing session parts under %s\n' "$chroot_session_parts_dir" >&2
  if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    return 1
  fi
  exit 1
fi

for chroot_session_part in "${chroot_session_parts[@]}"; do
  # shellcheck source=/dev/null
  source "$chroot_session_part"
done

unset chroot_session_parts_dir chroot_session_parts chroot_session_part
