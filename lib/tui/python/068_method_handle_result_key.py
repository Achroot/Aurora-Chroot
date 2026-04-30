    def handle_result_key(self, key):
        height, width = self.stdscr.getmaxyx()
        _content_top, content_height, _ = self.screen_content_layout(height, width)
        view_height = max(1, content_height - 4)
        max_scroll = max(0, len(self.result_lines) - view_height)
        info_mode = bool(getattr(self, "result_info_mode", False))

        if info_mode and key == curses.KEY_UP:
            self.result_scroll = max(0, self.result_scroll - 1)
            return True
        if info_mode and key == curses.KEY_DOWN:
            self.result_scroll = min(max_scroll, self.result_scroll + 1)
            return True
        if info_mode and key in (ord("k"), ord("j"), ord("h"), ord("l")):
            return True
        if key in (curses.KEY_UP, ord("k")):
            self.result_scroll = max(0, self.result_scroll - 1)
            return True
        if key in (curses.KEY_DOWN, ord("j")):
            self.result_scroll = min(max_scroll, self.result_scroll + 1)
            return True
        if key in (curses.KEY_LEFT, ord("h"), ord("<")):
            self.result_hscroll = max(0, self.result_hscroll - self.hscroll_step())
            return True
        if key in (curses.KEY_RIGHT, ord("l"), ord(">")):
            max_line = max((len(l) for l in self.result_lines), default=0)
            view_width = max(1, width - 5)
            max_hscroll = max(0, max_line - view_width)
            self.result_hscroll = min(max_hscroll, self.result_hscroll + self.hscroll_step())
            return True
        if key == curses.KEY_PPAGE:
            self.result_scroll = max(0, self.result_scroll - view_height)
            return True
        if key == curses.KEY_NPAGE:
            self.result_scroll = min(max_scroll, self.result_scroll + view_height)
            return True
        if key == curses.KEY_HOME:
            self.result_scroll = 0
            return True
        if key == curses.KEY_END:
            self.result_scroll = max_scroll
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
            if self.result_back_state == "busybox":
                self.update_busybox_last_summary_from_result()
            self.state = self.result_back_state
            if self.state == "form":
                if self.active_command == "service":
                    self.refresh_service_choices(show_error=False)
                    self.refresh_service_builtin_choices(show_error=False)
                if self.active_command == "sessions":
                    self.refresh_session_choices(show_error=False)
            return True
        if key in (ord("q"), ord("Q")):
            if info_mode:
                self.state = self.result_back_state
                return True
            if self.result_back_state == "busybox":
                self.update_busybox_last_summary_from_result()
                self.state = "busybox"
                return True
            return False
        return True
