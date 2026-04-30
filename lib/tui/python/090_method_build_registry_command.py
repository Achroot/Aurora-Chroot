    def build_registry_command(self, command):
        spec = self.registry_specs.get(command)
        if not isinstance(spec, dict):
            return None

        builder = spec.get("builder")
        if not isinstance(builder, dict):
            return None

        kind = str(builder.get("kind", "")).strip().lower()
        if not kind:
            return None

        args = []
        stdin_data = ""

        if kind == "help":
            if str(self.form_values.get("view", "guide")).strip().lower() == "raw":
                args.append("raw")
            return args, stdin_data

        if kind == "none":
            return args, stdin_data

        if kind == "doctor":
            if self.form_values.get("json"):
                args.append("--json")
            if self.form_values.get("repair"):
                args.append("--repair-locks")
            return args, stdin_data

        if kind == "status":
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

        if kind == "logs":
            count = self.read_text("count")
            if count:
                parsed = self.read_positive_int("count", "Group count", required=True, max_value=50)
                args.append(str(parsed))
            return args, stdin_data

        if kind == "install-local":
            distro = self.require_text("distro", "Installed distro")
            file_path = self.read_text("file")
            if not file_path:
                file_path = self.default_install_local_path()
            if not file_path:
                raise ValueError("Tarball path or cache dir is required")
            sha256 = self.read_text("sha256")
            args.extend([distro, "--file", file_path])
            if sha256:
                args.extend(["--sha256", sha256])
            stdin_data = self.stdin_payload()
            return args, stdin_data

        if kind == "single-distro":
            args.append(self.require_text("distro", "Installed distro"))
            return args, stdin_data

        if kind == "unmount":
            args.append(self.require_text("distro", "Installed distro"))
            if self.form_values.get("kill_sessions"):
                args.append("--kill-sessions")
            return args, stdin_data

        if kind == "backup":
            distro = self.require_text("distro", "Installed distro")
            args.append(distro)
            mode = self.form_values.get("mode", "full")
            if mode and mode != "full":
                args.extend(["--mode", mode])
            out_path = self.read_text("out")
            if out_path:
                args.extend(["--out", out_path])
            return args, stdin_data

        if kind == "remove":
            distro = self.read_text("distro")
            if not distro:
                raise ValueError("No installed distros available for remove")
            args.append(distro)
            if self.form_values.get("full"):
                args.append("--full")
            return args, stdin_data

        if kind == "clear-cache":
            return args, stdin_data

        return None
