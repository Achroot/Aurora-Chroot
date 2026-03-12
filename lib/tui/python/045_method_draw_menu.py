    def draw_menu(self, height, width):
        content_top = 2
        content_height = height - content_top - 3
        left_width = max(24, int(width * 0.33))
        right_left = left_width + 2
        right_width = width - right_left - 1

        draw_box(self.stdscr, content_top, 0, content_height, left_width, "COMMANDS", self.color(4), self.color(1, curses.A_BOLD))
        draw_box(self.stdscr, content_top, right_left, content_height, right_width, "DETAILS", self.color(4), self.color(1, curses.A_BOLD))

        list_top = content_top + 1
        visible = max(1, content_height - 2)
        if self.menu_index < self.menu_scroll:
            self.menu_scroll = self.menu_index
        if self.menu_index >= self.menu_scroll + visible:
            self.menu_scroll = self.menu_index - visible + 1

        for row in range(visible):
            idx = self.menu_scroll + row
            y = list_top + row
            if idx >= len(self.commands):
                break
            cmd = self.commands[idx]
            marker = "->" if idx == self.menu_index else "  "
            display_cmd = "tor-beta" if cmd == "tor" else cmd
            text = f"{marker} {display_cmd}"
            style = self.color(2, curses.A_BOLD) if idx == self.menu_index else self.color(0)
            addstr_clipped(self.stdscr, y, 2, text, left_width - 4, style)

        selected = self.commands[self.menu_index]
        section = self.get_section(selected)
        usage = section.get("usage", selected)
        summary = section.get("summary", "")

        y = content_top + 2
        addstr_clipped(self.stdscr, y, right_left + 2, usage, right_width - 4, self.color(2, curses.A_BOLD))
        y += 2
        for line in wrap_lines(summary, right_width - 4):
            if y >= content_top + content_height - 2:
                break
            addstr_clipped(self.stdscr, y, right_left + 2, line, right_width - 4, self.color(0))
            y += 1

        if selected == "distros" and y < content_top + content_height - 3:
            y += 1
            addstr_clipped(self.stdscr, y, right_left + 2, "Flow: distro -> version -> details -> install", right_width - 4, self.color(6))
        if selected == "settings" and y < content_top + content_height - 3:
            y += 1
            addstr_clipped(self.stdscr, y, right_left + 2, "Shows current value + allowed values per key.", right_width - 4, self.color(6))
