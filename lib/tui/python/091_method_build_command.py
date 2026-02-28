    def build_command(self, command):
        args = []
        stdin_data = ""

        if command == "help":
            return args, stdin_data

        if command == "init":
            return args, stdin_data

        if command == "doctor":
            if self.form_values.get("json"):
                args.append("--json")
            if self.form_values.get("repair"):
                args.append("--repair-locks")
            return args, stdin_data

        if command == "status":
            scope = self.form_values.get("scope", "all")
            if scope == "distro":
                args.extend(["--distro", self.require_text("distro", "Distro id")])
            else:
                args.append("--all")
            if self.form_values.get("json"):
                args.append("--json")
                if self.form_values.get("live"):
                    args.append("--live")
            return args, stdin_data

        if command == "logs":
            tail = self.read_text("tail")
            if tail:
                parsed = self.read_positive_int("tail", "Tail lines", required=True)
                args.extend(["--tail", str(parsed)])
            return args, stdin_data

        if command == "install-local":
            distro = self.require_text("distro", "Installed distro")
            file_path = self.require_text("file", "Tarball path")
            sha256 = self.read_text("sha256")
            args.extend([distro, "--file", file_path])
            if sha256:
                args.extend(["--sha256", sha256])
            stdin_data = self.stdin_payload()
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

        if command == "login":
            distro = self.require_text("distro", "Installed distro")
            args.append(distro)
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
            stdin_data = self.stdin_payload()
            return args, stdin_data

        if command == "mount":
            args.append(self.require_text("distro", "Installed distro"))
            return args, stdin_data

        if command == "unmount":
            args.append(self.require_text("distro", "Installed distro"))
            if self.form_values.get("kill_sessions"):
                args.append("--kill-sessions")
            return args, stdin_data

        if command == "confirm-unmount":
            args.append(self.require_text("distro", "Installed distro"))
            if self.form_values.get("json"):
                args.append("--json")
            return args, stdin_data

        if command == "backup":
            distro = self.require_text("distro", "Installed distro")
            args.append(distro)
            mode = self.form_values.get("mode", "full")
            if mode and mode != "full":
                args.extend(["--mode", mode])
            out_path = self.read_text("out")
            if out_path:
                args.extend(["--out", out_path])
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

        if command == "remove":
            distro = self.read_text("distro")
            if not distro:
                raise ValueError("No installed distros available for remove")
            args.append(distro)
            if self.form_values.get("full"):
                args.append("--full")
            return args, stdin_data

        if command == "clear-cache":
            strategy = self.form_values.get("strategy", "default")
            if strategy == "older":
                days = self.read_positive_int("days", "Days threshold", required=True)
                args.extend(["--older-than", str(days)])
            elif strategy == "all":
                args.extend(["--all", "--yes"])
            return args, stdin_data

        if command == "nuke":
            return args, stdin_data

        raw_args = self.read_text("raw_args")
        if raw_args:
            try:
                args.extend(shlex.split(raw_args))
            except ValueError as exc:
                raise ValueError(f"Argument parse error: {exc}") from exc
        return args, stdin_data
