    def run_selected_distro_version(self, action="install"):
        distro = self.current_distro()
        version = self.current_version()
        if not distro or not version:
            self.status("No distro/version selected", "error")
            return
        flag = "--install"
        if str(action or "").strip().lower() == "download":
            flag = "--download"
        cmd = [
            self.runner,
            "distros",
            flag,
            str(distro.get("id", "")),
            "--version",
            str(version.get("install_target", "") or version.get("release", "")),
        ]
        if flag == "--install":
            self.execute_command(cmd, back_state="distros", interactive=True)
            return
        self.execute_command_stream(cmd, back_state="distros")

    def install_selected_distro_version(self):
        self.run_selected_distro_version("install")

    def download_selected_distro_version(self):
        self.run_selected_distro_version("download")
