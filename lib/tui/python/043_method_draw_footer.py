    def main_menu_run_enabled(self, command):
        return str(command or "").strip() not in {
            "install-local",
            "service",
            "login",
            "exec",
            "mount",
            "unmount",
            "backup",
            "restore",
            "clear-cache",
            "remove",
            "nuke",
        }

    def footer_entries(self):
        if self.state == "menu":
            selected = self.commands[self.menu_index] if self.commands else ""
            entries = ["Up/Down: scroll", "Enter: open", "q: quit"]
            if self.main_menu_run_enabled(selected):
                entries.insert(2, "r: run")
            return entries
        if self.state == "form":
            if self.form_panel_focus == "right":
                return ["Tap/Tab: focus", "Up/Down/Pg: scroll docs", "< >: pan", "Enter: options", "r: run", "b: back"]
            if self.active_command == "exec":
                return ["Up/Down: move", "Tap/Tab: focus", "< >: pan", "Enter/e: edit", "r: run", "c: clear", "b: back"]
            return ["Up/Down: move", "Tap/Tab: focus", "< >: pan", "Enter: edit/toggle", "r: run", "c: clear", "b: back"]
        if self.state == "distros":
            if self.distros_stage == "distros":
                return ["Up/Down: scroll", "Tap/Tab: focus", "< >: pan", "Enter: versions", "r: refresh catalog", "b: menu", "q: quit"]
            if self.distros_stage == "versions":
                return ["Up/Down: scroll", "Tap/Tab: focus", "< >: pan", "Enter: details", "i: install", "d: download", "b: back"]
            return ["Up/Down: scroll", "Tap/Tab: focus", "< >: pan", "i: install", "d: download", "b: back", "q: quit"]
        if self.state == "install_local":
            entries = ["Up/Down: scroll", "Tap/Tab: focus", "< >: pan", "Enter: edit path", "r: rescan", "b: menu", "q: quit"]
            if self.current_install_local_entry() is not None:
                entries.insert(4, "i: install")
            return entries
        if self.state == "settings":
            return ["Up/Down: scroll", "Tap/Tab: focus", "< >: pan", "Enter: edit", "h/l: cycle", "a: apply", "b: menu"]
        if self.state == "busybox":
            return ["Up/Down: action", "< >: pan", "r: run", "b: menu", "q: quit"]
        if self.state == "tor_apps_tunneling":
            return ["Up/Down: scroll", "< >: tabs", "Space: toggle", "/: search", "s: save", "b: back"]
        if self.state == "tor_exit_mode":
            return ["Up/Down: scroll", "< >: tabs", "Space/Enter: toggle", "s: save", "b: back"]
        if self.state == "info":
            return ["Up/Down: scroll", "Tap/Tab: focus", "< >: pan", "r: refresh", "q: quit", "b: back"]
        if self.state == "result" and getattr(self, "result_info_mode", False):
            return ["Up/Down/Pg: scroll", "< >: pan", "r: refresh", "b/q: back"]
        return ["Up/Down/Pg: scroll", "< >: pan", "r: rerun", "b: back", "q: quit"]

    def footer_lines(self, width, entries=None):
        available = max(1, width - 2)
        items = self.footer_entries() if entries is None else entries
        lines = []
        current = ""

        for raw_item in items:
            item = str(raw_item or "").strip()
            if not item:
                continue

            if len(item) > available:
                if current:
                    lines.append(current)
                    current = ""
                wrapped = wrap_lines(item, available)
                if wrapped:
                    lines.extend(wrapped)
                else:
                    lines.append(item[:available])
                continue

            if not current:
                current = item
                continue

            candidate = f"{current}  {item}"
            if len(candidate) <= available:
                current = candidate
            else:
                lines.append(current)
                current = item

        if current:
            lines.append(current)

        return lines or [""]

    def footer_reserved_rows(self, width, entries=None):
        return len(self.footer_lines(width, entries=entries)) + 2

    def screen_content_layout(self, height, width, footer_entries=None):
        content_top = 2
        content_height = max(1, height - content_top - self.footer_reserved_rows(width, entries=footer_entries))
        footer_lines = self.footer_lines(width, entries=footer_entries)
        return content_top, content_height, footer_lines

    def minimum_layout_height(self, width, footer_entries=None):
        return len(self.footer_lines(width, entries=footer_entries)) + 13

    def screen_too_small(self, height, width, footer_entries=None):
        return width < 54 or height < self.minimum_layout_height(width, footer_entries=footer_entries)

    def draw_footer_lines(self, height, width, lines, include_status=False):
        border_y = height - len(lines) - 1
        addstr_safe(self.stdscr, border_y, 0, "+" + "-" * (width - 2) + "+", self.color(4))
        for idx, line in enumerate(lines):
            addstr_clipped(self.stdscr, border_y + 1 + idx, 1, line, width - 2, self.color(3))
        if include_status:
            self.draw_status_overlay(height, width)

    def draw_footer(self, height, width):
        self.draw_footer_lines(height, width, self.footer_lines(width), include_status=True)
