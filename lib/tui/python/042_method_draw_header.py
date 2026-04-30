    def draw_header(self, height, width):
        mode = self.state.upper()
        if self.state == "distros":
            mode = f"DISTROS:{self.distros_stage.upper()}"
        elif self.state == "tor_apps_tunneling":
            mode = "TOR:APPS-TUNNELING"
        elif self.state == "tor_exit_mode":
            mode = "TOR:EXIT-TUNNELING"
        elif self.state == "info":
            mode = "INFO-HUB"
        title = "AURORA CHROOT CONTROL CENTER"
        runner_name = os.path.basename(self.runner) or self.runner

        addstr_safe(self.stdscr, 0, 0, " " * max(0, width - 1), self.color(4))
        addstr_clipped(self.stdscr, 0, 1, title, width - 2, self.color(2, curses.A_BOLD))
        if self.state == "menu":
            runtime_root = str(
                getattr(self, "runtime_root_hint", "")
                or getattr(self, "distros_runtime_root", "")
                or os.environ.get("CHROOT_TUI_RUNTIME_ROOT", "")
            ).strip()
            right_text = os.path.normpath(runtime_root) if runtime_root else "<runtime-root>"
        elif self.state == "info":
            right_text = f"MODE: {mode} | {self.info_header_status_text()} | runner: {runner_name}"
        else:
            right_text = f"MODE: {mode} | runner: {runner_name}"
        right_x = max(1, width - len(right_text) - 2)
        addstr_clipped(self.stdscr, 0, right_x, right_text, width - right_x - 1, self.color(1))
        addstr_safe(self.stdscr, 1, 0, "+" + "-" * (width - 2) + "+", self.color(4))
