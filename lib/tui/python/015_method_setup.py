    def setup(self):
        try:
            curses.curs_set(0)
        except curses.error:
            pass
        # Use raw mode here so Ctrl-C can be forwarded from the live exec screen
        # to the child command instead of being handled by the terminal.
        try:
            curses.raw()
        except curses.error:
            try:
                curses.cbreak()
            except curses.error:
                pass
        self.stdscr.nodelay(False)
        self.stdscr.keypad(True)
        try:
            curses.mousemask(curses.ALL_MOUSE_EVENTS | curses.REPORT_MOUSE_POSITION)
        except Exception:
            pass
        if curses.has_colors():
            curses.start_color()
            curses.use_default_colors()
            curses.init_pair(1, curses.COLOR_CYAN, -1)
            curses.init_pair(2, curses.COLOR_YELLOW, -1)
            curses.init_pair(3, curses.COLOR_GREEN, -1)
            curses.init_pair(4, curses.COLOR_BLUE, -1)
            curses.init_pair(5, curses.COLOR_RED, -1)
            curses.init_pair(6, curses.COLOR_MAGENTA, -1)
            try:
                curses.init_pair(7, 39, -1)
            except Exception:
                curses.init_pair(7, curses.COLOR_BLUE, -1)
        self.status("Ready", "ok")
