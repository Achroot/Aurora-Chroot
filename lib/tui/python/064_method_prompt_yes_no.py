    def prompt_yes_no(self, question, default_no=True):
        height, width = self.stdscr.getmaxyx()
        while True:
            self.stdscr.move(height - 1, 0)
            self.stdscr.clrtoeol()
            suffix = "[y/N]" if default_no else "[Y/n]"
            addstr_clipped(self.stdscr, height - 1, 1, f"{question} {suffix}: ", width - 2, self.color(1))
            self.stdscr.refresh()
            key = self.stdscr.getch()
            if key in (ord("y"), ord("Y")):
                return True
            if key in (ord("n"), ord("N"), 27):
                return False
            if key in (10, 13, curses.KEY_ENTER):
                return not default_no

