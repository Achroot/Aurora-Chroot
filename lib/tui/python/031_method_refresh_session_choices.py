    def refresh_session_choices(self, show_error=False):
        distro = str(self.form_values.get("distro", "")).strip()
        if not distro:
            self.set_choice_field_choices("sessions", "session_pick", [], "<select distro first>")
            return False

        cmd = [self.runner, distro, "sessions", "list", "--json"]
        rc, stdout, stderr, duration, rendered, merged_output = self.capture_command(cmd)
        if rc != 0:
            self.set_choice_field_choices("sessions", "session_pick", [], "<failed to load sessions>")
            if show_error:
                self.show_result(rendered, stdout, stderr, rc, duration, back_state="form", rerun_cmd=cmd, merged_output=merged_output)
            else:
                self.status(f"Could not load sessions for {distro}", "error")
            return False

        try:
            payload = parse_json_payload(stdout)
        except Exception as exc:
            self.set_choice_field_choices("sessions", "session_pick", [], "<failed to parse sessions>")
            parse_out = (stdout or "") + f"\nparse error: {exc}\n" + (stderr or "")
            if show_error:
                self.show_result(rendered, parse_out, "", 1, duration, back_state="form", rerun_cmd=cmd)
            else:
                self.status(f"Could not parse sessions for {distro}", "error")
            return False

        choices = self.session_choices_from_payload(payload)
        with_empty = [("", "<select session>")] + choices
        self.set_choice_field_choices("sessions", "session_pick", with_empty, "<no sessions>")
        if self.active_command == "sessions" and self.form_values.get("action") == "kill" and not choices:
            self.status(f"No tracked sessions for {distro}", "info")
        return bool(choices)
