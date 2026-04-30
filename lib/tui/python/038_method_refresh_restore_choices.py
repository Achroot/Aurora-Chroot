    def refresh_restore_choices(self, show_error=False):
        payload = self.load_status_payload(show_error=show_error)
        self.restore_backups = self.collect_restore_backups(payload or {})
        distros = sorted(self.restore_backups.keys())
        distro_choices = [(d, f"{d} ({len(self.restore_backups.get(d, []))} backups)") for d in distros]
        self.set_choice_field_choices("restore", "distro", distro_choices, "<no backup distros>")
        self.refresh_restore_file_choices()

        if not distros:
            self.status("No backups found for restore", "error")
            return False
        return True

