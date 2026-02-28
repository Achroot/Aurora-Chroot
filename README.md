<div align="center">

# Aurora Chroot

Universal chroot environment manager for rooted Android + Termux.

<p>
  <img alt="Platform" src="https://img.shields.io/badge/platform-Android%20%2B%20Termux-0f766e?style=flat-square">
  <img alt="Runtime" src="https://img.shields.io/badge/runtime-Bash%20%2B%20Python-1d4ed8?style=flat-square">
  <img alt="Distribution" src="https://img.shields.io/badge/distribution-GitHub%20Releases-111827?style=flat-square">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-7c3aed?style=flat-square">
</p>

</div>

Aurora Chroot is a release-first tool for installing, mounting, entering, backing up, restoring, and managing Linux chroot environments on Android. It ships as a single bundled `chroot` script for end users, while this repository keeps the source split into maintainable Bash and Python parts.

## Interface Preview

Aurora includes a keyboard-first TUI for distro browsing, runtime control, and settings management.

<table align="center">
  <tr>
    <td align="center">
      <a href="docs/screenshots/main-tui-menu.jpg">
        <img src="docs/screenshots/main-tui-menu.jpg" alt="Aurora main TUI menu" width="250">
      </a><br>
      <sub>Main TUI menu</sub>
    </td>
    <td align="center">
      <a href="docs/screenshots/live-distros.jpg">
        <img src="docs/screenshots/live-distros.jpg" alt="Aurora distro browser" width="250">
      </a><br>
      <sub>Live distro browser</sub>
    </td>
    <td align="center">
      <a href="docs/screenshots/settings.jpg">
        <img src="docs/screenshots/settings.jpg" alt="Aurora settings screen" width="250">
      </a><br>
      <sub>Integrated settings editor</sub>
    </td>
  </tr>
</table>

## Why Aurora Chroot

- Release-first distribution: users download one bundled `chroot` file from GitHub Releases.
- Built for rooted Android + Termux workflows rather than desktop Linux assumptions.
- Interactive TUI plus direct CLI commands.
- Session-aware mount, login, exec, service, and removal flows.
- Backup and restore support for full, rootfs-only, or state-only snapshots.
- Built-in service installers for `sshd`, `pcbridge`, and distro-specific `zsh` setup.
- Root-backend detection and preflight diagnostics through `doctor`.

## Install From A Release

1. Download `chroot` from the latest GitHub Release.
2. Save it anywhere on the phone.
3. Run `init` once and follow the printed setup instructions.

Example when downloaded to `/storage/emulated/0/Download/chroot`:

```bash
termux-setup-storage
bash /storage/emulated/0/Download/chroot init
```

Every time `chroot` is invoked using its full path, Aurora creates or updates the `aurora` launcher so it points to the current `chroot` location.

## Quick Start

Download `chroot` from the latest GitHub Release, then run the first-time setup flow in Termux:

```bash
termux-setup-storage
# bash path/to/your/chroot/location init
bash /storage/emulated/0/Download/chroot init
```

<p align="left">
  <a href="docs/screenshots/init.jpg">
    <img src="docs/screenshots/init.jpg" alt="Aurora init first-run setup screen" width="360">
  </a><br>
  <sub>First-run setup guide shown by <code>init</code></sub>
</p>

## Command Map

| Area | Commands |
| --- | --- |
| Setup and diagnostics | `init`, `doctor`, `settings`, `logs` |
| Distro lifecycle | `distros`, `install-local`, `remove`, `nuke` |
| Runtime access | `login`, `exec`, `mount`, `unmount`, `confirm-unmount` |
| State and operations | `status`, `sessions`, `service` |
| Data management | `backup`, `restore`, `clear-cache` |

For the full command reference, see [HELP.md](HELP.md).

## What The Repo Contains

- `main.sh`: CLI entrypoint.
- `lib/`: Bash implementation split by feature area.
- `lib/tui/python/`: embedded Python pieces used by the TUI.
- `docs/screenshots/`: UI screenshots used on the repo landing page.
- `tools/bundle.sh`: bundles the source tree into `dist/chroot`.
- `HELP.md`: full command documentation.

## Requirements

- Rooted Android device
- Termux installed
- Basic comfort with terminal and root-level operations

## Safety

> [!WARNING]
> Aurora uses root privileges and modifies mounts, filesystems, and running processes. Keep backups and use it only if you understand the risk profile of root-level tooling on Android.

## Documentation

- Command reference: [HELP.md](HELP.md)
- License: [LICENSE](LICENSE)

## License

Aurora Chroot is licensed under MIT. See [LICENSE](LICENSE).
