# Chroot Command Help

This document mirrors `bash path/to/chroot help` and explains what each command does, including defaults and required arguments.

## Invocation

- `bash path/to/chroot <command> [args]`
- `aurora <command> [args]` (alias created in Termux)
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

### `help`

Displays the interactive TUI or a command-line reference guide.

- Without args: opens the TUI.
- In non-interactive mode: prints command summary text.

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

### `status [--all|--distro <id>] [--json] [--live]`

Displays an overview of installed distros, active sessions, and mount states.

- Without args: table for all installed distros, followed by per-session details (session id/pid/state/mode/start/cmd) for each distro with recorded sessions.
- `--all`: same as the default (all installed distros).
- `--distro <id>`: only report a single distro if installed.
- `--json`: JSON report including cache size and `safe_to_remove`/`rootfs_mounts`.
- `--live`: with `--json`, adds per-distro live diagnostics (`live.active_sessions`, `live.active_mounts`, stale counters, and raw log-entry counts).

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
- `download_retries`: integer `1..10`
- `download_timeout_sec`: integer `5..300`
- `log_retention_days`: integer `1..365`

### `logs [--tail <N>]`

Displays recent action logs for debugging and system auditing.

- Without args: prints the last 120 lines.
- `--tail <N>`: prints the last N lines (`N` must be a positive integer).

### `install-local <distro> --file <path> [--sha256 <hex>]`

Installs a custom Linux distribution directly from a local tarball archive.

- Without args: error (`install-local requires distro`).
- `--file <path>` is required.
- `--sha256 <hex>` is optional. If not provided, it requires typed confirmation to proceed without verification.

Behavior notes:
- Uses the same staging/extract flow as manifest-based installs.
- On successful install, Aurora adds/updates the distro alias in managed Termux rc profile block(s) and prints which profile(s) were updated plus login hint.

### `service <distro> [action] [args...]`

Manages persistent background services and daemons without a traditional init system.

- `list`: Shows a table of all defined services, their live status, and PIDs. (Default action).
- `status`: Alias of `list`.
- `add <name> <command>`: Creates a new service definition. The command must run the daemon in the foreground.
- `install [<builtin-id>]`: Installs a built-in service definition. With no id in interactive terminals, shows a picker. Use `install --json` to list built-ins for scripting/TUI.
- `start <name>`: Spawns the service in the background, detached from the terminal, and records its PID. Fails if the process exits immediately after launch.
- `stop <name>`: Gracefully stops the service (SIGTERM), falling back to SIGKILL if necessary.
- `restart <name>`: Stops and then starts the service.
- `remove [<name>]`: Stops the service and deletes its definition.
- Service names must match `^[A-Za-z0-9][A-Za-z0-9._-]*$`.

Behavior notes:
- Auto-mounts the distro if needed when starting a service.
- Records a precise PID-backed session entry in `state/<distro>/sessions/current.json`.
- `unmount --kill-sessions` natively detects and gracefully shuts down running services.
- For SSH-like services (`sshd`), `start`/`stop`/`restart` print copy-ready SSH connect commands for Termux (same phone), PC (same Wi-Fi), and different-Wi-Fi guidance.
- Human `service list`/`service status` prints SSH connect hints only for active SSH-like services.
- SSH hints also print a copy-ready password-change command for the SSH login account.
- If `remove` is called without a name in an interactive terminal, it shows a numbered service picker.
- `remove` prints what it will remove (tracked session id + service definition file path) before deletion.
- Built-in catalog currently includes:
  - `sshd`: installs `state/<distro>/services/sshd.json` + `/usr/local/sbin/aurora-sshd-start`.
  - `pcbridge`: installs `state/<distro>/services/pcbridge.json` + `/usr/local/sbin/aurora-pcbridge-start`.
  - `zsh`: install-only (Arch Linux and Ubuntu ONLY; no service definition, no daemon). Detects the distro's package manager (pacman → Arch, apt → Ubuntu) and installs Zsh with zsh-autocomplete, zsh-autosuggestions, fzf, and fd. Upgrades system packages as part of install (pacman -Syu / apt upgrade). Configures .zshrc (prompt, completions, keybindings, aliases), patches .bashrc for compatibility, sets up bash-to-zsh login handoff, and changes root's login shell. Idempotent: safe to run multiple times without overwriting existing .zshrc blocks (plugins are updated to latest). Since `zsh` is install-only, `service start/stop/restart/remove` do not apply to it. Other distros are not supported and will fail with an error. In TUI, selecting zsh install switches to live output mode.
- `pcbridge` is independent from `sshd` service and uses dedicated defaults (`ssh:2223`, `bootstrap-http:47077`).
- `pcbridge` uses dedicated host keys under `/etc/aurora-pcbridge/hostkeys` and does not regenerate `/etc/ssh/ssh_host_*` keys.
- If system SSH host keys are missing, `pcbridge` records a warning in `/etc/aurora-pcbridge/warnings.log`.
- Interactive `service <distro> start|restart pcbridge` shows options:
  - `f`: starts in pairing mode (SSH + bootstrap HTTP), then prints one-time WSL bootstrap command to install/setup `aurorafs`.
  - `c`: starts in pairing mode (SSH + bootstrap HTTP), then prints WSL cleanup command to remove `aurorafs` files/aliases (packages remain installed).
  - `s`: starts normal mode (SSH/SFTP only; no bootstrap HTTP/token).
- After selecting `f` or `c`, CLI/TUI keep the command open in a waiting task:
  - detects command usage and exits when setup/cleanup token is used from PC,
  - exits when token TTL auto-expires,
  - allows manual early expiry by typing `e` then Enter (`expire token now and end task`).
- In normal mode (`s`), if no paired key exists in `/etc/aurora-pcbridge/authorized_keys`, start/restart aborts with an instruction to rerun and choose `f` first.
- In TUI, selecting `service` action `start`/`stop`/`restart`/`remove` shows a service-name selector populated from `service <distro> list --json`.
- In TUI, selecting `service` action `install` shows a built-in selector populated from `service <distro> install --json`.

### `sessions <distro> [action] [args...]`

Inspects and manages tracked runtime sessions (login, exec, service) for a distro.

- `list`: Shows tracked sessions (default).
- `status`: Alias of `list`.
- `kill [<session_id>]`: Stops one session and removes it from tracking. If `<session_id>` is omitted in an interactive terminal, it shows a numbered session picker.
- `kill-all [--grace <sec>]`: Sends SIGTERM then SIGKILL (after grace) to all tracked sessions for the distro.
- `list --json`: emits JSON for scripting/TUI.

Behavior notes:
- Uses PID + starttime identity checks to avoid killing reused PIDs.
- `unmount --kill-sessions` still exists and remains the distro-wide teardown path.
- In TUI, `sessions` action `kill` uses a session selector populated from `sessions <distro> list --json` (stays inside TUI, no CLI picker handoff).
- Human `sessions list`/`sessions status` also prints SSH connect hints for active SSH-like services in that distro.

### `login <distro>`

Launches an interactive root shell session inside the selected distro.

- Without args: error (`login requires distro`).

Behavior notes:
- Auto-mounts the distro if needed.
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

### `clear-cache [--all|--older-than <days>] [--yes]`

Frees up device storage by deleting old or downloaded distro tarballs from the cache.

- Without args: removes files older than 14 days.
- `--older-than <days>`: custom age cutoff (`days` must be a positive integer).
- `--all`: deletes all cached tarballs.
- `--yes`: with `--all`, skips the typed confirmation prompt.
