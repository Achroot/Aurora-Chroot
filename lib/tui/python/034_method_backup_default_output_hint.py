    def backup_default_output_hint(self):
        distro = self.read_text("distro") or "<distro>"
        mode = str(self.form_values.get("mode", "full") or "full")
        root = str(self.runtime_root_hint or self.distros_runtime_root or "<runtime-root>")
        return f"{root}/backups/{distro}-{mode}-<timestamp>.{self.backup_default_extension()}"
