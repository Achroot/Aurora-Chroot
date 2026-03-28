    def handle_result_key(self, key):
        view_height = max(1, self.stdscr.getmaxyx()[0] - 9)
        max_scroll = max(0, len(self.result_lines) - view_height)

        if key in (curses.KEY_UP, ord("k")):
            self.result_scroll = max(0, self.result_scroll - 1)
            return True
        if key in (curses.KEY_DOWN, ord("j")):
            self.result_scroll = min(max_scroll, self.result_scroll + 1)
            return True
        if key in (curses.KEY_LEFT, ord("h")):
            self.result_hscroll = max(0, self.result_hscroll - 4)
            return True
        if key in (curses.KEY_RIGHT, ord("l")):
            max_line = max((len(l) for l in self.result_lines), default=0)
            view_width = max(1, self.stdscr.getmaxyx()[1] - 5)
            max_hscroll = max(0, max_line - view_width)
            self.result_hscroll = min(max_hscroll, self.result_hscroll + 4)
            return True
        if key == curses.KEY_PPAGE:
            self.result_scroll = max(0, self.result_scroll - view_height)
            return True
        if key == curses.KEY_NPAGE:
            self.result_scroll = min(max_scroll, self.result_scroll + view_height)
            return True
        if key in (ord("r"), ord("R")):
            if self.result_rerun_cmd:
                self.execute_command(
                    self.result_rerun_cmd,
                    self.result_rerun_stdin,
                    back_state=self.result_back_state,
                    interactive=self.result_rerun_interactive,
                )
            return True
        if key in (ord("b"), ord("B")):
            self.state = self.result_back_state
            if self.state == "form":
                if self.active_command == "service":
                    self.refresh_service_choices(show_error=False)
                    self.refresh_service_builtin_choices(show_error=False)
                if self.active_command == "sessions":
                    self.refresh_session_choices(show_error=False)
            return True
        if key in (ord("q"), ord("Q")):
            return False
        return True
