    def draw_footer(self, height, width):
        hint = ""
        if self.state == "menu":
            hint = "Arrows: navigate  Enter: open  r: run  q: quit"
        elif self.state == "form":
            if self.form_panel_focus == "right":
                hint = "Tap/Tab: options  Arrows/PgUp/PgDn: scroll docs  Enter: options  r: run  b: back"
            elif self.active_command == "exec":
                hint = "Arrows: move  Enter/e: edit  Tap/Tab: preview  r: run  c: clear  b: back"
            else:
                hint = "Arrows: move  Enter: edit/toggle  Tap/Tab: preview  r: run  c: clear  b: back"
        elif self.state == "distros":
            if self.distros_stage == "distros":
                hint = "Arrows: select distro  Enter: versions  r: fetch latest  b: menu  q: quit"
            elif self.distros_stage == "versions":
                hint = "Arrows: select version  Enter: details  i: install  b: back  r: fetch latest"
            else:
                hint = "i: install this version  b: back  r: fetch latest  q: quit"
        elif self.state == "settings":
            hint = "Arrows: select key  Enter: edit  a: apply  c: reset  r: refresh  b: menu"
        else:
            hint = "Arrows/PgUp/PgDn: scroll  r: rerun  b: back  q: quit"

        addstr_safe(self.stdscr, height - 2, 0, "+" + "-" * (width - 2) + "+", self.color(4))
        addstr_clipped(self.stdscr, height - 1, 1, hint, width - 2, self.color(3))

        if self.status_message and (time.time() - self.status_time) < 6:
            status_attr = self.color(1)
            if self.status_kind == "error":
                status_attr = self.color(5, curses.A_BOLD)
            elif self.status_kind == "ok":
                status_attr = self.color(3, curses.A_BOLD)
            message = f"[{self.status_message}]"
            x = max(1, width - len(message) - 2)
            addstr_clipped(self.stdscr, height - 1, x, message, width - x - 1, status_attr)
