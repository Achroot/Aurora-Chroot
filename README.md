<div align="center">

# Aurora Chroot

<p><strong>Release-First Chroot Management For Rooted Android + Termux</strong></p>

<p>
  <img alt="Platform" src="https://img.shields.io/badge/platform-Android%20%2B%20Termux-0f766e?style=flat-square">
  <img alt="Tor Support" src="https://img.shields.io/badge/Tor-Support-1d4ed8?style=flat-square">
  <img alt="Desktop" src="https://img.shields.io/badge/desktop-XFCE%20%2F%20LXQt-f59e0b?style=flat-square">
  <a href="https://github.com/Achroot/Aurora-Chroot/releases">
    <img alt="GitHub Releases" src="https://img.shields.io/badge/Releases-GitHub-f43f5e?style=flat-square&logo=github&logoColor=white">
  </a>
  <a href="LICENSE">
    <img alt="License MIT" src="https://img.shields.io/badge/license-MIT-7c3aed?style=flat-square">
  </a>
</p>

<p>
  Release-first chroot management for rooted Android + Termux.<br>
  One bundled <code>chroot</code> file for distro installs, mounts, and login.<br>
  Managed services, desktop sessions, backup, restore, and diagnostics built in.<br>
  Keyboard-first, touch-friendly TUI, direct CLI, and distro-backed Tor.
</p>

</div>

## Table of Contents

<div align="center">

<pre>
<a href="#aurora-chroot">Aurora</a>
 /\
 /   \
<a href="#interface-preview">Preview</a>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href="#desktop-gui">Desktop</a>
 /________\
<a href="#why-aurora-chroot">Perks</a>&nbsp;&nbsp;&nbsp;&nbsp;<a href="#built-in-tor-support-beta">Tor</a>&nbsp;&nbsp;&nbsp;&nbsp;<a href="#step-by-step-first-setup">Setup</a>
/      |      \
<a href="#command-map">CLI</a>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href="#what-the-repo-contains">Files</a>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href="#requirements">Deps</a>
/        |        \
<a href="#safety">Safety</a>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href="#documentation">Docs</a>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href="#license">License</a>
</pre>

</div>

## Interface Preview

Aurora includes a keyboard-first TUI for distro browsing, runtime control, and settings management.

<table align="center">
  <tr>
    <td align="center">
      <a href="docs/screenshots/main-tui-menu.jpg">
        <img src="docs/screenshots/main-tui-menu.jpg" alt="Aurora main TUI menu" width="289" height="301">
      </a><br>
      <sub>Main TUI menu</sub>
    </td>
    <td align="center">
      <a href="docs/screenshots/live-distros.jpg">
        <img src="docs/screenshots/live-distros.jpg" alt="Aurora distro browser" width="274" height="286">
      </a><br>
      <sub>Live distro browser</sub>
    </td>
    <td align="center">
      <a href="docs/screenshots/settings.jpg">
        <img src="docs/screenshots/settings.jpg" alt="Aurora settings screen" width="268" height="279">
      </a><br>
      <sub>Integrated settings editor</sub>
    </td>
  </tr>
</table>

## Desktop GUI

Aurora can install and manage full Linux desktop sessions directly from the existing `service` flow.

<p align="center">
  <a href="docs/screenshots/Desktop.jpg">
    <img src="docs/screenshots/Desktop.jpg" alt="Aurora desktop GUI running through the desktop service" width="960">
  </a><br>
  <sub>Desktop GUI support managed through Aurora's built-in <code>desktop</code> service</sub>
</p>

## Why Aurora Chroot

- **Release-First Distribution:** Download one bundled `chroot` file from GitHub Releases.
- **Android-Focused Workflow:** Built for rooted Android + Termux rather than desktop Linux assumptions.
- **Flexible Runtime Control:** Interactive TUI plus direct CLI commands.
- **Desktop Sessions:** Built-in desktop GUI support for managed Linux desktop sessions.
- **Session-Aware Operations:** Mount, login, exec, service, and removal flows built around active runtime state.
- **Backup And Restore:** Full, rootfs-only, or state-only snapshot support.
- **Built-In Service Installers:** Includes `desktop`, `sshd`, `pcbridge`, and distro-specific `zsh` setup.
- **Diagnostics:** Root-backend detection and preflight checks through `doctor`.
- **Native Tor Support (Beta):**

## Built-In Tor Support (Beta)

- **CLI And TUI Control:** Manage Tor from direct commands or Aurora's built-in interface.
- **Automatic Tor Setup:** Installs and configures Tor inside supported distros when it is missing.
- **Apps Tunneling:** Save Android apps as tunneled or bypassed for configured Tor runs.
- **Exit Tunneling:** Save preferred exit countries with optional strict mode.
- **Runtime Tools:** Includes `status`, `doctor`, `logs`, `newnym`, and `freeze` for active Tor sessions.

<table align="center">
  <tr>
    <td align="center">
      <a href="docs/screenshots/Apps-Tunneling.jpg">
        <img src="docs/screenshots/Apps-Tunneling.jpg" alt="Aurora Tor Apps Tunneling screen" width="430">
      </a><br>
      <sub>Apps Tunneling</sub>
    </td>
    <td align="center">
      <a href="docs/screenshots/Exit-Tunneling.jpg">
        <img src="docs/screenshots/Exit-Tunneling.jpg" alt="Aurora Tor Exit Tunneling screen" width="430">
      </a><br>
      <sub>Exit Tunneling</sub>
    </td>
  </tr>
</table>

## Step-By-Step First Setup

<p>
  <a href="https://github.com/Achroot/Aurora-Chroot/releases/latest">
    <img alt="Open Latest Release" src="https://img.shields.io/badge/Open-Latest%20Release-f43f5e?style=for-the-badge&logo=github&logoColor=white">
  </a>
</p>

- Download `chroot` from the latest GitHub Release.
- Save it anywhere on the phone.

> [!TIP]
> Run the following commands in order inside Termux.

1. Grant storage permission.

    ```bash
    termux-setup-storage
    ```

2. Refresh mirrors.

    ```bash
    termux-change-repo   # mirror group > all mirrors
    ```

3. Update and upgrade Termux packages.

    ```bash
    pkg update && pkg upgrade -y
    ```

4. Install all required packages.

    ```bash
    pkg install -y bash coreutils curl tar python dialog zstd xz-utils x11-repo && pkg install -y termux-x11-nightly
    ```

5. Run the downloaded `chroot` script.

    ```bash
    bash /storage/emulated/0/Download/chroot
    ```

6. Restart Termux and use `aurora` to run commands.

    ```bash
    aurora
    ```

> [!NOTE]
> When `chroot` is invoked using its full path, Aurora creates or updates the `aurora` launcher so it points to the current `chroot` location.

<p align="center">
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
| State and operations | `status`, `tor` (beta), `sessions`, `service` |
| Data management | `backup`, `restore`, `clear-cache` |

For the full command reference, run `chroot help` or `chroot help raw`.

The `service` command also includes the built-in desktop GUI flow, alongside `sshd`, `pcbridge`, and `zsh`.

## What The Repo Contains

| Path | Use |
| --- | --- |
| `main.sh` | CLI entrypoint |
| `lib/` | Bash feature modules |
| <code>lib/<wbr>tui/<wbr>python/</code> | TUI Python components |
| <code>docs/<wbr>screenshots/</code> | Landing page screenshots |
| <code>tools/<wbr>bundle.sh</code> | Builds dist/chroot |
| <code>lib/<wbr>help.sh</code> | Help text, raw commands, and init copy |

## Requirements

- Rooted Android device
- Termux installed
- Basic comfort with terminal and root-level operations

## Safety

> [!WARNING]
> Aurora uses root privileges and modifies mounts, filesystems, and running processes. Keep backups and use it only if you understand the risk profile of root-level tooling on Android.

## Documentation

- Command reference: `chroot help` / `chroot help raw`
- License: [LICENSE](LICENSE)

## License

Aurora Chroot is licensed under MIT. See [LICENSE](LICENSE).
