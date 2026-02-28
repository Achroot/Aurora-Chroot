    def draw_preview_panel(self, top, right_left, right_width, content_height):
        section = self.get_section(self.active_command)
        usage = section.get("usage", self.active_command)
        summary = section.get("summary", "")
        preview_text, preview_error = self.command_preview()
        default_lines = self.command_default_summary_lines(right_width - 4)

        y = top + 2
        addstr_clipped(self.stdscr, y, right_left + 2, usage, right_width - 4, self.color(2, curses.A_BOLD))
        y += 2
        addstr_clipped(self.stdscr, y, right_left + 2, "Run:", right_width - 4, self.color(6, curses.A_BOLD))
        y += 1
        for line in wrap_lines(preview_text, right_width - 4):
            if y >= top + content_height - 2:
                break
            addstr_clipped(self.stdscr, y, right_left + 2, line, right_width - 4, self.color(1))
            y += 1

        if preview_error and y < top + content_height - 2:
            y += 1
            for line in wrap_lines(f"Validation: {preview_error}", right_width - 4):
                if y >= top + content_height - 2:
                    break
                addstr_clipped(self.stdscr, y, right_left + 2, line, right_width - 4, self.color(5))
                y += 1

        if y < top + content_height - 2:
            y += 1
            addstr_clipped(self.stdscr, y, right_left + 2, "Summary:", right_width - 4, self.color(6, curses.A_BOLD))
            y += 1
            for line in wrap_lines(summary, right_width - 4):
                if y >= top + content_height - 2:
                    break
                addstr_clipped(self.stdscr, y, right_left + 2, line, right_width - 4, self.color(0))
                y += 1
            if default_lines and y < top + content_height - 2:
                y += 1
                for line in default_lines:
                    if y >= top + content_height - 2:
                        break
                    addstr_clipped(self.stdscr, y, right_left + 2, line, right_width - 4, self.color(1))
                    y += 1

