    def set_active_command(self, command):
        self.active_command = command
        self.form_panel_focus = "left"
        self.preview_scroll = 0
        self.service_payload_data = None
        self.service_builtin_payload_data = None
        self.desktop_profile_payload_data = None
        self.tor_status_payload_data = None
        self.tor_apps_payload_data = None
        self.tor_exit_payload_data = None
        self.tor_country_payload_data = None
        spec = self.get_spec(command)
        self.form_values = {}
        for field in spec.get("fields", []):
            value = field.get("default")
            if field.get("type") == "choice":
                value = normalize_choice_value(field, value)
            self.form_values[field["id"]] = value
        self.form_index = 0
        if command in ("tor", "service", "sessions", "login", "exec", "mount", "unmount", "confirm-unmount", "backup", "remove"):
            self.refresh_installed_distro_choices(show_error=False)
        if command == "service":
            self.refresh_service_choices(show_error=False)
            self.refresh_service_builtin_choices(show_error=False)
            self.clear_desktop_profile_state()
        if command == "sessions":
            self.refresh_session_choices(show_error=False)
        if command == "restore":
            self.refresh_restore_choices(show_error=False)
        if command == "tor":
            self.refresh_tor_status_payload(show_error=False)
            self.refresh_tor_dynamic_choices()
