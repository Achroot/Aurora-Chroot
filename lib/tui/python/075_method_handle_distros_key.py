    def handle_distros_key(self, key):
        height, width = self.stdscr.getmaxyx()
        _content_top, content_height, _ = self.screen_content_layout(height, width)
        left_width = max(28, int(width * 0.42))
        right_left = left_width + 2
        right_width = width - right_left - 1
        if key in (9, curses.KEY_BTAB):
            self.distros_panel_focus = "right" if self.distros_panel_focus != "right" else "left"
            return True
        if key in (curses.KEY_UP, ord("k")):
            if self.distros_panel_focus == "right":
                rows = self.distros_detail_rows_for_width(right_width)
                self.scroll_text_panel_vertical(
                    "distros_detail_scroll",
                    "distros_detail_hscroll",
                    rows,
                    max(1, content_height - 2),
                    max(1, right_width - 4),
                    -1,
                )
            else:
                self.move_distros(-1)
            return True
        if key in (curses.KEY_DOWN, ord("j")):
            if self.distros_panel_focus == "right":
                rows = self.distros_detail_rows_for_width(right_width)
                self.scroll_text_panel_vertical(
                    "distros_detail_scroll",
                    "distros_detail_hscroll",
                    rows,
                    max(1, content_height - 2),
                    max(1, right_width - 4),
                    1,
                )
            else:
                self.move_distros(1)
            return True
        if key == curses.KEY_PPAGE and self.distros_panel_focus == "right":
            rows = self.distros_detail_rows_for_width(right_width)
            self.scroll_text_panel_vertical(
                "distros_detail_scroll",
                "distros_detail_hscroll",
                rows,
                max(1, content_height - 2),
                max(1, right_width - 4),
                -1,
                page=True,
            )
            return True
        if key == curses.KEY_NPAGE and self.distros_panel_focus == "right":
            rows = self.distros_detail_rows_for_width(right_width)
            self.scroll_text_panel_vertical(
                "distros_detail_scroll",
                "distros_detail_hscroll",
                rows,
                max(1, content_height - 2),
                max(1, right_width - 4),
                1,
                page=True,
            )
            return True
        if key in (curses.KEY_LEFT, ord("<")):
            if self.distros_panel_focus == "right":
                rows = self.distros_detail_rows_for_width(right_width)
                self.scroll_text_panel_horizontal(
                    "distros_detail_scroll",
                    "distros_detail_hscroll",
                    rows,
                    max(1, content_height - 2),
                    max(1, right_width - 4),
                    -1,
                )
            else:
                self.scroll_text_panel_horizontal(
                    "distros_index",
                    "distros_left_hscroll",
                    self.distros_left_rows(),
                    max(1, content_height - 2),
                    max(1, left_width - 4),
                    -1,
                )
            return True
        if key in (curses.KEY_RIGHT, ord(">")):
            if self.distros_panel_focus == "right":
                rows = self.distros_detail_rows_for_width(right_width)
                self.scroll_text_panel_horizontal(
                    "distros_detail_scroll",
                    "distros_detail_hscroll",
                    rows,
                    max(1, content_height - 2),
                    max(1, right_width - 4),
                    1,
                )
            else:
                self.scroll_text_panel_horizontal(
                    "distros_index",
                    "distros_left_hscroll",
                    self.distros_left_rows(),
                    max(1, content_height - 2),
                    max(1, left_width - 4),
                    1,
                )
            return True
        if key == curses.KEY_HOME and self.distros_panel_focus == "right":
            self.distros_detail_scroll = 0
            return True
        if key == curses.KEY_END and self.distros_panel_focus == "right":
            rows = self.distros_detail_rows_for_width(right_width)
            self.scroll_text_panel_vertical(
                "distros_detail_scroll",
                "distros_detail_hscroll",
                rows,
                max(1, content_height - 2),
                max(1, right_width - 4),
                len(rows),
            )
            return True
        if key in (ord("r"), ord("R")):
            self.load_distros_catalog(back_state="distros", refresh=True)
            if self.state != "result":
                self.status("Catalog refreshed", "ok")
            return True
        if key in (10, 13, curses.KEY_ENTER):
            if self.distros_stage == "distros":
                self.distros_stage = "versions"
                self.distros_version_index = 0
                self.reset_panel_scroll("distros_detail_scroll", "distros_detail_hscroll")
            elif self.distros_stage == "versions":
                self.distros_stage = "detail"
                self.reset_panel_scroll("distros_detail_scroll", "distros_detail_hscroll")
            return True
        if key in (ord("i"), ord("I")):
            if self.distros_stage in ("versions", "detail"):
                self.install_selected_distro_version()
            return True
        if key in (ord("d"), ord("D")):
            if self.distros_stage in ("versions", "detail"):
                self.download_selected_distro_version()
            return True
        if key in (ord("b"), ord("B")):
            if self.distros_stage == "detail":
                self.distros_stage = "versions"
            elif self.distros_stage == "versions":
                self.distros_stage = "distros"
            else:
                self.state = "menu"
            self.reset_panel_scroll("distros_detail_scroll", "distros_detail_hscroll")
            return True
        if key in (ord("q"), ord("Q")):
            return False
        return True
