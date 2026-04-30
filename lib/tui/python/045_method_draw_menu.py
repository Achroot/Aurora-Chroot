    def draw_menu(self, height, width):
        self.menu_panel_focus = "left"
        self.menu_left_hscroll = 0
        self.menu_detail_scroll = 0
        self.menu_detail_hscroll = 0

        content_top, content_height, _ = self.screen_content_layout(height, width)
        left_width = max(24, int(width * 0.33))
        right_left = left_width + 2
        right_width = width - right_left - 1

        draw_box(
            self.stdscr,
            content_top,
            0,
            content_height,
            left_width,
            "COMMANDS",
            self.color(2),
            self.color(2, curses.A_BOLD),
        )
        draw_box(
            self.stdscr,
            content_top,
            right_left,
            content_height,
            right_width,
            "DETAILS",
            self.color(4),
            self.color(1, curses.A_BOLD),
        )

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
            if cmd == "tor":
                display_cmd = "tor"
            elif cmd == "info":
                display_cmd = "info-hub"
            else:
                display_cmd = cmd
            text = f"{marker} {display_cmd}"
            style = self.color(2, curses.A_BOLD) if idx == self.menu_index else self.color(0)
            addstr_clipped(self.stdscr, y, 2, text, left_width - 4, style)

        selected = self.commands[self.menu_index]
        section = self.get_section(selected)
        usage = section.get("usage", selected)
        summary = section.get("summary", "")

        rows = [(usage, self.color(2, curses.A_BOLD)), ("", self.color(0))]
        rows.extend(self.wrapped_panel_rows(summary, right_width - 4, self.color(0)))

        if selected == "distros":
            rows.append(("", self.color(0)))
            rows.append(("Flow: distro -> version -> details -> install", self.color(6)))
        if selected == "settings":
            rows.append(("", self.color(0)))
            rows.append(("Shows current value + allowed values per key.", self.color(6)))

        self.draw_text_panel_rows(
            content_top,
            right_left,
            content_height,
            right_width,
            rows,
            "menu_detail_scroll",
            "menu_detail_hscroll",
        )
