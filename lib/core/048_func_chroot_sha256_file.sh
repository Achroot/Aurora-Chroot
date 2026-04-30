chroot_sha256_file() {
  local file="$1"
  "$CHROOT_SHA256_BIN" "$file" | awk '{print $1}'
}

