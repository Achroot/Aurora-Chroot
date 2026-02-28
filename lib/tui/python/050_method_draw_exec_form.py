    def draw_exec_form(self, height, width):
        content_top = 2
        content_height = height - content_top - 3
        left_width = max(38, int(width * 0.60))
        right_left = left_width + 2
        right_width = width - right_left - 1

        draw_box(self.stdscr, content_top, 0, content_height, left_width, "EXEC WORKSPACE", self.color(4), self.color(1, curses.A_BOLD))
        draw_box(self.stdscr, content_top, right_left, content_height, right_width, "PREVIEW / DOCS", self.color(4), self.color(1, curses.A_BOLD))

        fields = self.visible_fields()
        if self.form_index >= len(fields):
            self.form_index = max(0, len(fields) - 1)

        list_top = content_top + 1
        visible_rows = max(1, content_height - 2)
        for idx in range(min(len(fields), visible_rows)):
            field = fields[idx]
            marker = "->" if idx == self.form_index else "  "
            value_text = self.field_value_display(field)
            label = field.get("label", field.get("id", ""))
            style = self.color(2, curses.A_BOLD) if idx == self.form_index else self.color(0)
            addstr_clipped(
                self.stdscr,
                list_top + idx,
                2,
                f"{marker} {label}: {value_text}",
                left_width - 4,
                style,
            )

        command_text = self.read_text("command")
        stdin_text = self.read_text("stdin_reply")

        y = list_top + min(len(fields), visible_rows) + 1
        if y < content_top + content_height - 2:
            addstr_clipped(self.stdscr, y, 2, "Command body:", left_width - 4, self.color(6, curses.A_BOLD))
            y += 1
            for line in wrap_lines(command_text or "<empty>", left_width - 4):
                if y >= content_top + content_height - 2:
                    break
                addstr_clipped(self.stdscr, y, 2, line, left_width - 4, self.color(1))
                y += 1

        if y < content_top + content_height - 2:
            y += 1
            addstr_clipped(self.stdscr, y, 2, "STDIN payload:", left_width - 4, self.color(6, curses.A_BOLD))
            y += 1
            preview = stdin_text if stdin_text else "<empty>"
            for line in wrap_lines(preview, left_width - 4):
                if y >= content_top + content_height - 2:
                    break
                addstr_clipped(self.stdscr, y, 2, line, left_width - 4, self.color(0))
                y += 1

        self.draw_preview_panel(content_top, right_left, right_width, content_height)

