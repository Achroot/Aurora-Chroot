    def draw_running_screen(self, command_line, spinner_char=""):
        height, width = self.stdscr.getmaxyx()
        self.stdscr.erase()
        if self.screen_too_small(height, width):
            self.draw_too_small(height, width)
            return
        self.draw_header(height, width)
        content_top, content_height, _ = self.screen_content_layout(height, width)
        box_h = 7
        box_w = min(width - 2, max(40, len(command_line) + 6))
        top = max(content_top, content_top + max(0, (content_height - box_h) // 2))
        left = max(0, (width - box_w) // 2)
        draw_box(self.stdscr, top, left, box_h, box_w, f"RUNNING {spinner_char}".strip(), self.color(4), self.color(2, curses.A_BOLD))
        addstr_clipped(self.stdscr, top + 2, left + 2, "Executing command...", box_w - 4, self.color(3))
        addstr_clipped(self.stdscr, top + 3, left + 2, command_line, box_w - 4, self.color(1))
        self.draw_footer(height, width)
