CHROOT_SERVICE_DESKTOP_LOADED=1
CHROOT_SERVICE_DESKTOP_ID="desktop"
CHROOT_SERVICE_DESKTOP_NAME="Desktop"
CHROOT_SERVICE_DESKTOP_SERVICE_NAME="desktop"
CHROOT_SERVICE_DESKTOP_COMMAND="/usr/local/sbin/aurora-desktop-launch"
CHROOT_SERVICE_DESKTOP_SCHEMA_VERSION=1

chroot_service_desktop_builtin_id() {
  printf '%s\n' "$CHROOT_SERVICE_DESKTOP_ID"
}

chroot_service_desktop_service_name() {
  printf '%s\n' "$CHROOT_SERVICE_DESKTOP_SERVICE_NAME"
}

chroot_service_desktop_command() {
  printf '%s\n' "$CHROOT_SERVICE_DESKTOP_COMMAND"
}

chroot_service_desktop_description() {
  printf '%s\n' "Managed desktop session (XFCE or LXQt over Termux-X11)"
}
