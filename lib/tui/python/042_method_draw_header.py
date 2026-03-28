    def draw_header(self, height, width):
        mode = self.state.upper()
        if self.state == "distros":
            mode = f"DISTROS:{self.distros_stage.upper()}"
        elif self.state == "tor_apps_tunneling":
            mode = "TOR:APPS-TUNNELING"
        elif self.state == "tor_exit_mode":
            mode = "TOR:EXIT-TUNNELING"
        title = "AURORA CHROOT CONTROL CENTER"
        runner_name = os.path.basename(self.runner) or self.runner

        addstr_safe(self.stdscr, 0, 0, " " * max(0, width - 1), self.color(4))
        addstr_clipped(self.stdscr, 0, 1, title, width - 2, self.color(2, curses.A_BOLD))
        right_text = f"MODE: {mode} | runner: {runner_name}"
        right_x = max(1, width - len(right_text) - 2)
        addstr_clipped(self.stdscr, 0, right_x, right_text, width - right_x - 1, self.color(1))
        addstr_safe(self.stdscr, 1, 0, "+" + "-" * (width - 2) + "+", self.color(4))
