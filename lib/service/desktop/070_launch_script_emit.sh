chroot_service_desktop_launch_script_content() {
  cat <<'SH'
#!/usr/bin/env bash
set -euo pipefail

profile_env="/etc/aurora-desktop/profile.env"

if [[ -r "$profile_env" ]]; then
  # shellcheck disable=SC1091
  . "$profile_env"
fi

export HOME="${HOME:-/root}"
export USER="${USER:-root}"
export LOGNAME="${LOGNAME:-root}"
export SHELL="${SHELL:-/bin/bash}"
export DISPLAY="${DISPLAY:-:0}"
export XDG_SESSION_TYPE="x11"
export DESKTOP_SESSION="${DESKTOP_SESSION:-${AURORA_DESKTOP_SESSION:-desktop}}"
export XDG_SESSION_DESKTOP="${XDG_SESSION_DESKTOP:-${AURORA_DESKTOP_SESSION:-desktop}}"
export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-${AURORA_DESKTOP_PROFILE_NAME:-Desktop}}"

runtime_dir="${XDG_RUNTIME_DIR:-/tmp/runtime-root}"
mkdir -p "$runtime_dir"
chmod 700 "$runtime_dir" 2>/dev/null || true
export XDG_RUNTIME_DIR="$runtime_dir"

if [[ "${AURORA_X11_DPI:-}" =~ ^[0-9]+$ ]]; then
  dpi_value="$AURORA_X11_DPI"
  cursor_size=$(( dpi_value / 6 ))
  if (( cursor_size < 24 )); then
    cursor_size=24
  elif (( cursor_size > 64 )); then
    cursor_size=64
  fi

  export QT_FONT_DPI="${QT_FONT_DPI:-$dpi_value}"
  export XCURSOR_SIZE="${XCURSOR_SIZE:-$cursor_size}"
  export XFT_DPI="${XFT_DPI:-$dpi_value}"
  export QT_ENABLE_HIGHDPI_SCALING="${QT_ENABLE_HIGHDPI_SCALING:-1}"
  export QT_AUTO_SCREEN_SCALE_FACTOR="${QT_AUTO_SCREEN_SCALE_FACTOR:-0}"

  if (( dpi_value >= 220 )); then
    export GDK_SCALE="${GDK_SCALE:-2}"
  fi

  if command -v xrdb >/dev/null 2>&1; then
    aurora_xrdb_file="$XDG_RUNTIME_DIR/.aurora-Xresources"
    mkdir -p "$(dirname "$aurora_xrdb_file")"
    cat >"$aurora_xrdb_file" <<EOF_XRDB
Xft.dpi: ${dpi_value}
Xcursor.size: ${cursor_size}
EOF_XRDB
    xrdb -merge "$aurora_xrdb_file" >/dev/null 2>&1 || true
  fi
fi

session_cmd="${AURORA_DESKTOP_EXEC:-}"
if [[ -z "$session_cmd" ]]; then
  printf 'ERROR: desktop launcher is missing AURORA_DESKTOP_EXEC.\n' >&2
  exit 1
fi

if command -v dbus-run-session >/dev/null 2>&1; then
  exec dbus-run-session /bin/sh -lc "$session_cmd"
fi

if command -v dbus-launch >/dev/null 2>&1; then
  exec dbus-launch --exit-with-session /bin/sh -lc "$session_cmd"
fi

exec /bin/sh -lc "$session_cmd"
SH
}
