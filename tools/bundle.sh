#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$BASE_DIR/dist/chroot"

mkdir -p "$BASE_DIR/dist"

LIBS=(
  core.sh
  log.sh
  settings.sh
  init.sh
  lock.sh
  preflight.sh
  manifest.sh
  install.sh
  aliases.sh
  mount.sh
  session.sh
  service.sh
  status.sh
  tor.sh
  backup.sh
  remove.sh
  nuke.sh
  cache.sh
  tui.sh
)

TUI_PY_PARTS=("$BASE_DIR"/lib/tui/python/[0-9][0-9][0-9]_*.py)
if [[ ! -f "${TUI_PY_PARTS[0]:-}" ]]; then
  printf 'Missing TUI python parts under %s\n' "$BASE_DIR/lib/tui/python" >&2
  exit 1
fi

HELP_MD_EMBEDDED="$(cat "$BASE_DIR/HELP.md")"
TUI_PY_EMBEDDED="$(cat "${TUI_PY_PARTS[@]}")"

{
  echo '#!/usr/bin/env bash'
  echo 'set -euo pipefail'
  echo 'CHROOT_LIBS_LOADED=1'
  echo
  printf 'CHROOT_EMBEDDED_HELP_MD=%q\n' "$HELP_MD_EMBEDDED"
  echo
  printf 'CHROOT_TUI_PY_EMBEDDED=%q\n' "$TUI_PY_EMBEDDED"
  echo

  for lib in "${LIBS[@]}"; do
    parts_dir="$BASE_DIR/lib/${lib%.sh}"
    parts=("$parts_dir"/[0-9][0-9][0-9]_*.sh)
    if [[ -f "${parts[0]:-}" ]]; then
      for part in "${parts[@]}"; do
        if [[ "$lib" == "service.sh" && "$(basename "$part")" == "090_desktop.sh" ]]; then
          desktop_parts=("$BASE_DIR"/lib/service/desktop/[0-9][0-9][0-9]_*.sh)
          if [[ -f "${desktop_parts[0]:-}" ]]; then
            for desktop_part in "${desktop_parts[@]}"; do
              sed '1{/^#!/d;}' "$desktop_part"
              echo
            done
          fi
        fi
        sed '1{/^#!/d;}' "$part"
        echo
      done
      continue
    fi

    sed '1{/^#!/d;}' "$BASE_DIR/lib/$lib"
    echo
  done

  sed '/source ".*\/lib\//d' "$BASE_DIR/main.sh" | sed '1{/^#!/d;}'
} >"$OUT"

chmod +x "$OUT"
printf 'Bundled: %s\n' "$OUT"
