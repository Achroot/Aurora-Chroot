    def build_command(self, command):
        built = self.build_registry_command(command)
        if built is not None:
            return built

        args = []
        stdin_data = ""

        if command == "tor":
            distro = self.require_text("distro", "Installed distro")
            action = self.form_values.get("action", "status")
            args.append(distro)
            if action == "status":
                args.append("status")
                if self.form_values.get("json"):
                    args.append("--json")
            elif action in ("on", "restart"):
                args.append(action)
                run_mode = str(self.form_values.get("run_mode", "default")).strip().lower() or "default"
                if run_mode == "configured":
                    args.append("--configured")
                elif run_mode == "configured-apps":
                    args.extend(["--configured", "apps"])
                elif run_mode == "configured-exit":
                    args.extend(["--configured", "exit"])
                if self.form_values.get("no_lan_bypass"):
                    args.append("--no-lan-bypass")
            elif action in ("off", "stop"):
                args.append("off")
            elif action == "freeze":
                args.append("freeze")
            elif action == "doctor":
                args.append("doctor")
                if self.form_values.get("json"):
                    args.append("--json")
            elif action == "newnym":
                args.append("newnym")
            elif action == "apps-tunneling":
                args.extend(["apps", "list", "--json"])
            elif action == "exit-tunneling":
                args.extend(["exit", "list", "--json"])
            elif action == "remove":
                args.append("remove")
                args.append("--yes")
            return args, stdin_data

        if command == "service":
            distro = self.require_text("distro", "Installed distro")
            action = self.form_values.get("action", "list")
            args.extend([distro, action])
            if action in ("start", "stop", "restart"):
                svc_name = self.require_text("service_pick", "Service")
                svc_name = self.validate_service_name_value(svc_name, "Service")
                args.append(svc_name)
            elif action == "add":
                svc_name = self.require_service_name("service_name", "Service Name")
                svc_cmd = self.require_text("service_cmd", "Command")
                args.append(svc_name)
                args.append(svc_cmd)
            elif action == "install":
                builtin_id = self.require_text("service_builtin", "Built-in service")
                args.append(builtin_id)
                if str(builtin_id).strip().lower() == "desktop":
                    desktop_profile = self.require_text("desktop_profile", "Desktop profile")
                    args.extend(["--profile", desktop_profile])
                    if self.form_values.get("desktop_reinstall"):
                        args.append("--reinstall")
            elif action == "remove":
                svc_name = self.read_text("service_pick")
                if svc_name:
                    args.append(self.validate_service_name_value(svc_name, "Service"))
            return args, stdin_data

        if command == "sessions":
            distro = self.require_text("distro", "Installed distro")
            action = self.form_values.get("action", "list")
            args.extend([distro, action])
            if action == "list":
                if self.form_values.get("json"):
                    args.append("--json")
            elif action == "kill":
                session_id = self.require_text("session_pick", "Session")
                args.append(session_id)
            elif action == "kill-all":
                grace = self.read_text("grace")
                if grace:
                    parsed = self.read_positive_int("grace", "Grace seconds", required=True)
                    args.extend(["--grace", str(parsed)])
            return args, stdin_data

        if command == "exec":
            distro = self.require_text("distro", "Installed distro")
            command_text = self.require_text("command", "Command")
            try:
                parts = shlex.split(command_text)
            except ValueError as exc:
                raise ValueError(f"Command parse error: {exc}") from exc
            if not parts:
                raise ValueError("Command cannot be empty")
            args.extend([distro, "--"] + parts)
            return args, stdin_data

        if command == "restore":
            distro = self.require_text("distro", "Backup distro")
            file_path = self.read_text("file")
            if not file_path:
                file_path = self.default_restore_file_for_distro(distro)
            if not file_path:
                raise ValueError("Backup archive path is required")
            args.extend([distro, "--file", file_path])
            return args, stdin_data

        raw_args = self.read_text("raw_args")
        if raw_args:
            try:
                args.extend(shlex.split(raw_args))
            except ValueError as exc:
                raise ValueError(f"Argument parse error: {exc}") from exc
        return args, stdin_data

    def build_cli_command(self, command, args):
        if command in ("service", "sessions", "tor"):
            distro = args[0] if args else "<distro>"
            return [self.runner, distro, command] + list(args[1:])
        return [self.runner, command] + list(args)
