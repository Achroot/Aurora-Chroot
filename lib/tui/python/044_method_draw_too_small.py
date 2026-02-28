    def draw_too_small(self, height, width):
        addstr_safe(self.stdscr, 1, 2, "Aurora Chroot", self.color(2, curses.A_BOLD))
        addstr_safe(self.stdscr, 3, 2, "Terminal is too small for this TUI.", self.color(5))
        addstr_safe(self.stdscr, 5, 2, "Resize terminal then retry.", self.color(1))
        addstr_safe(self.stdscr, height - 2, 2, "q: quit", self.color(4))

