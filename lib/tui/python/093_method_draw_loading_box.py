    def draw_loading_box(self, loading_text, height, width):
        box_h = 5
        box_w = min(width - 2, max(30, len(loading_text) + 6))
        top = max(2, (height - box_h) // 2)
        left = max(0, (width - box_w) // 2)
        draw_box(self.stdscr, top, left, box_h, box_w, "WORKING", self.color(4), self.color(2, curses.A_BOLD))
        addstr_clipped(self.stdscr, top + 2, left + 2, loading_text, box_w - 4, self.color(3))

