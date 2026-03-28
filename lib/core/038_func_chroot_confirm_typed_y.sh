chroot_confirm_typed_y() {
  local prompt="${1:-$CHROOT_CONFIRM_REMOVE_DEFAULT}"
  local reply
  printf '%s: ' "$prompt" >&2
  read -r reply
  [[ "$reply" == "y" ]]
}

