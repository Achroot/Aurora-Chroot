#!/usr/bin/env bash

# shellcheck disable=SC2034
CHROOT_VERSION="0.1.2"
CHROOT_SCRIPT_NAME="chroot"
CHROOT_DEFAULT_RUNTIME_ROOT="/data/local/aurora-chroot"
CHROOT_RUNTIME_ROOT_FROM_ENV=0
if [[ -n "${CHROOT_RUNTIME_ROOT:-}" ]]; then
  CHROOT_RUNTIME_ROOT_FROM_ENV=1
fi
CHROOT_RUNTIME_ROOT="${CHROOT_RUNTIME_ROOT:-$CHROOT_DEFAULT_RUNTIME_ROOT}"

_chroot_prefix_guess="${CHROOT_TERMUX_PREFIX:-${PREFIX:-}}"
_chroot_known_termux_prefix=""
_chroot_nullglob_was_set=0
if shopt -q nullglob; then
  _chroot_nullglob_was_set=1
fi
shopt -s nullglob
for _chroot_termux_prefix_candidate in /data/data/*/files/usr /data/user/*/*/files/usr; do
  if [[ -e "${_chroot_termux_prefix_candidate}/bin/pkg" && -d "${_chroot_termux_prefix_candidate%/usr}/home" ]]; then
    _chroot_known_termux_prefix="$_chroot_termux_prefix_candidate"
    break
  fi
done
if (( _chroot_nullglob_was_set == 0 )); then
  shopt -u nullglob
fi
if [[ -z "$_chroot_prefix_guess" ]]; then
  _chroot_pkg_bin="$(command -v pkg 2>/dev/null || true)"
  if [[ -n "$_chroot_pkg_bin" ]]; then
    _chroot_prefix_guess="$(cd "$(dirname "$_chroot_pkg_bin")/.." 2>/dev/null && pwd || true)"
  fi
fi
if [[ -z "$_chroot_prefix_guess" ]]; then
  _chroot_bash_bin="$(command -v bash 2>/dev/null || true)"
  if [[ -n "$_chroot_bash_bin" ]]; then
    _chroot_prefix_guess="$(cd "$(dirname "$_chroot_bash_bin")/.." 2>/dev/null && pwd || true)"
  fi
fi
if [[ -n "$_chroot_known_termux_prefix" ]]; then
  if [[ -z "$_chroot_prefix_guess" || "$_chroot_prefix_guess" == "/usr" ]]; then
    _chroot_prefix_guess="$_chroot_known_termux_prefix"
  fi
fi
[[ -n "$_chroot_prefix_guess" ]] || _chroot_prefix_guess="/usr"
CHROOT_TERMUX_PREFIX="$_chroot_prefix_guess"
CHROOT_TERMUX_BIN="$CHROOT_TERMUX_PREFIX/bin"

_chroot_home_guess="${CHROOT_TERMUX_HOME_DEFAULT:-${HOME:-}}"
_chroot_known_termux_home=""
if [[ "$CHROOT_TERMUX_PREFIX" == */usr && "$CHROOT_TERMUX_PREFIX" != "/usr" && -e "$CHROOT_TERMUX_PREFIX/bin/pkg" ]]; then
  _chroot_known_termux_home="${CHROOT_TERMUX_PREFIX%/usr}/home"
fi
if [[ ! -d "$_chroot_known_termux_home" ]]; then
  _chroot_nullglob_was_set=0
  if shopt -q nullglob; then
    _chroot_nullglob_was_set=1
  fi
  shopt -s nullglob
  for _chroot_termux_home_candidate in /data/data/*/files/home /data/user/*/*/files/home; do
    _chroot_termux_prefix_candidate="${_chroot_termux_home_candidate%/home}/usr"
    if [[ -d "$_chroot_termux_home_candidate" && -e "${_chroot_termux_prefix_candidate}/bin/pkg" ]]; then
      _chroot_known_termux_home="$_chroot_termux_home_candidate"
      break
    fi
  done
  if (( _chroot_nullglob_was_set == 0 )); then
    shopt -u nullglob
  fi
fi
if [[ -n "$_chroot_known_termux_home" ]]; then
  if [[ -z "$_chroot_home_guess" || "$_chroot_home_guess" == "/root" ]]; then
    _chroot_home_guess="$_chroot_known_termux_home"
  fi
fi
if [[ -z "$_chroot_home_guess" ]] && [[ "$CHROOT_TERMUX_PREFIX" == */usr ]]; then
  _chroot_home_guess="${CHROOT_TERMUX_PREFIX%/usr}/home"
fi
if [[ -z "$_chroot_home_guess" ]]; then
  _chroot_home_guess="$HOME"
fi
CHROOT_TERMUX_HOME_DEFAULT="$_chroot_home_guess"
unset _chroot_prefix_guess _chroot_pkg_bin _chroot_bash_bin _chroot_home_guess _chroot_known_termux_prefix _chroot_termux_prefix_candidate _chroot_known_termux_home _chroot_termux_home_candidate _chroot_nullglob_was_set

CHROOT_AUTO_INSTALL_DEPS="${CHROOT_AUTO_INSTALL_DEPS:-1}"
CHROOT_AURORA_LAUNCHER_NAME="aurora"
CHROOT_MANIFEST_DIR=""
CHROOT_CACHE_DIR=""
CHROOT_ROOTFS_DIR=""
CHROOT_STATE_DIR=""
CHROOT_BACKUPS_DIR=""
CHROOT_LOG_DIR=""
CHROOT_LOCK_DIR=""
CHROOT_TMP_DIR=""
CHROOT_LOG_FILE=""
CHROOT_LOG_INVOCATION_ID=""
CHROOT_LOG_EVENT_SEQ=0
CHROOT_LOG_LAST_EVENT_ID=""
CHROOT_LOG_SOURCE_EFFECTIVE=""
CHROOT_LOG_RUNNER_EFFECTIVE=""
CHROOT_LOG_COMMAND_TEXT=""
CHROOT_LOG_ARGV_TEXT=""
CHROOT_LOG_FAMILY=""
CHROOT_LOG_ACTION_PATH=""
CHROOT_LOG_DISTRO=""
CHROOT_LOG_START_MS=""
CHROOT_LOG_COMMAND_END_WRITTEN=0
CHROOT_LOG_ACTIVE_INTERNAL_COMMAND=""
CHROOT_SETTINGS_FILE=""
CHROOT_MANIFEST_FILE=""
CHROOT_MANIFEST_META_FILE=""
CHROOT_SYSTEM_BIN_DEFAULT="/system/bin"
CHROOT_SYSTEM_XBIN_DEFAULT="/system/xbin"
CHROOT_SYSTEM_CHROOT="${CHROOT_SYSTEM_CHROOT:-}"
CHROOT_SYSTEM_MOUNT="${CHROOT_SYSTEM_MOUNT:-}"
CHROOT_SYSTEM_UMOUNT="${CHROOT_SYSTEM_UMOUNT:-}"
CHROOT_HOST_SH="${CHROOT_HOST_SH:-}"
CHROOT_BUSYBOX_BIN="${CHROOT_BUSYBOX_BIN:-}"
CHROOT_TOYBOX_BIN="${CHROOT_TOYBOX_BIN:-}"
CHROOT_BUSYBOX_HAS_CHROOT=""
CHROOT_BUSYBOX_HAS_MOUNT=""
CHROOT_BUSYBOX_HAS_UMOUNT=""
CHROOT_TOYBOX_HAS_CHROOT=""
CHROOT_TOYBOX_HAS_MOUNT=""
CHROOT_TOYBOX_HAS_UMOUNT=""
CHROOT_INSIDE_CHROOT=""
CHROOT_RUNTIME_ROOT_MARKER=".aurora-runtime-root"
CHROOT_RUNTIME_ROOT_FALLBACK_HOME_REL="aurora-chroot"
CHROOT_RUNTIME_ROOT_RESOLVED=0

CHROOT_CONFIRM_REMOVE_DEFAULT="Type y and press Enter to continue"
CHROOT_LOCK_TIMEOUT_SEC_DEFAULT=30
CHROOT_DOWNLOAD_RETRIES_DEFAULT=3
CHROOT_DOWNLOAD_TIMEOUT_SEC_DEFAULT=20
CHROOT_LOG_RETENTION_DAYS_DEFAULT=14
CHROOT_CATALOG_VERSION_LIMIT_DEFAULT="${CHROOT_CATALOG_VERSION_LIMIT_DEFAULT:-5}"

CHROOT_PYTHON_BIN=""
CHROOT_TAR_BIN=""
CHROOT_CURL_BIN=""
CHROOT_SHA256_BIN=""
CHROOT_DIALOG_BIN=""
CHROOT_ZSTD_BIN=""
CHROOT_XZ_BIN=""
CHROOT_BASH_BIN=""
CHROOT_PKG_BIN=""
CHROOT_APT_BIN=""
CHROOT_ROOT_LAUNCHER="${CHROOT_ROOT_LAUNCHER:-}"
CHROOT_ROOT_LAUNCHER_BIN=""
CHROOT_ROOT_LAUNCHER_SUBCMD=""
CHROOT_ROOT_LAUNCHER_KIND=""
CHROOT_ROOT_BACKEND_READY=0
CHROOT_ROOT_DIAGNOSTICS=""
CHROOT_ROOT_PROBE_TRACE=""
CHROOT_ROOT_ORIGINAL_LAUNCHER_BIN="${CHROOT_ROOT_ORIGINAL_LAUNCHER_BIN:-}"
CHROOT_ROOT_ORIGINAL_LAUNCHER_SUBCMD="${CHROOT_ROOT_ORIGINAL_LAUNCHER_SUBCMD:-}"
CHROOT_ROOT_ORIGINAL_LAUNCHER_KIND="${CHROOT_ROOT_ORIGINAL_LAUNCHER_KIND:-}"
CHROOT_ROOT_ORIGINAL_DIAGNOSTICS="${CHROOT_ROOT_ORIGINAL_DIAGNOSTICS:-}"
CHROOT_ROOT_ORIGINAL_PROBE_TRACE="${CHROOT_ROOT_ORIGINAL_PROBE_TRACE:-}"
CHROOT_SU_HAS_INTERACTIVE=""
CHROOT_SU_INTERACTIVE_FLAG=""
