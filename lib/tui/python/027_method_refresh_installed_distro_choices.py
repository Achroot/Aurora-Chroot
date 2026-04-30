    def refresh_installed_distro_choices(self, show_error=False):
        payload = self.load_status_payload(show_error=show_error)
        choices = self.installed_choices_from_payload(payload or {})
        for command in ("tor", "service", "sessions", "login", "exec", "mount", "unmount", "backup", "remove"):
            self.set_choice_field_choices(command, "distro", choices, "<no installed distros>")
        if not choices:
            if self.active_command in ("tor", "mount", "unmount", "backup", "remove"):
                self.status(f"No installed distros available for {self.active_command}", "error")
            return False
        return True
