    def refresh_service_choices(self, show_error=False):
        distro = str(self.form_values.get("distro", "")).strip()
        if not distro:
            self.set_choice_field_choices("service", "service_pick", [], "<select distro first>")
            return False

        cmd = [self.runner, "service", distro, "list", "--json"]
        rc, stdout, stderr, duration, rendered = self.capture_command(cmd)
        if rc != 0:
            self.set_choice_field_choices("service", "service_pick", [], "<failed to load services>")
            if show_error:
                self.show_result(rendered, stdout, stderr, rc, duration, back_state="form", rerun_cmd=cmd)
            else:
                self.status(f"Could not load services for {distro}", "error")
            return False

        try:
            payload = parse_json_payload(stdout)
        except Exception as exc:
            self.set_choice_field_choices("service", "service_pick", [], "<failed to parse services>")
            parse_out = (stdout or "") + f"\nparse error: {exc}\n" + (stderr or "")
            if show_error:
                self.show_result(rendered, parse_out, "", 1, duration, back_state="form", rerun_cmd=cmd)
            else:
                self.status(f"Could not parse services for {distro}", "error")
            return False

        choices = self.service_choices_from_payload(payload)
        with_empty = [("", "<select service>")] + choices
        self.set_choice_field_choices("service", "service_pick", with_empty, "<no services>")
        if self.active_command == "service" and not choices:
            self.status(f"No services defined for {distro}", "info")
        return bool(choices)

    def refresh_service_builtin_choices(self, show_error=False):
        distro = str(self.form_values.get("distro", "")).strip()
        if not distro:
            self.set_choice_field_choices("service", "service_builtin", [], "<select distro first>")
            return False

        cmd = [self.runner, "service", distro, "install", "--json"]
        rc, stdout, stderr, duration, rendered = self.capture_command(cmd)
        if rc != 0:
            self.set_choice_field_choices("service", "service_builtin", [], "<failed to load built-ins>")
            if show_error:
                self.show_result(rendered, stdout, stderr, rc, duration, back_state="form", rerun_cmd=cmd)
            else:
                self.status(f"Could not load built-in services for {distro}", "error")
            return False

        try:
            payload = parse_json_payload(stdout)
        except Exception as exc:
            self.set_choice_field_choices("service", "service_builtin", [], "<failed to parse built-ins>")
            parse_out = (stdout or "") + f"\nparse error: {exc}\n" + (stderr or "")
            if show_error:
                self.show_result(rendered, parse_out, "", 1, duration, back_state="form", rerun_cmd=cmd)
            else:
                self.status(f"Could not parse built-in services for {distro}", "error")
            return False

        choices = self.service_builtin_choices_from_payload(payload)
        with_empty = [("", "<select built-in service>")] + choices
        self.set_choice_field_choices("service", "service_builtin", with_empty, "<no built-in services>")
        if self.active_command == "service" and self.form_values.get("action") == "install" and not choices:
            self.status("No built-in services available", "info")
        return bool(choices)
