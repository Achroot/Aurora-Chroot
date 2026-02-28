    def command_preview(self):
        command = self.active_command
        try:
            args, _stdin_payload = self.build_command(command)
            if command == "nuke":
                args = args + ["--yes"]
            cmd = [self.runner, command] + args
            return " ".join(shlex.quote(part) for part in cmd), ""
        except Exception as exc:
            cmd = [self.runner, command]
            return " ".join(shlex.quote(part) for part in cmd), str(exc)

