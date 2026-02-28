    def draw_result(self, height, width):
        content_top = 2
        content_height = height - content_top - 3
        draw_box(self.stdscr, content_top, 0, content_height, width - 1, "COMMAND OUTPUT", self.color(4), self.color(1, curses.A_BOLD))

        addstr_clipped(self.stdscr, content_top + 1, 2, f"$ {self.result_command}", width - 5, self.color(2))
        meta = f"exit={self.result_exit_code}   duration={self.result_duration:.2f}s"
        meta_style = self.color(3) if self.result_exit_code == 0 else self.color(5, curses.A_BOLD)
        addstr_clipped(self.stdscr, content_top + 2, 2, meta, width - 5, meta_style)

        output_top = content_top + 3
        output_height = content_height - 4
        if output_height <= 0:
            return

        max_scroll = max(0, len(self.result_lines) - output_height)
        self.result_scroll = max(0, min(self.result_scroll, max_scroll))
        avail = width - 5
        for row in range(output_height):
            idx = self.result_scroll + row
            if idx >= len(self.result_lines):
                break
            line = self.result_lines[idx]
            if self.result_hscroll > 0:
                line = line[self.result_hscroll:]
            addstr_clipped(self.stdscr, output_top + row, 2, line, avail, self.color(0))

