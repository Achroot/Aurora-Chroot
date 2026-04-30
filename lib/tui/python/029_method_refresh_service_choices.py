    def refresh_service_choices(self, show_error=False):
        distro = str(self.form_values.get("distro", "")).strip()
        if not distro:
            self.service_payload_data = None
            self.set_choice_field_choices("service", "service_pick", [], "<select distro first>")
            return False

        cmd = [self.runner, distro, "service", "list", "--json"]
        rc, stdout, stderr, duration, rendered, merged_output = self.capture_command(cmd)
        if rc != 0:
            self.service_payload_data = None
            self.set_choice_field_choices("service", "service_pick", [], "<failed to load services>")
            if show_error:
                self.show_result(rendered, stdout, stderr, rc, duration, back_state="form", rerun_cmd=cmd, merged_output=merged_output)
            else:
                self.status(f"Could not load services for {distro}", "error")
            return False

        try:
            payload = parse_json_payload(stdout)
        except Exception as exc:
            self.service_payload_data = None
            self.set_choice_field_choices("service", "service_pick", [], "<failed to parse services>")
            parse_out = (stdout or "") + f"\nparse error: {exc}\n" + (stderr or "")
            if show_error:
                self.show_result(rendered, parse_out, "", 1, duration, back_state="form", rerun_cmd=cmd)
            else:
                self.status(f"Could not parse services for {distro}", "error")
            return False

        self.service_payload_data = payload
        choices = self.service_choices_from_payload(payload)
        with_empty = [("", "<select service>")] + choices
        self.set_choice_field_choices("service", "service_pick", with_empty, "<no services>")
        if self.active_command == "service" and not choices:
            self.status(f"No services defined for {distro}", "info")
        return bool(choices)

    def refresh_service_builtin_choices(self, show_error=False):
        distro = str(self.form_values.get("distro", "")).strip()
        if not distro:
            self.service_builtin_payload_data = None
            self.set_choice_field_choices("service", "service_builtin", [], "<select distro first>")
            return False

        cmd = [self.runner, distro, "service", "install", "--json"]
        rc, stdout, stderr, duration, rendered, merged_output = self.capture_command(cmd)
        if rc != 0:
            self.service_builtin_payload_data = None
            self.set_choice_field_choices("service", "service_builtin", [], "<failed to load built-ins>")
            if show_error:
                self.show_result(rendered, stdout, stderr, rc, duration, back_state="form", rerun_cmd=cmd, merged_output=merged_output)
            else:
                self.status(f"Could not load built-in services for {distro}", "error")
            return False

        try:
            payload = parse_json_payload(stdout)
        except Exception as exc:
            self.service_builtin_payload_data = None
            self.set_choice_field_choices("service", "service_builtin", [], "<failed to parse built-ins>")
            parse_out = (stdout or "") + f"\nparse error: {exc}\n" + (stderr or "")
            if show_error:
                self.show_result(rendered, parse_out, "", 1, duration, back_state="form", rerun_cmd=cmd)
            else:
                self.status(f"Could not parse built-in services for {distro}", "error")
            return False

        self.service_builtin_payload_data = payload
        choices = self.service_builtin_choices_from_payload(payload)
        with_empty = [("", "<select built-in service>")] + choices
        self.set_choice_field_choices("service", "service_builtin", with_empty, "<no built-in services>")
        if self.active_command == "service" and self.form_values.get("action") == "install" and not choices:
            self.status("No built-in services available", "info")
        return bool(choices)

    def service_payload(self):
        payload = self.service_payload_data
        return payload if isinstance(payload, list) else []

    def service_builtin_payload(self):
        payload = self.service_builtin_payload_data
        return payload if isinstance(payload, list) else []

    def clear_desktop_profile_state(self):
        self.desktop_profile_payload_data = None
        self.set_choice_field_choices("service", "desktop_profile", [], "<select desktop first>")
        if self.active_command == "service" and "desktop_reinstall" in self.form_values:
            self.form_values["desktop_reinstall"] = False

    def desktop_profile_payload(self):
        if self.active_command != "service":
            return None
        action = str(self.form_values.get("action", "")).strip().lower()
        builtin = str(self.form_values.get("service_builtin", "")).strip().lower()
        if action != "install" or builtin != "desktop":
            return None
        payload = self.desktop_profile_payload_data
        return payload if isinstance(payload, dict) else None

    def desktop_profile_choices_from_payload(self, payload):
        rows = payload.get("profiles", []) if isinstance(payload, dict) else []
        out = []
        for row in rows:
            if not isinstance(row, dict):
                continue
            profile_id = str(row.get("id", "")).strip()
            profile_name = str(row.get("name", "")).strip() or profile_id
            if not profile_id:
                continue
            if row.get("recommended"):
                status = "recommended"
            elif row.get("blocked"):
                status = "blocked"
            elif row.get("can_install"):
                status = "allowed"
            elif not row.get("supported", True):
                status = "unsupported"
            else:
                status = "unavailable"
            reason = str(row.get("reason", "")).strip()
            label = f"{profile_id} -> {profile_name} [{status}]"
            if reason:
                label = f"{label} {reason}"
            out.append((profile_id, label))
        return out

    def refresh_desktop_profile_choices(self, show_error=False):
        distro = str(self.form_values.get("distro", "")).strip()
        action = str(self.form_values.get("action", "")).strip().lower()
        builtin = str(self.form_values.get("service_builtin", "")).strip().lower()
        if not distro or action != "install" or builtin != "desktop":
            self.clear_desktop_profile_state()
            return False

        cmd = [self.runner, distro, "service", "install", "desktop", "--profiles", "--json"]
        rc, stdout, stderr, duration, rendered, merged_output = self.capture_command(cmd)
        if rc != 0:
            self.clear_desktop_profile_state()
            if show_error:
                self.show_result(rendered, stdout, stderr, rc, duration, back_state="form", rerun_cmd=cmd, merged_output=merged_output)
            else:
                self.status(f"Could not load desktop profiles for {distro}", "error")
            return False

        try:
            payload = parse_json_payload(stdout)
        except Exception as exc:
            self.clear_desktop_profile_state()
            parse_out = (stdout or "") + f"\nparse error: {exc}\n" + (stderr or "")
            if show_error:
                self.show_result(rendered, parse_out, "", 1, duration, back_state="form", rerun_cmd=cmd)
            else:
                self.status(f"Could not parse desktop profiles for {distro}", "error")
            return False

        self.desktop_profile_payload_data = payload
        choices = self.desktop_profile_choices_from_payload(payload)
        with_empty = [("", "<select desktop profile>")] + choices
        self.set_choice_field_choices("service", "desktop_profile", with_empty, "<no desktop profiles>")
        if self.active_command == "service" and not choices:
            self.status("No desktop profiles available", "info")
        return bool(choices)

    def handle_service_field_change(self, field_id):
        if field_id == "distro":
            self.refresh_service_choices(show_error=False)
            self.refresh_service_builtin_choices(show_error=False)

        action = str(self.form_values.get("action", "")).strip().lower()
        builtin = str(self.form_values.get("service_builtin", "")).strip().lower()
        if action == "install" and builtin == "desktop":
            self.refresh_desktop_profile_choices(show_error=False)
        else:
            self.clear_desktop_profile_state()

    def refresh_tor_dynamic_choices(self):
        action = str(self.form_values.get("action", "")).strip().lower()
        _ = action

    def handle_tor_field_change(self, field_id):
        self.refresh_tor_dynamic_choices()
