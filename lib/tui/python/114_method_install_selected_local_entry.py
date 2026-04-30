    def install_selected_local_entry(self):
        entry = self.current_install_local_entry()
        if not entry:
            self.status("Select a local archive first", "error")
            return

        distro = str(entry.get("distro", "") or "").strip()
        file_path = str(entry.get("path", "") or "").strip()
        if not distro or not file_path:
            self.status("Selected archive is missing distro metadata", "error")
            return

        cmd = [self.runner, "install-local", distro, "--file", file_path]
        sha256 = str(entry.get("sha256", "") or "").strip()
        if sha256:
            cmd.extend(["--sha256", sha256])
        self.execute_command(cmd, back_state="install_local", interactive=True)
