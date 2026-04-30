    def command_preview(self):
        command = self.active_command
        if command == "tor" and str(self.form_values.get("action", "")).strip().lower() == "apps-tunneling":
            distro = str(self.form_values.get("distro", "")).strip() or "<distro>"
            cmd = [self.runner, distro, "tor", "apps", "list", "--json"]
            return " ".join(shlex.quote(part) for part in cmd), ""
        if command == "tor" and str(self.form_values.get("action", "")).strip().lower() == "exit-tunneling":
            distro = str(self.form_values.get("distro", "")).strip() or "<distro>"
            cmd = [self.runner, distro, "tor", "exit", "list", "--json"]
            return " ".join(shlex.quote(part) for part in cmd), ""
        try:
            args, _stdin_payload = self.build_command(command)
            if command == "nuke":
                args = args + ["--yes"]
            cmd = self.build_cli_command(command, args)
            return " ".join(shlex.quote(part) for part in cmd), ""
        except Exception as exc:
            if command in ("service", "sessions", "tor"):
                cmd = [self.runner, "<distro>", command]
            else:
                cmd = [self.runner, command]
            return " ".join(shlex.quote(part) for part in cmd), str(exc)
