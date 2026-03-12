    def refresh_service_choices(self, show_error=False):
        distro = str(self.form_values.get("distro", "")).strip()
        if not distro:
            self.service_payload_data = None
            self.set_choice_field_choices("service", "service_pick", [], "<select distro first>")
            return False

        cmd = [self.runner, "service", distro, "list", "--json"]
        rc, stdout, stderr, duration, rendered = self.capture_command(cmd)
        if rc != 0:
            self.service_payload_data = None
            self.set_choice_field_choices("service", "service_pick", [], "<failed to load services>")
            if show_error:
                self.show_result(rendered, stdout, stderr, rc, duration, back_state="form", rerun_cmd=cmd)
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

        cmd = [self.runner, "service", distro, "install", "--json"]
        rc, stdout, stderr, duration, rendered = self.capture_command(cmd)
        if rc != 0:
            self.service_builtin_payload_data = None
            self.set_choice_field_choices("service", "service_builtin", [], "<failed to load built-ins>")
            if show_error:
                self.show_result(rendered, stdout, stderr, rc, duration, back_state="form", rerun_cmd=cmd)
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

        cmd = [self.runner, "service", distro, "install", "desktop", "--profiles", "--json"]
        rc, stdout, stderr, duration, rendered = self.capture_command(cmd)
        if rc != 0:
            self.clear_desktop_profile_state()
            if show_error:
                self.show_result(rendered, stdout, stderr, rc, duration, back_state="form", rerun_cmd=cmd)
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

    def refresh_tor_status_payload(self, show_error=False):
        distro = str(self.form_values.get("distro", "")).strip()
        if not distro:
            self.tor_status_payload_data = None
            return False

        cmd = [self.runner, "tor", distro, "status", "--json"]
        rc, stdout, stderr, duration, rendered = self.capture_command(cmd)
        if rc != 0:
            self.tor_status_payload_data = None
            if show_error:
                self.show_result(rendered, stdout, stderr, rc, duration, back_state="form", rerun_cmd=cmd)
            else:
                self.status("Could not load Tor status", "error")
            return False

        try:
            payload = parse_json_payload(stdout)
        except Exception as exc:
            self.tor_status_payload_data = None
            parse_out = (stdout or "") + f"\nparse error: {exc}\n" + (stderr or "")
            if show_error:
                self.show_result(rendered, parse_out, "", 1, duration, back_state="form", rerun_cmd=cmd)
            else:
                self.status("Could not parse Tor status", "error")
            return False

        self.tor_status_payload_data = payload if isinstance(payload, dict) else None
        return isinstance(self.tor_status_payload_data, dict)

    def tor_status_payload(self):
        payload = self.tor_status_payload_data
        return payload if isinstance(payload, dict) else None

    def refresh_tor_apps_payload(self, show_error=False):
        distro = str(self.form_values.get("distro", "")).strip()
        if not distro:
            self.tor_apps_payload_data = None
            return False

        cmd = [self.runner, "tor", distro, "apps", "list", "--json"]
        rc, stdout, stderr, duration, rendered = self.capture_command(cmd)
        if rc != 0:
            self.tor_apps_payload_data = None
            if show_error:
                self.show_result(rendered, stdout, stderr, rc, duration, back_state="form", rerun_cmd=cmd)
            else:
                self.status("Could not load Tor apps", "error")
            return False

        try:
            payload = parse_json_payload(stdout)
        except Exception as exc:
            self.tor_apps_payload_data = None
            parse_out = (stdout or "") + f"\nparse error: {exc}\n" + (stderr or "")
            if show_error:
                self.show_result(rendered, parse_out, "", 1, duration, back_state="form", rerun_cmd=cmd)
            else:
                self.status("Could not parse Tor apps", "error")
            return False

        self.tor_apps_payload_data = payload if isinstance(payload, dict) else None
        return isinstance(self.tor_apps_payload_data, dict)

    def refresh_tor_exit_payload(self, show_error=False):
        distro = str(self.form_values.get("distro", "")).strip()
        if not distro:
            self.tor_exit_payload_data = None
            return False

        cmd = [self.runner, "tor", distro, "exit", "show", "--json"]
        rc, stdout, stderr, duration, rendered = self.capture_command(cmd)
        if rc != 0:
            self.tor_exit_payload_data = None
            if show_error:
                self.show_result(rendered, stdout, stderr, rc, duration, back_state="form", rerun_cmd=cmd)
            else:
                self.status("Could not load Tor exit config", "error")
            return False

        try:
            payload = parse_json_payload(stdout)
        except Exception as exc:
            self.tor_exit_payload_data = None
            parse_out = (stdout or "") + f"\nparse error: {exc}\n" + (stderr or "")
            if show_error:
                self.show_result(rendered, parse_out, "", 1, duration, back_state="form", rerun_cmd=cmd)
            else:
                self.status("Could not parse Tor exit config", "error")
            return False

        self.tor_exit_payload_data = payload if isinstance(payload, dict) else None
        return isinstance(self.tor_exit_payload_data, dict)

    def refresh_tor_country_payload(self, show_error=False):
        distro = str(self.form_values.get("distro", "")).strip()
        if not distro:
            self.tor_country_payload_data = None
            return False

        cmd = [self.runner, "tor", distro, "exit", "list", "--json"]
        rc, stdout, stderr, duration, rendered = self.capture_command(cmd)
        if rc != 0:
            self.tor_country_payload_data = None
            if show_error:
                self.show_result(rendered, stdout, stderr, rc, duration, back_state="form", rerun_cmd=cmd)
            else:
                self.status("Could not load country catalog", "error")
            return False

        try:
            payload = parse_json_payload(stdout)
        except Exception as exc:
            self.tor_country_payload_data = None
            parse_out = (stdout or "") + f"\nparse error: {exc}\n" + (stderr or "")
            if show_error:
                self.show_result(rendered, parse_out, "", 1, duration, back_state="form", rerun_cmd=cmd)
            else:
                self.status("Could not parse country catalog", "error")
            return False

        self.tor_country_payload_data = payload if isinstance(payload, list) else None
        return isinstance(self.tor_country_payload_data, list)

    def tor_apps_payload(self):
        payload = self.tor_apps_payload_data
        return payload if isinstance(payload, dict) else {}

    def tor_exit_payload(self):
        payload = self.tor_exit_payload_data
        return payload if isinstance(payload, dict) else {}

    def tor_country_payload(self):
        payload = self.tor_country_payload_data
        return payload if isinstance(payload, list) else []

    def refresh_tor_payloads(self, show_error=False):
        return self.refresh_tor_status_payload(show_error=show_error)

    def tor_app_choices(self, only_bypassed=None):
        payload = self.tor_apps_payload()
        rows = payload.get("packages", []) if isinstance(payload, dict) else []
        query = str(self.form_values.get("apps_query", "")).strip().lower()
        scope_filter = str(self.form_values.get("apps_scope", "all")).strip().lower() or "all"
        out = []
        for row in rows:
            if not isinstance(row, dict):
                continue
            package = str(row.get("package", "")).strip()
            if not package:
                continue
            bypassed = bool(row.get("bypassed"))
            scope = str(row.get("scope", "unknown")).strip().lower() or "unknown"
            if only_bypassed is True and not bypassed:
                continue
            if only_bypassed is False and bypassed:
                continue
            if scope_filter in ("user", "system") and scope != scope_filter:
                continue
            if query and query not in package.lower():
                continue
            uid = row.get("uid")
            shared = ""
            if row.get("shared_uid"):
                shared = f" shared:{row.get('uid_package_count') or '?'}"
            label = f"{package} [uid={uid}] {scope} {'bypass' if bypassed else 'tor'}{shared}"
            out.append((package, label))
        return out

    def tor_country_choices(self, selected_only=False):
        query = str(self.form_values.get("country_query", "")).strip().lower()
        selected = set(str(x).strip().lower() for x in self.tor_exit_payload().get("countries", []) if str(x).strip())
        out = []
        for row in self.tor_country_payload():
            if not isinstance(row, dict):
                continue
            code = str(row.get("code", "")).strip().lower()
            name = str(row.get("name", "")).strip()
            if not code:
                continue
            if selected_only and code not in selected:
                continue
            if query and query not in code and query not in name.lower():
                continue
            label = f"{code.upper()} -> {name}"
            if code in selected:
                label += " [selected]"
            out.append((code, label))
        return out

    def refresh_tor_dynamic_choices(self):
        action = str(self.form_values.get("action", "")).strip().lower()
        apps_action = str(self.form_values.get("apps_action", "")).strip().lower()
        exit_action = str(self.form_values.get("exit_action", "")).strip().lower()

        if action == "apps" and apps_action == "bypass-add":
            choices = [("", "<select app>")] + self.tor_app_choices(only_bypassed=False)
            self.set_choice_field_choices("tor", "app_pick", choices, "<no matching apps>")
        elif action == "apps" and apps_action == "bypass-remove":
            choices = [("", "<select bypassed app>")] + self.tor_app_choices(only_bypassed=True)
            self.set_choice_field_choices("tor", "app_pick", choices, "<no bypassed apps>")
        else:
            self.set_choice_field_choices("tor", "app_pick", [], "<select app>")

        if action == "exit" and exit_action == "add":
            choices = [("", "<select country>")] + self.tor_country_choices(selected_only=False)
            self.set_choice_field_choices("tor", "country_pick", choices, "<no matching countries>")
        elif action == "exit" and exit_action == "remove":
            choices = [("", "<select selected country>")] + self.tor_country_choices(selected_only=True)
            self.set_choice_field_choices("tor", "country_pick", choices, "<no selected countries>")
        else:
            self.set_choice_field_choices("tor", "country_pick", [], "<select country>")

    def handle_tor_field_change(self, field_id):
        if field_id == "distro":
            self.refresh_tor_status_payload(show_error=False)
            action = str(self.form_values.get("action", "")).strip().lower()
            if action == "apps":
                self.refresh_tor_apps_payload(show_error=False)
            elif action == "exit":
                self.refresh_tor_exit_payload(show_error=False)
                self.refresh_tor_country_payload(show_error=False)
        elif field_id == "action":
            action = str(self.form_values.get("action", "")).strip().lower()
            if action == "apps":
                self.refresh_tor_apps_payload(show_error=False)
            elif action == "exit":
                self.refresh_tor_exit_payload(show_error=False)
                self.refresh_tor_country_payload(show_error=False)
        self.refresh_tor_dynamic_choices()
