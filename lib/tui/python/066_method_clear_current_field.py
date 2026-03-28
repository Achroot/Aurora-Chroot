    def clear_current_field(self):
        field = self.current_field()
        if not field:
            return
        ftype = field.get("type")
        if ftype == "bool":
            self.form_values[field["id"]] = False
            self.preview_scroll = 0
            return
        if ftype == "choice":
            self.form_values[field["id"]] = normalize_choice_value(field, None)
            self.preview_scroll = 0
            if self.active_command == "restore" and field.get("id") == "distro":
                self.refresh_restore_file_choices()
            if self.active_command == "service" and field.get("id") in ("distro", "action", "service_builtin"):
                self.handle_service_field_change(field.get("id"))
            if self.active_command == "sessions" and field.get("id") in ("distro", "action"):
                self.refresh_session_choices(show_error=False)
            return
        self.form_values[field["id"]] = ""
        self.preview_scroll = 0
