    def cycle_field(self, field, direction=1):
        ftype = field.get("type")
        fid = field["id"]
        if ftype == "bool":
            self.form_values[fid] = not bool(self.form_values.get(fid))
            return
        if ftype == "choice":
            options = [opt[0] if isinstance(opt, tuple) else opt for opt in field.get("choices", [])]
            if not options:
                return
            current = self.form_values.get(fid)
            if current not in options:
                current = options[0]
            idx = options.index(current)
            idx = (idx + direction) % len(options)
            self.form_values[fid] = options[idx]
            if self.active_command == "restore" and fid == "distro":
                self.refresh_restore_file_choices()
            if self.active_command == "service" and fid == "distro":
                self.refresh_service_choices(show_error=False)
                self.refresh_service_builtin_choices(show_error=False)
            if self.active_command == "sessions" and fid in ("distro", "action"):
                self.refresh_session_choices(show_error=False)
