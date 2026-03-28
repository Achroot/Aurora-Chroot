    def preview_panel_lines(self, right_width):
        section = self.get_section(self.active_command)
        usage = section.get("usage", self.active_command)
        summary = section.get("summary", "")
        preview_text, preview_error = self.command_preview()
        default_lines = self.command_default_summary_lines(right_width - 4)

        rows = []

        def add_wrapped(text, attr):
            for line in wrap_lines(text, right_width - 4):
                rows.append((line, attr))

        add_wrapped(usage, self.color(2, curses.A_BOLD))
        rows.append(("", self.color(0)))
        rows.append(("Run:", self.color(6, curses.A_BOLD)))
        for line in wrap_lines(preview_text, right_width - 4):
            rows.append((line, self.color(1)))

        if preview_error:
            rows.append(("", self.color(0)))
            add_wrapped(f"Validation: {preview_error}", self.color(5))

        rows.append(("", self.color(0)))
        rows.append((("Details:" if default_lines else "Summary:"), self.color(6, curses.A_BOLD)))

        for line in default_lines:
            rows.append((line, self.color(1)))

        if summary:
            if default_lines:
                rows.append(("", self.color(0)))
                rows.append(("About:", self.color(6, curses.A_BOLD)))
            for line in wrap_lines(summary, right_width - 4):
                rows.append((line, self.color(0)))

        return rows

    def preview_max_scroll(self):
        height, width = self.stdscr.getmaxyx()
        if height < 14 or width < 54:
            return 0
        _, content_height, _, _, right_width = self.form_panel_layout(height, width)
        visible_height = max(1, content_height - 2)
        rows = self.preview_panel_lines(right_width)
        return max(0, len(rows) - visible_height)

    def scroll_preview(self, delta, page=False):
        step = max(1, self.stdscr.getmaxyx()[0] - 8) if page else 1
        max_scroll = self.preview_max_scroll()
        self.preview_scroll = max(0, min(max_scroll, self.preview_scroll + (delta * step)))

    def draw_preview_panel(self, top, right_left, right_width, content_height):
        rows = self.preview_panel_lines(right_width)
        visible_height = max(1, content_height - 2)
        max_scroll = max(0, len(rows) - visible_height)
        self.preview_scroll = max(0, min(self.preview_scroll, max_scroll))

        y = top + 1
        for idx in range(visible_height):
            row_idx = self.preview_scroll + idx
            if row_idx >= len(rows):
                break
            text, attr = rows[row_idx]
            addstr_clipped(self.stdscr, y + idx, right_left + 2, text, right_width - 4, attr)
