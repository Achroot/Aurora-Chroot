    def handle_install_local_key(self, key):
        height, width = self.stdscr.getmaxyx()
        layout = self.install_local_layout(height, width)
        detail_rows = self.install_local_detail_rows_for_width(layout["right_width"])
        if key in (9, curses.KEY_BTAB):
            self.install_local_panel_focus = "right" if self.install_local_panel_focus != "right" else "left"
            return True
        if key in (curses.KEY_UP, ord("k")):
            if self.install_local_panel_focus == "right":
                self.scroll_text_panel_vertical(
                    "install_local_detail_scroll",
                    "install_local_detail_hscroll",
                    detail_rows,
                    max(1, layout["content_height"] - 2),
                    max(1, layout["right_width"] - 4),
                    -1,
                )
            else:
                self.move_install_local(-1)
            return True
        if key in (curses.KEY_DOWN, ord("j")):
            if self.install_local_panel_focus == "right":
                self.scroll_text_panel_vertical(
                    "install_local_detail_scroll",
                    "install_local_detail_hscroll",
                    detail_rows,
                    max(1, layout["content_height"] - 2),
                    max(1, layout["right_width"] - 4),
                    1,
                )
            else:
                self.move_install_local(1)
            return True
        if key == curses.KEY_PPAGE and self.install_local_panel_focus == "right":
            self.scroll_text_panel_vertical(
                "install_local_detail_scroll",
                "install_local_detail_hscroll",
                detail_rows,
                max(1, layout["content_height"] - 2),
                max(1, layout["right_width"] - 4),
                -1,
                page=True,
            )
            return True
        if key == curses.KEY_NPAGE and self.install_local_panel_focus == "right":
            self.scroll_text_panel_vertical(
                "install_local_detail_scroll",
                "install_local_detail_hscroll",
                detail_rows,
                max(1, layout["content_height"] - 2),
                max(1, layout["right_width"] - 4),
                1,
                page=True,
            )
            return True
        if key in (curses.KEY_LEFT, ord("<")):
            if self.install_local_panel_focus == "right":
                self.scroll_text_panel_horizontal(
                    "install_local_detail_scroll",
                    "install_local_detail_hscroll",
                    detail_rows,
                    max(1, layout["content_height"] - 2),
                    max(1, layout["right_width"] - 4),
                    -1,
                )
            else:
                self.scroll_text_panel_horizontal(
                    "install_local_index",
                    "install_local_left_hscroll",
                    self.install_local_left_rows(),
                    max(1, layout["content_height"] - 2),
                    max(1, layout["left_width"] - 4),
                    -1,
                )
            return True
        if key in (curses.KEY_RIGHT, ord(">")):
            if self.install_local_panel_focus == "right":
                self.scroll_text_panel_horizontal(
                    "install_local_detail_scroll",
                    "install_local_detail_hscroll",
                    detail_rows,
                    max(1, layout["content_height"] - 2),
                    max(1, layout["right_width"] - 4),
                    1,
                )
            else:
                self.scroll_text_panel_horizontal(
                    "install_local_index",
                    "install_local_left_hscroll",
                    self.install_local_left_rows(),
                    max(1, layout["content_height"] - 2),
                    max(1, layout["left_width"] - 4),
                    1,
                )
            return True
        if key == curses.KEY_HOME and self.install_local_panel_focus == "right":
            self.install_local_detail_scroll = 0
            return True
        if key == curses.KEY_END and self.install_local_panel_focus == "right":
            self.scroll_text_panel_vertical(
                "install_local_detail_scroll",
                "install_local_detail_hscroll",
                detail_rows,
                max(1, layout["content_height"] - 2),
                max(1, layout["right_width"] - 4),
                len(detail_rows),
            )
            return True
        if key in (ord("r"), ord("R")):
            self.load_install_local_entries(show_loading=True, select_first_entry=bool(self.install_local_entries))
            return True
        if key in (10, 13, curses.KEY_ENTER):
            current = self.install_local_path
            if self.install_local_index != 0:
                return True
            new_value = self.prompt_input("Tarball Path", current)
            self.install_local_path = str(new_value or "").strip()
            self.form_values["file"] = self.install_local_path
            self.load_install_local_entries(show_loading=True, select_first_entry=True)
            return True
        if key in (ord("i"), ord("I")):
            self.install_selected_local_entry()
            return True
        if key in (ord("b"), ord("B")):
            self.state = "menu"
            return True
        if key in (ord("q"), ord("Q")):
            return False
        return True
