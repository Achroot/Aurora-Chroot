#!/usr/bin/env bash

chroot_cmd_init() {
  [[ $# -eq 0 ]] || chroot_die "usage: bash path/to/chroot init"

  cat <<'EOF_INIT'
═══════════════════════════════════════════════════════
  Aurora Chroot — First-Run Setup Guide
═══════════════════════════════════════════════════════

  This command does NOT execute anything automatically.
  Follow the steps below in order.

─── Step 1: Set up Termux ─────────────────────────────

  Open Termux and run these commands one at a time:

    termux-change-repo          # mirror group > all mirrors
    pkg update -y && pkg upgrade -y

─── Step 2: Install required packages ─────────────────

    pkg install -y bash coreutils curl tar python dialog zstd xz-utils x11-repo termux-x11-nightly

EOF_INIT

  cat <<'EOF_INIT2'
─── Step 3: Restart Termux───────────────────────────────
  The `aurora` shortcut was created when you ran this command.
  You can now use `aurora` everywhere instead of the full path.

    aurora                      # launches the TUI
    aurora doctor               # verify system readiness
    aurora distros --refresh    # fetch latest distro catalog

  Use the TUI to browse distros, install, and manage everything.

═══════════════════════════════════════════════════════
EOF_INIT2
}
