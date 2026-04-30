chroot_prepend_termux_path() {
  if chroot_is_inside_chroot || ! chroot_is_termux_env; then
    return 0
  fi
  [[ -d "$CHROOT_TERMUX_BIN" ]] || return 0
  case ":$PATH:" in
    *":$CHROOT_TERMUX_BIN:"*) ;;
    *) export PATH="$CHROOT_TERMUX_BIN:$PATH" ;;
  esac
}
