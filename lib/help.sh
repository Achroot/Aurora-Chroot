#!/usr/bin/env bash

chroot_help_repeat_char() {
  local count="${1:-0}"
  local char="${2:--}"
  local out=""
  while (( count > 0 )); do
    out+="$char"
    count=$((count - 1))
  done
  printf '%s\n' "$out"
}

chroot_help_heading_block() {
  local text="${1:-}"
  local char="${2:--}"
  [[ -n "$text" ]] || return 0
  printf '%s\n' "$text"
  chroot_help_repeat_char "${#text}" "$char"
}

chroot_help_render_full_text() {
  local line heading
  local pending_blank=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      '# '*)
        heading="${line#\# }"
        (( pending_blank == 0 )) || printf '\n'
        chroot_help_heading_block "$heading" "="
        printf '\n'
        pending_blank=0
        continue
        ;;
      '## '*)
        heading="${line#\#\# }"
        (( pending_blank == 0 )) || printf '\n'
        chroot_help_heading_block "$heading" "-"
        printf '\n'
        pending_blank=0
        continue
        ;;
      '### `'*'`')
        heading="${line#\#\#\# \`}"
        heading="${heading%\`}"
        (( pending_blank == 0 )) || printf '\n'
        chroot_help_heading_block "$heading" "~"
        printf '\n'
        pending_blank=0
        continue
        ;;
      '')
        if (( pending_blank == 0 )); then
          printf '\n'
          pending_blank=1
        fi
        continue
        ;;
      *)
        printf '%s\n' "$line"
        pending_blank=0
        ;;
    esac
  done < <(chroot_help_full_text)
}

chroot_help_full_text() {
  cat <<'EOF_HELP'
# Chroot Command Help

This document mirrors `bash path/to/chroot help` and explains what each command does, including defaults and required arguments.

## Invocation

- `bash path/to/chroot help [raw]`
- `bash path/to/chroot <command> [args]`
- `bash path/to/chroot <distro> service [args]`
- `bash path/to/chroot <distro> sessions [args]`
- `bash path/to/chroot <distro> tor [args]`
- `aurora help [raw]`
- `aurora <command> [args]` (alias created in Termux)
- `aurora <distro> service [args]`
- `aurora <distro> sessions [args]`
- `aurora <distro> tor [args]`
- On first run in Termux, Aurora creates/updates `aurora` at resolved `$PREFIX/bin` (fallback `$HOME/bin`) to call the current chroot script absolute path and forward all args.

If no command is provided, the tool runs `help`.

## Runtime Root

- Runtime root is resolved dynamically at startup.
- Priority order: `CHROOT_RUNTIME_ROOT` override, existing initialized runtime, `/data/local/chroot`, `/data/local/tmp/chroot`, `/data/chroot`, then `$HOME/.local/share/aurora-chroot`.
- The selected runtime root must be absolute, safe, and writable.
- All installs/state/logs are scoped under the resolved runtime root.

## Root Backend

- Aurora is root-launcher agnostic.
- Detection order: already-root process, `CHROOT_ROOT_LAUNCHER` override, provider-native launchers (if present), then compatibility `su` launchers.
- `doctor --json` reports root backend details for troubleshooting.

## Termux Distro Login Aliases

- In Termux host mode, successful distro install operations auto-manage quick login aliases.
- Managed block markers in rc files:
  - `# >>> aurora login distros quick aliases >>>`
  - `# <<< aurora login distros quick aliases <<<`
- Alias format:
  - `alias <distro>='<resolved-aurora-launcher> login <distro>'`
- Launcher path is resolved using the same dynamic logic Aurora uses to create the `aurora` launcher (no hardcoded device path).
- File behavior:
  - If neither `~/.bashrc` nor `~/.zshrc` exists, Aurora creates only `~/.bashrc`.
  - If both exist, Aurora updates both.
  - If only one exists, Aurora updates only that file.
- On successful `remove`, Aurora removes only that distro alias from the managed block.
- Existing user content outside the managed block is preserved.

## Commands

### `help [raw]`

Displays the full command reference in CLI or TUI. In the TUI, switch `View` to `Raw command list` for the compact command-only reference.

- Without args: opens the TUI.
- In non-interactive mode: prints the full command reference.
- `help raw`: prints the raw merged command list only, with no explanatory notes.

### `init`

Verifies core dependencies and prints first-run Termux setup instructions.

- Does not execute setup commands.
- Shows copy/paste commands for repo selection, package install, storage setup, and backend-agnostic root checks.
- On already prepared installs, it prints the same guidance plus dependency status.

### `doctor [--json] [--repair-locks]`

Runs comprehensive preflight system checks and repairs corrupted lockfiles.

- Without args: prints a text table of checks.
- `--json`: prints a JSON report.
- `--repair-locks`: deletes only stale lockdirs (no active owner PID). Can be combined with `--json`.

Notes:
- Free-space check uses measured available space on the resolved runtime filesystem.
- `--json` also includes portability selftest summary and root-backend probe trace (candidates tried and why they were accepted/rejected).
- Tool diagnostics report effective `chroot`/`mount`/`umount` backends, including BusyBox applet fallback when selected.

### `distros [--json] [--refresh] [--install <id> --version <release>]`

Opens the interactive distro catalog to browse, fetch, and install new Linux environments.

Flow:
- Loads distro metadata from local cached manifest by default.
- Shows available distro names.
- After selecting a distro, shows available versions.
- After selecting a version, shows details and offers install.

Notes:
- `--refresh`: manually fetches latest distro metadata and overwrites old cache.
- `--json`: prints catalog JSON from cache (or refreshed cache when combined with `--refresh`).
- Version lists are capped to the latest 5 entries per distro.
- Catalog and version selection are filtered by the current host architecture.
- Requires an interactive terminal.
- This replaces the previous separate `fetch`, `list`, and `install` flow.
- On successful install, Aurora adds/updates the distro alias in managed Termux rc profile block(s) and prints which profile(s) were updated plus login hint.

### `install-local <distro> --file <path> [--sha256 <hex>]`

Installs a custom Linux distribution directly from a local tarball archive.

- Without args: error (`install-local requires distro`).
- `--file <path>` is required.
- `--sha256 <hex>` is optional. If not provided, it requires typed confirmation to proceed without verification.

Behavior notes:
- Uses the same staging/extract flow as manifest-based installs.
- On successful install, Aurora adds/updates the distro alias in managed Termux rc profile block(s) and prints which profile(s) were updated plus login hint.

### `status [--all|--distro <id>] [--json] [--live]`

Displays an overview of installed distros, active sessions, and mount states.

- Without args: table for all installed distros, followed by per-session details (session id/pid/state/mode/start/cmd) for each distro with recorded sessions.
- `--all`: same as the default (all installed distros).
- `--distro <id>`: only report a single distro if installed.
- `--json`: JSON report including cache size and `safe_to_remove`/`rootfs_mounts`.
- `--live`: with `--json`, adds per-distro live diagnostics (`live.active_sessions`, `live.active_mounts`, stale counters, and raw log-entry counts).

### `<distro> tor [status|on|start|off|stop|restart|freeze|logs|newnym|doctor|apps|exit|remove|rm] [args...]`

Controls Aurora's distro-backed Tor mode for supported Android app traffic. This feature is still in beta.

- `status`: Prints current Tor mode status for the selected distro. Default action. When the Tor daemon is running and bootstrapped, Aurora shows both Tor control's current exit candidate and a separate live SOCKS-routed public-exit probe for comparison. If they do not match, Aurora notes that the probe hit a different Tor exit; if the IP matches but country codes differ, Aurora notes that Tor control and external GeoIP data disagree.
- `status --json`: Prints machine-readable Tor status for TUI and scripting, including `active_exit`, `public_exit`, and the `active_exit.matched_public_ip` / `active_exit.selection` comparison fields when available.
- `on|start [--configured [apps|exit]] [--no-lan-bypass]`: Mounts the selected distro, installs/runs Tor inside it, waits for bootstrap, then applies Aurora-owned routing rules. Plain `on` ignores saved Apps Tunneling and exit-country preferences. `on --configured` applies both. `on --configured apps` applies only saved Apps Tunneling config. `on --configured exit` applies only saved exit-country config. `--no-lan-bypass` blocks direct private/LAN IPv4 access for targeted apps instead of allowing the usual bypass.
- `off|stop`: Removes Aurora-owned routing rules and stops the selected distro's Tor daemon.
- `restart [--configured [apps|exit]] [--no-lan-bypass]`: Runs a clean `off` then `on` cycle. `--configured` applies both saved Apps Tunneling and exit-country preferences. `--configured apps` and `--configured exit` apply only that side. `--no-lan-bypass` blocks direct private/LAN IPv4 access for targeted apps instead of allowing the usual bypass.
- `freeze`: Pins the current public Tor exit for the active session. The freeze is runtime-only and clears automatically on `newnym`, `off`, or `restart`.
- `logs [--tail <N>]`: Shows the selected distro's Tor runtime log.
- `newnym`: Requests fresh Tor circuits for new connections on the active selected distro.
- `doctor [--json]`: Probes distro/backend readiness and routing-rule support without enabling Tor.
- `apps list|refresh|set`: Manages the saved Apps Tunneling selection for configured Tor runs.
  `apps list [--json] [--system|--unknown]`
  Shows the cached list. Default output is user apps only. `--system` switches the list to system apps. `--unknown` shows apps whose scope could not be classified confidently. Human output prints one app per line with `[x]` for tunneled and `[ ]` for bypassed, using label when available and package id as fallback.
  `apps refresh [--json]`
  Rebuilds the cached Android app inventory and re-fetches labels when possible.
  `apps set "<query[,query...]>" <bypassed|tunneled>`
  Resolves one or more comma-separated labels/package ids and applies the selected mode immediately to saved config.
- `exit list|refresh|set`: Manages saved Exit Tunneling country preferences for configured Tor runs.
  `exit list [--json]`
  Shows the cached country list. Human output prints one country per line as `Country (CC)` with selected/unselected state.
  `exit refresh [--json]`
  Rebuilds the cached country inventory from the internal country catalog plus saved config.
  `exit set "<query[,query...]>" <selected|unselected>`
  Resolves one or more comma-separated country names/codes and applies the selected mode immediately to saved config.
  `exit set strict <on|off>`
  Updates strict mode immediately. Turning strict on requires at least one selected country.
- `remove|rm [--yes]`: Stops Tor for the selected distro if needed, then deletes Aurora-managed Tor state plus Aurora and standard Tor runtime/config/log/cache directories inside that distro, while keeping the installed distro packages themselves installed.

Behavior notes:
- V1 is distro-backed and requires an installed distro.
- Automatic Tor package installation currently supports apt, pacman, dnf, yum, zypper, apk, and xbps-based distros. Ubuntu remains the primary tested path.
- Installs Tor inside the selected distro when it is missing.
- Only one distro can be the active system-wide Tor backend at a time.
- Routes supported TCP traffic through Tor and sends DNS to Tor `DNSPort`.
- Blocks unsupported UDP traffic instead of letting it leak direct.
- Blocks IPv6 in Tor mode to reduce leak risk.
- Bypasses loopback and common private/LAN IPv4 destinations.
- Targets Android app UIDs discovered from package-manager data. Root-owned/system daemon traffic is not included by default.
- Tor refuses to start if the selected distro would run the daemon as root instead of a dedicated Tor user.
- Apps Tunneling is enforced at the Android UID level. When multiple packages share one UID, saving any of them as bypassed or tunneled affects that whole UID group after save/refresh.
- User/system app scope filtering is best-effort from Android package metadata and install paths. Packages that cannot be classified confidently are marked `unknown` instead of being forced into the user-app view.
- Host Termux/Aurora traffic is included when the distro Tor daemon runs under a different UID than the host user; otherwise status shows a warning and excludes it.
- Tor status warns if the Android app inventory changed since Tor was enabled, because the targeted UID snapshot is generated at `<distro> tor on` / `<distro> tor restart` time.
- Tor status also warns that Android DNS anonymity still depends on device resolver behavior and should be validated on-device when that matters.
- Some apps may fail or be slower. This is Tor mode, not a full-protocol VPN replacement.
- Circuit rotation behavior is controlled by setting `tor_rotation_min` (default `5`), which maps to Tor `MaxCircuitDirtiness` for new connections.
- Bootstrap wait behavior is controlled by setting `tor_bootstrap_timeout_sec` (default `45`).
- Apps Tunneling and Exit Tunneling preferences are saved per distro and only used in configured runs: `--configured`, `--configured apps`, or `--configured exit`.
- Runtime exit freeze is session-only and does not rewrite saved exit-country preferences.
- `apps refresh` rebuilds the cached Android app inventory and re-fetches labels when possible.
- `apps list` uses the cached inventory and refreshes only when the cache is missing. By default it shows user apps. `--system` switches the list to system apps and `--unknown` shows only apps with uncertain scope classification.
- App labels are shown when Aurora can resolve them from Android package metadata and APK resources. If label resolution fails, Aurora keeps the app visible and falls back to the package id instead of hiding it.
- If package metadata enrichment is incomplete, Aurora keeps UID targeting usable and falls back to package ids plus `unknown` scope where needed instead of failing the Tor workflow.
- The same cached app inventory stores both resolved labels and package-id fallbacks, so later opens can reuse the saved list until `apps refresh` is requested.
- Exit Tunneling uses a cached country inventory too. `exit list` reads the saved cache and `exit refresh` rebuilds it. Selected countries sort first after save or refresh.
- Country labels are always shown as `Country (CC)` in both CLI and TUI.
- `<distro> sessions kill`, `<distro> sessions kill-all`, `unmount --kill-sessions`, and distro `remove` all stop Tor cleanly when it is active for that distro.
- If `<distro> tor on` fails and Aurora mounted the distro only for that attempt, Aurora unmounts it again during failure cleanup.

### `<distro> service [list|status|on|start|off|stop|restart|add|install|remove|rm] [args...]`

Manages persistent background services and daemons without a traditional init system.

- `list`: Shows a table of all defined services, their live status, and PIDs. (Default action).
- `status`: Alias of `list`.
- `add <name> <command>`: Creates a new service definition. The command must run the daemon in the foreground.
- `install [<builtin-id>]`: Installs a built-in service definition. With no id in interactive terminals, shows a picker. Use `install --json` to list built-ins for scripting/TUI.
- `install desktop --profiles --json`: Returns desktop install metadata, including host RAM, requirement state, and the `lxqt` / `xfce` profile recommendations.
- `install desktop --profile <xfce|lxqt> [--reinstall]`: Installs or refreshes the managed desktop service inside the selected distro.
- `on|start <name>`: Spawns the service in the background, detached from the terminal, and records its PID. Fails if the process exits immediately after launch.
- `off|stop <name>`: Gracefully stops the service (SIGTERM), falling back to SIGKILL if necessary.
- `restart <name>`: Stops and then starts the service.
- `remove|rm [<name>]`: Stops the service and deletes its definition.
- Service names must match `^[A-Za-z0-9][A-Za-z0-9._-]*$`.

Behavior notes:
- Auto-mounts the distro if needed when starting a service.
- Records a precise PID-backed session entry in `state/<distro>/sessions/current.json`.
- `unmount --kill-sessions` natively detects and gracefully shuts down running services.
- For SSH-like services (`sshd`), `start`/`stop`/`restart` print copy-ready SSH connect commands for Termux (same phone), PC (same Wi-Fi), and different-Wi-Fi guidance.
- Human `<distro> service list` / `<distro> service status` prints SSH connect hints only for active SSH-like services.
- SSH hints also print a copy-ready password-change command for the SSH login account.
- If `remove` is called without a name in an interactive terminal, it shows a numbered service picker.
- `remove|rm` prints what it will remove (tracked session id + service definition file path) before deletion.
- Built-in catalog currently includes:
  - `desktop`: installs `state/<distro>/services/desktop.json`, `/usr/local/sbin/aurora-desktop-launch`, and `/etc/aurora-desktop/profile.{env,json}`. Supports `lxqt` and `xfce` profiles on installed distros that Aurora detects as Ubuntu-family (`apt`/`apt-get`) or Arch-family (`pacman`), including compatible local/custom installs. Other distros are unsupported. Requires `settings x11=true`. Install uses host RAM thresholds to recommend or block profiles before package installation. Re-running install with the same profile is safe and refreshes/repairs the managed desktop assets. Switching to a different profile requires `--reinstall` in non-interactive mode. Runtime is managed with the normal `<distro> service start|stop|restart|remove desktop` flow over Termux-X11.
  - `sshd`: installs `state/<distro>/services/sshd.json` + `/usr/local/sbin/aurora-sshd-start`.
  - `pcbridge`: installs `state/<distro>/services/pcbridge.json` + `/usr/local/sbin/aurora-pcbridge-start`.
- `zsh`: install-only (Arch Linux and Ubuntu ONLY; no service definition, no daemon). Detects the distro's package manager (pacman -> Arch, apt -> Ubuntu) and installs Zsh with zsh-autocomplete, zsh-autosuggestions, fzf, and fd. Upgrades system packages as part of install (pacman -Syu / apt upgrade). Configures `.zshrc`/`.zprofile` (prompt, completions, keybindings, aliases, and common user-local PATH), patches `.bashrc` for compatibility, and changes root's login shell. Idempotent: safe to run multiple times; Aurora refreshes its managed Zsh blocks while leaving user content outside those blocks intact, and updates plugins to latest. Since `zsh` is install-only, `<distro> service start/stop/restart/remove` do not apply to it. Other distros are not supported and will fail with an error. In TUI, selecting zsh install switches to live output mode.
- `pcbridge` is independent from `sshd` service and uses dedicated defaults (`ssh:2223`, `bootstrap-http:47077`).
- `pcbridge` uses dedicated host keys under `/etc/aurora-pcbridge/hostkeys` and does not regenerate `/etc/ssh/ssh_host_*` keys.
- If system SSH host keys are missing, `pcbridge` records a warning in `/etc/aurora-pcbridge/warnings.log`.
- Interactive `<distro> service start|restart pcbridge` shows options:
  - `f`: starts in pairing mode (SSH + bootstrap HTTP), then prints one-time WSL bootstrap command to install/setup `aurorafs`.
  - `c`: starts in pairing mode (SSH + bootstrap HTTP), then prints WSL cleanup command to remove `aurorafs` files/aliases (packages remain installed).
  - `s`: starts normal mode (SSH/SFTP only; no bootstrap HTTP/token).
- After selecting `f` or `c`, CLI/TUI keep the command open in a waiting task:
  - detects command usage and exits when setup/cleanup token is used from PC,
  - exits when token TTL auto-expires,
  - allows manual early expiry by typing `e` then Enter (`expire token now and end task`).
- In normal mode (`s`), if no paired key exists in `/etc/aurora-pcbridge/authorized_keys`, start/restart aborts with an instruction to rerun and choose `f` first.
- In TUI, selecting `service` action `start`/`stop`/`restart`/`remove` shows a service-name selector populated from `<distro> service list --json`.
- In TUI, selecting `service` action `install` shows a built-in selector populated from `<distro> service install --json`.
- In TUI, selecting built-in `desktop` reveals a `Desktop profile` selector backed by `<distro> service install desktop --profiles --json`.
- `<distro> service remove desktop` removes Aurora-managed desktop service/config assets only; it does not purge the desktop packages from the distro.

### `<distro> sessions [list|status|kill|kill-all] [args...]`

Inspects and manages tracked runtime sessions (login, exec, service) for a distro.

- `list`: Shows tracked sessions (default).
- `status`: Alias of `list`.
- `kill [<session_id>]`: Stops one session and removes it from tracking. If `<session_id>` is omitted in an interactive terminal, it shows a numbered session picker.
- `kill-all [--grace <sec>]`: Sends SIGTERM then SIGKILL (after grace) to all tracked sessions for the distro.
- `list --json`: emits JSON for scripting/TUI.

Behavior notes:
- Uses PID + starttime identity checks to avoid killing reused PIDs.
- `unmount --kill-sessions` still exists and remains the distro-wide teardown path.
- In TUI, `sessions` action `kill` uses a session selector populated from `<distro> sessions list --json` (stays inside TUI, no CLI picker handoff).
- Human `<distro> sessions list` / `<distro> sessions status` also prints SSH connect hints for active SSH-like services in that distro.

### `login <distro>`

Launches an interactive root shell session inside the selected distro.

- Without args: error (`login requires distro`).

Behavior notes:
- Auto-mounts the distro if needed.
- Launches root's configured login shell from `/etc/passwd` when present, falling back to bash or sh when needed.
- Auto-populates `/etc/resolv.conf` when missing/invalid using Android DNS props to improve apt/network reliability.
- Records a PID-backed session entry in `state/<distro>/sessions/current.json`.
- Stale session entries are auto-pruned.
- Leaves mounts active when the shell exits.

### `exec <distro> -- <cmd...>`

Executes a specific command or script inside the distro without opening a shell.

- Without args: error (`exec requires distro`).
- Requires `--` before the command.
- Command is mandatory.

Behavior notes:
- Auto-mounts the distro if needed.
- Executes argv-safe: arguments after `--` are passed directly (no `$*` re-join).
- Records a PID-backed session entry and removes it after completion.

### `mount [<distro>]`

Sets up the distro's virtual filesystems (proc, sys, dev) and shared Android storage binds.

- Without `<distro>`: shows installed distros and lets you pick one.
- Writes to `state/<distro>/mounts/current.log` for strict reverse unmounting.
- With `android_storage_bind=true`, auto-discovers storage via Android env vars (`EXTERNAL_STORAGE`, `SECONDARY_STORAGE`), `/sdcard` realpath, `/mnt/user/*/primary`, and `/storage/*` (excluding `emulated` and `self`) so changed multi-user/SD-card paths are bound automatically.
- Required mounts (`/dev`, `proc`, `sys`, `/dev/pts`, `/dev/shm`) are strict.
- Optional binds (Termux home/storage/data/full Android binds) are best-effort and warn on failure.
- For pacman-based distros, mount ensures `/etc/mtab` exists and disables pacman `CheckSpace` to avoid false low-space failures in Android chroot layouts.

### `unmount [<distro>] [--kill-sessions|--no-kill-sessions]`

Safely tears down distro mounts and optionally terminates active sessions to prevent data corruption.

- Without `<distro>`: shows installed distros and lets you pick one.
- When selecting distro interactively, asks whether to kill active sessions before unmount.
- `--kill-sessions`: terminate active tracked sessions before unmount.
- `--no-kill-sessions`: skip session termination step.
- If mounts are busy, attempts lazy unmount and reports a warning.
- Always prints a post-unmount removal check (`sessions`, `mount_entries`, `rootfs_mounts`, `safe_to_remove`).
- Returns non-zero if the distro is still not safe to remove.

### `confirm-unmount [<distro>] [--json]`

Evaluates if a distro is idle and fully safe to remove without performing any unmount actions.

- Without `<distro>`: shows installed distros and lets you pick one.
- Uses the same readiness logic as `status`: safe only when `sessions=0`, `mount_entries=0`, and `rootfs_mounts=0`.
- `--json`: emits a small JSON payload for scripting.
- Returns zero only when `safe_to_remove=true`.

### `backup [<distro>] [--out <dir>] [--mode full|rootfs|state]`

Creates a highly compressed snapshot archive of the distro's rootfs and internal state.

- Without `<distro>`: shows installed distros and lets you pick one.
- Default `--mode` is `full`.
- Default `--out` is `backups/<distro>-<mode>-<timestamp>.tar.zst` (or `.tar.xz` if zstd is unavailable).
- If `--out` is provided, it is always treated as an output directory. Backup writes into it using the default archive filename.

Behavior notes:
- Blocks if there are active sessions.
- Blocks if mounts are active when mode is `full` or `rootfs`.

### `restore [<distro>] [--file <backup.tar.zst|backup.tar.xz>]`

Reconstructs a distro from a previously created snapshot archive.

- Without `<distro>`: lists backup distros (from `backups/`) and lets you pick one.
- Without `--file <path>`: lists backup archives for the selected backup distro and lets you pick one.
- Restore requires that target distro does not already exist in `rootfs/` or `state/`.
- If restoring the same distro id again, remove the existing install first (`remove <distro>`), then run restore.

Behavior notes:
- Validates archive paths to prevent unsafe extraction.
- Rewrites distro state flags after restore.
- When restore includes rootfs data and succeeds, Aurora adds/updates the distro alias in managed Termux rc profile block(s) and prints which profile(s) were updated plus login hint.

### `settings [set <key> <value>] [--json]`

Configures system preferences like mounts, timeouts, and logging behavior.

- Without args: prints a table with `current`, `allowed`, `status`, and description.
- `--json`: prints merged schema + current values JSON.
- `set <key> <value>`: validates value against allowed type/range/choices, then writes atomically.

Allowed keys and values:
- `termux_home_bind`: `true|false` (default `false`)
- `android_storage_bind`: `true|false` (default `false`)
- `data_bind`: `true|false` (default `false`)
- `android_full_bind`: `true|false` (default `false`; binds core Android partitions plus detected `*_dlkm` and common vendor top-level mounts)
- `x11`: `true|false` (bind Termux-X11 socket + inject `DISPLAY=:0`; setting to `true` restarts display `:0`)
- `x11_dpi`: integer `96..480` (default `160`; exported as `QT_FONT_DPI` / `AURORA_X11_DPI`)
- `download_retries`: integer `1..10`
- `download_timeout_sec`: integer `5..300`
- `log_retention_days`: integer `1..365`

### `logs [--tail <N>]`

Displays recent action logs for debugging and system auditing.

- Without args: prints the last 120 lines.
- `--tail <N>`: prints the last N lines (`N` must be a positive integer).

### `clear-cache [--all|--older-than <days>] [--yes]`

Frees up device storage by deleting cached downloads and disposable runtime files.

- Without args: removes files older than 14 days.
- `--older-than <days>`: custom age cutoff (`days` must be a positive integer).
- `--all`: deletes cached tarballs, Aurora tmp workspace files, interrupted install staging directories, and stale runtime logs that are no longer attached to active mounts or desktop sessions.
- `--yes`: with `--all`, skips the typed confirmation prompt.
- `--all` does not remove backups, settings, installed distro state, or retained action logs.

### `remove [<distro>] [--full]`

Deletes an installed distro completely, including its rootfs, state, and optional cached files.

- Without `<distro>`: shows installed distros and lets you pick one from a numbered list.
- Requires yes/no confirmation before delete.
- `--full` also deletes cached tarballs matching `<distro>-*` in the cache directory.

Behavior notes:
- Kills active tracked sessions by default (via `unmount --kill-sessions`) before delete.
- Attempts unmount before deleting.
- If any sessions or mounts remain active under the distro rootfs after unmount attempt, remove aborts for safety.
- On successful remove, Aurora removes the distro alias from managed Termux rc profile block(s) and prints which profile(s) were updated.

### `nuke [--yes]`

DANGEROUS: Wipes all installed distros, backups, cache, and settings. Resets the application entirely.

- Danger: removes all runtime data under the currently resolved runtime root.
- Removes all installed distros, backups, cache, manifests, logs, settings, and lock/state files.
- Removes `aurora` launcher file(s).
- Intended remaining file is `bash path/to/chroot`.
- `--yes`: skip the interactive yes/no confirmation.

Behavior notes:
- Prints step-by-step progress messages.
- Kills active tracked sessions by default before unmount/removal.
- Uses unmount + mount verification safety checks.
- Aborts if sessions remain active, unmount fails, or any mounts remain active.
EOF_HELP
}

chroot_cmd_help() {
  chroot_help_render_full_text
}

chroot_help_raw_text() {
  cat <<'EOF_HELP_RAW'
Core

  chroot
  chroot help|-h|--help
  chroot help raw
  chroot init
  chroot doctor [--json] [--repair-locks]
  chroot distros [--refresh]
  chroot distros [--json] [--refresh]
  chroot distros --install <id> --version <release> [--refresh]
  chroot install-local <distro> --file <path> [--sha256 <hex>]
  chroot status [--all|--distro <id>] [--json] [--live]
  chroot login <distro>
  chroot exec <distro> -- <cmd...>
  chroot mount [<distro>]
  chroot unmount [<distro>] [--kill-sessions|--no-kill-sessions]
  chroot confirm-unmount [<distro>] [--json]
  chroot backup [<distro>] [--out <dir>] [--mode full|rootfs|state]
  chroot restore [<distro>] [--file <backup.tar|backup.tar.zst|backup.tar.xz>]
  chroot logs [--tail <N>]
  chroot clear-cache
  chroot clear-cache --older-than <days>
  chroot clear-cache --all [--yes|-y]
  chroot remove [<distro>] [--full]
  chroot nuke [--yes|-y]

Settings

  chroot settings
  chroot settings show|list
  chroot settings --json
  chroot settings set termux_home_bind <true|false>
  chroot settings set android_storage_bind <true|false>
  chroot settings set data_bind <true|false>
  chroot settings set android_full_bind <true|false>
  chroot settings set x11 <true|false>
  chroot settings set x11_dpi <96..480>
  chroot settings set download_retries <1..10>
  chroot settings set download_timeout_sec <5..300>
  chroot settings set log_retention_days <1..365>
  chroot settings set tor_rotation_min <1..120>
  chroot settings set tor_bootstrap_timeout_sec <10..600>

Service

  chroot <distro> service list|status [--json]
  chroot <distro> service add <name> <command>
  chroot <distro> service install
  chroot <distro> service install --json
  chroot <distro> service install --list
  chroot <distro> service install pcbridge
  chroot <distro> service install sshd
  chroot <distro> service install zsh
  chroot <distro> service install desktop --profiles --json
  chroot <distro> service install desktop [--profile <xfce|lxqt>] [--reinstall]
  chroot <distro> service on|start <name>
  chroot <distro> service off|stop <name>
  chroot <distro> service restart <name>
  chroot <distro> service remove|rm [<name>]

Sessions

  chroot <distro> sessions list|status [--json]
  chroot <distro> sessions kill [<session_id>]
  chroot <distro> sessions kill-all [--grace <sec>]

Tor

  chroot <distro> tor status [--json]
  chroot <distro> tor on|start [--configured [apps|exit]] [--no-lan-bypass]
  chroot <distro> tor off|stop
  chroot <distro> tor restart [--configured [apps|exit]] [--no-lan-bypass]
  chroot <distro> tor freeze
  chroot <distro> tor logs [--tail <N>]
  chroot <distro> tor newnym
  chroot <distro> tor doctor [--json]
  chroot <distro> tor apps list [--json] [--system|--unknown]
  chroot <distro> tor apps refresh [--json]
  chroot <distro> tor apps set "<query[,query...]>" <bypassed|tunneled>
  chroot <distro> tor exit list [--json]
  chroot <distro> tor exit refresh [--json]
  chroot <distro> tor exit set "<query[,query...]>" <selected|unselected>
  chroot <distro> tor exit set strict <on|off>
  chroot <distro> tor remove|rm [--yes]
EOF_HELP_RAW
}

chroot_help_render_raw_text() {
  local line
  local in_code=0
  local pending_blank=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      '')
        if (( pending_blank == 0 )); then
          printf '\n'
          pending_blank=1
        fi
        continue
        ;;
      Core|Settings|Service|Sessions|Tor)
        (( pending_blank == 0 )) || printf '\n'
        chroot_help_heading_block "$line" "-"
        printf '\n'
        pending_blank=0
        ;;
      *)
        printf '%s\n' "$line"
        pending_blank=0
        ;;
    esac
  done < <(chroot_help_raw_text)
}

chroot_cmd_help_raw() {
  chroot_help_render_raw_text
}

chroot_init_text() {
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

    pkg install -y bash coreutils curl tar python dialog zstd xz-utils x11-repo && pkg install -y termux-x11-nightly

─── Step 3: Restart Termux───────────────────────────────
  The `aurora` shortcut was created when you ran this command.
  You can now use `aurora` everywhere instead of the full path.

    aurora                      # launches the TUI
    aurora doctor               # verify system readiness
    aurora distros --refresh    # fetch latest distro catalog

  Use the TUI to browse distros, install, and manage everything.

═══════════════════════════════════════════════════════
EOF_INIT
}
