    def handle_settings_key(self, key):
        height, width = self.stdscr.getmaxyx()
        _content_top, content_height, _ = self.screen_content_layout(height, width)
        left_width = max(32, int(width * 0.46))
        right_left = left_width + 2
        right_width = width - right_left - 1
        detail_rows = self.settings_detail_rows_for_width(right_width)
        if key in (9, curses.KEY_BTAB):
            self.settings_panel_focus = "right" if self.settings_panel_focus != "right" else "left"
            return True
        if key in (curses.KEY_UP, ord("k")):
            if self.settings_panel_focus == "right":
                self.scroll_text_panel_vertical(
                    "settings_detail_scroll",
                    "settings_detail_hscroll",
                    detail_rows,
                    max(1, content_height - 2),
                    max(1, right_width - 4),
                    -1,
                )
            elif self.settings_rows:
                self.settings_index = (self.settings_index - 1) % len(self.settings_rows)
                self.reset_panel_scroll("settings_detail_scroll", "settings_detail_hscroll")
            return True
        if key in (curses.KEY_DOWN, ord("j")):
            if self.settings_panel_focus == "right":
                self.scroll_text_panel_vertical(
                    "settings_detail_scroll",
                    "settings_detail_hscroll",
                    detail_rows,
                    max(1, content_height - 2),
                    max(1, right_width - 4),
                    1,
                )
            elif self.settings_rows:
                self.settings_index = (self.settings_index + 1) % len(self.settings_rows)
                self.reset_panel_scroll("settings_detail_scroll", "settings_detail_hscroll")
            return True
        if key == curses.KEY_PPAGE and self.settings_panel_focus == "right":
            self.scroll_text_panel_vertical(
                "settings_detail_scroll",
                "settings_detail_hscroll",
                detail_rows,
                max(1, content_height - 2),
                max(1, right_width - 4),
                -1,
                page=True,
            )
            return True
        if key == curses.KEY_NPAGE and self.settings_panel_focus == "right":
            self.scroll_text_panel_vertical(
                "settings_detail_scroll",
                "settings_detail_hscroll",
                detail_rows,
                max(1, content_height - 2),
                max(1, right_width - 4),
                1,
                page=True,
            )
            return True
        if key in (curses.KEY_LEFT, ord("<")):
            if self.settings_panel_focus == "right":
                self.scroll_text_panel_horizontal(
                    "settings_detail_scroll",
                    "settings_detail_hscroll",
                    detail_rows,
                    max(1, content_height - 2),
                    max(1, right_width - 4),
                    -1,
                )
            else:
                self.scroll_text_panel_horizontal(
                    "settings_index",
                    "settings_left_hscroll",
                    self.settings_left_rows(),
                    max(1, content_height - 2),
                    max(1, left_width - 4),
                    -1,
                )
            return True
        if key in (curses.KEY_RIGHT, ord(">")):
            if self.settings_panel_focus == "right":
                self.scroll_text_panel_horizontal(
                    "settings_detail_scroll",
                    "settings_detail_hscroll",
                    detail_rows,
                    max(1, content_height - 2),
                    max(1, right_width - 4),
                    1,
                )
            else:
                self.scroll_text_panel_horizontal(
                    "settings_index",
                    "settings_left_hscroll",
                    self.settings_left_rows(),
                    max(1, content_height - 2),
                    max(1, left_width - 4),
                    1,
                )
            return True
        if key in (ord("h"),):
            self.cycle_setting_pending(-1)
            return True
        if key in (ord("l"),):
            self.cycle_setting_pending(1)
            return True
        if key in (10, 13, curses.KEY_ENTER, ord("e"), ord("E"), ord(" ")):
            self.edit_setting_pending()
            return True
        if key in (ord("c"), ord("C")):
            row = self.current_setting()
            if row:
                key_name = row.get("key", "")
                self.settings_pending[key_name] = str(row.get("current_text", ""))
            return True
        if key in (ord("a"), ord("A")):
            self.apply_current_setting()
            return True
        if key in (ord("r"), ord("R")):
            self.load_settings(back_state="settings")
            if self.state != "result":
                self.status("Settings refreshed", "ok")
            return True
        if key in (ord("b"), ord("B")):
            self.state = "menu"
            return True
        if key in (ord("q"), ord("Q")):
            return False
        return True
