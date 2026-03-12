    def run_current_command(self):
        command = self.active_command
        if command == "help":
            lines = self.help_text.splitlines() or ["No help text available."]
            self.result_command = "embedded help"
            self.result_exit_code = 0
            self.result_duration = 0.0
            self.result_lines = lines
            self.result_scroll = 0
            self.result_hscroll = 0
            self.result_back_state = "form"
            self.result_rerun_cmd = None
            self.result_rerun_stdin = ""
            self.result_rerun_interactive = False
            self.state = "result"
            self.status("Rendered help text", "ok")
            return

        try:
            args, stdin_data = self.build_command(command)
        except Exception as exc:
            self.status(str(exc), "error")
            return

        if command == "remove":
            distro = args[0] if args else self.form_values.get("distro", "")
            if not self.prompt_yes_no(f"Remove distro '{distro}' now?", default_no=True):
                self.status("Remove canceled", "info")
                return
            stdin_data = "y\n"
        elif command == "tor" and len(args) >= 2 and args[1] == "remove":
            distro = args[0] if args else self.form_values.get("distro", "")
            if not self.prompt_yes_no(
                f"Remove Tor state/config/log/cache for distro '{distro}' and keep packages installed?",
                default_no=True,
            ):
                self.status("Tor remove canceled", "info")
                return
        elif command == "clear-cache" and "--all" in args:
            if not self.prompt_yes_no("Clear cached downloads and disposable runtime files?", default_no=True):
                self.status("Clear-cache canceled", "info")
                return
        elif command == "nuke":
            if not self.prompt_yes_no("DANGER: NUKE all Aurora data now?", default_no=True):
                self.status("Nuke canceled", "info")
                return
            args.append("--yes")

        cmd = [self.runner, command] + args
        if command == "service":
            action = str(self.form_values.get("action", "list"))
            svc_name = self.read_text("service_pick")
            if action == "remove" and not svc_name:
                self.execute_command_interactive(cmd, back_state="form")
                return
            if action in ("start", "restart") and str(svc_name).strip().lower() == "pcbridge":
                self.execute_command(cmd, stdin_data=stdin_data, back_state="form", interactive=True)
                return
            if action == "install" and str(self.form_values.get("service_builtin", "")).strip().lower() == "zsh":
                self.execute_command(cmd, stdin_data=stdin_data, back_state="form", interactive=True)
                return
        if command == "login":
            self.execute_command_interactive(cmd, back_state="form")
        elif command == "exec":
            self.execute_command(cmd, stdin_data=stdin_data, back_state="form", interactive=True)
        else:
            self.execute_command_stream(cmd, stdin_data=stdin_data, back_state="form")
            if command == "tor":
                self.refresh_tor_status_payload(show_error=False)
                action = str(self.form_values.get("action", "")).strip().lower()
                if action == "apps":
                    self.refresh_tor_apps_payload(show_error=False)
                elif action == "exit":
                    self.refresh_tor_exit_payload(show_error=False)
                    self.refresh_tor_country_payload(show_error=False)
                self.refresh_tor_dynamic_choices()
