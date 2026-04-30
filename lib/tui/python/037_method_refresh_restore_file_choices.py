    def refresh_restore_file_choices(self):
        distro = str(self.form_values.get("distro", "")).strip()
        default_file = self.default_restore_file_for_distro(distro)
        current = self.read_text("file")
        if not current or current not in self.restore_backups.get(distro, []):
            self.form_values["file"] = default_file

