    def command_default_summary_lines(self, wrap_width):
        lines = []
        if self.active_command == "backup":
            lines.append(f"Default output when 'out' is empty: {self.backup_default_output_hint()}")
        elif self.active_command == "restore":
            distro = self.read_text("distro")
            default_file = self.default_restore_file_for_distro(distro)
            if default_file:
                lines.append(f"Default restore file when path is empty: {default_file}")
            else:
                lines.append("Default restore file when path is empty: <no backups for selected distro>")
        elif self.active_command == "service":
            action = self.form_values.get("action", "")
            builtin = str(self.form_values.get("service_builtin", "")).strip().lower()
            if action == "install" and builtin == "zsh":
                lines.append("Supported distros: Arch Linux and Ubuntu ONLY. Other distros are not supported.")
                lines.append("Installs: Zsh shell, zsh-autocomplete plugin, zsh-autosuggestions plugin, fzf, fd.")
                lines.append("Configures: .zshrc (prompt, completions, keybindings, aliases), bash-to-zsh handoff, root login shell.")
                lines.append("Packages are upgraded as part of install (pacman -Syu / apt upgrade).")
                lines.append("Install-only: this is NOT a background service. 'service start/stop/restart/remove' do not apply to zsh.")
                lines.append("Safe to re-run: existing .zshrc blocks are not overwritten. Plugins are updated to latest.")

        wrapped = []
        for line in lines:
            chunk = wrap_lines(line, wrap_width)
            if chunk:
                wrapped.extend(chunk)
            else:
                wrapped.append(line)
        return wrapped

