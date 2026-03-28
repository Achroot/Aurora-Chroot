chroot_aurora_launcher_bin_dir() {
  local home_dir bin_dir
  bin_dir="$CHROOT_TERMUX_BIN"
  if [[ ! -d "$bin_dir" || ! -w "$bin_dir" ]]; then
    home_dir="${HOME:-$CHROOT_TERMUX_HOME_DEFAULT}"
    if [[ ( ! -d "$home_dir" || ! -w "$home_dir" ) && -d "$CHROOT_TERMUX_HOME_DEFAULT" ]]; then
      home_dir="$CHROOT_TERMUX_HOME_DEFAULT"
    fi
    bin_dir="$home_dir/bin"
  fi
  printf '%s\n' "$bin_dir"
}

chroot_aurora_launcher_path() {
  printf '%s/%s\n' "$(chroot_aurora_launcher_bin_dir)" "$CHROOT_AURORA_LAUNCHER_NAME"
}
