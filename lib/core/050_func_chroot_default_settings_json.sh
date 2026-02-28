chroot_default_settings_json() {
  if declare -F chroot_settings_defaults_json >/dev/null 2>&1; then
    chroot_settings_defaults_json
    return 0
  fi

  cat <<'JSON'
{
  "termux_home_bind": false,
  "android_storage_bind": false,
  "data_bind": false,
  "android_full_bind": false,
  "x11": false,
  "download_retries": 3,
  "download_timeout_sec": 20,
  "log_retention_days": 14
}
JSON
}
