    def form_panel_layout(self, height, width):
        content_top, content_height, _ = self.screen_content_layout(height, width)
        if self.active_command == "exec":
            left_width = max(24, (width - 3) // 2)
        else:
            left_width = max(28, int(width * 0.46))
        right_left = left_width + 2
        right_width = width - right_left - 1
        return content_top, content_height, left_width, right_left, right_width

    def draw_form(self, height, width):
        if self.active_command == "exec":
            self.draw_exec_form(height, width)
            return

        content_top, content_height, left_width, right_left, right_width = self.form_panel_layout(height, width)
        options_active = self.form_panel_focus != "right"
        preview_active = self.form_panel_focus == "right"

        draw_box(
            self.stdscr,
            content_top,
            0,
            content_height,
            left_width,
            f"OPTIONS: {self.active_command}{' [ACTIVE]' if options_active else ''}",
            self.color(2) if options_active else self.color(4),
            self.color(2, curses.A_BOLD) if options_active else self.color(1, curses.A_BOLD),
        )
        draw_box(
            self.stdscr,
            content_top,
            right_left,
            content_height,
            right_width,
            f"PREVIEW / DOCS{' [ACTIVE]' if preview_active else ''}",
            self.color(2) if preview_active else self.color(4),
            self.color(2, curses.A_BOLD) if preview_active else self.color(1, curses.A_BOLD),
        )

        fields = self.visible_fields()
        if self.form_index >= len(fields):
            self.form_index = max(0, len(fields) - 1)

        list_top = content_top + 1
        visible_rows = max(1, content_height - 2)
        for idx in range(min(len(fields), visible_rows)):
            field = fields[idx]
            y = list_top + idx
            marker = "->" if idx == self.form_index else "  "
            value_text = self.field_value_display(field)
            line = f"{marker} {field['label']}: {value_text}"
            if self.form_hscroll > 0:
                line = line[self.form_hscroll:]
            style = self.color(2, curses.A_BOLD) if idx == self.form_index else self.color(0)
            addstr_clipped(self.stdscr, y, 2, line, left_width - 4, style)

        if not fields:
            addstr_clipped(self.stdscr, list_top, 2, "No options for this command.", left_width - 4, self.color(6))

        self.draw_preview_panel(content_top, right_left, right_width, content_height)
