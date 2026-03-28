    def install_selected_distro_version(self):
        distro = self.current_distro()
        version = self.current_version()
        if not distro or not version:
            self.status("No distro/version selected", "error")
            return
        cmd = [
            self.runner,
            "distros",
            "--install",
            str(distro.get("id", "")),
            "--version",
            str(version.get("release", "")),
        ]
        self.execute_command_stream(cmd, back_state="distros")

