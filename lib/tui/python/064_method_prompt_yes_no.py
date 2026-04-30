    def prompt_yes_no(self, question, default_no=True):
        suffix = "[y/N]" if default_no else "[Y/n]"
        default_text = "no" if default_no else "yes"
        help_text = f"y: yes  n/Esc: no  Enter: {default_text}"
        try:
            self.stdscr.timeout(-1)
        except curses.error:
            pass

        while True:
            height, width = self.stdscr.getmaxyx()
            try:
                self.draw_current_state()
            except curses.error:
                pass

            box_w = min(72, max(24, width - 4))
            box_w = min(box_w, max(1, width))
            inner_w = max(1, box_w - 4)
            question_lines = wrap_lines(str(question or ""), inner_w) or [str(question or "")[:inner_w]]
            box_h = min(max(7, len(question_lines) + 5), max(3, height))
            visible_question_rows = max(1, box_h - 5)
            top = max(0, (height - box_h) // 2)
            left = max(0, (width - box_w) // 2)

            draw_box(
                self.stdscr,
                top,
                left,
                box_h,
                box_w,
                "CONFIRM",
                self.color(4),
                self.color(2, curses.A_BOLD),
            )

            y = top + 1
            for line in question_lines[:visible_question_rows]:
                addstr_clipped(self.stdscr, y, left + 2, line, inner_w, self.color(1, curses.A_BOLD))
                y += 1
            prompt_y = min(top + box_h - 3, max(top + 1, y + 1))
            help_y = min(top + box_h - 2, prompt_y + 1)
            addstr_clipped(self.stdscr, prompt_y, left + 2, suffix, inner_w, self.color(3, curses.A_BOLD))
            addstr_clipped(self.stdscr, help_y, left + 2, help_text, inner_w, self.color(6))

            try:
                self.stdscr.refresh()
            except curses.error:
                pass
            try:
                key = self.stdscr.getch()
            except curses.error:
                continue
            if key == curses.KEY_RESIZE:
                continue
            if key in (ord("y"), ord("Y")):
                return True
            if key in (ord("n"), ord("N"), 27):
                return False
            if key in (10, 13, curses.KEY_ENTER):
                return not default_no
