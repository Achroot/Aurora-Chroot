    def handle_form_key(self, key):
        if key in (9, curses.KEY_BTAB):
            self.form_panel_focus = "right" if self.form_panel_focus != "right" else "left"
            return True
        height, width = self.stdscr.getmaxyx()
        _panel_top, content_height, left_width, _right_left, _right_width = self.form_panel_layout(height, width)
        fields = self.visible_fields()
        left_rows = []
        for field in fields:
            left_rows.append((f"{field.get('label', field.get('id', ''))}: {self.field_value_display(field)}", self.color(0)))
        if self.active_command == "exec":
            left_rows.append(("Command body:", self.color(6, curses.A_BOLD)))
            left_rows.extend(self.wrapped_panel_rows(self.read_text("command") or "<empty>", left_width - 4, self.color(1)))
        if key in (curses.KEY_LEFT, ord("<")):
            if self.form_panel_focus == "right":
                self.scroll_preview_horizontal(-1)
            else:
                self.scroll_text_panel_horizontal(
                    "form_index",
                    "form_hscroll",
                    left_rows,
                    max(1, content_height - 2),
                    max(1, left_width - 4),
                    -1,
                )
            return True
        if key in (curses.KEY_RIGHT, ord(">")):
            if self.form_panel_focus == "right":
                self.scroll_preview_horizontal(1)
            else:
                self.scroll_text_panel_horizontal(
                    "form_index",
                    "form_hscroll",
                    left_rows,
                    max(1, content_height - 2),
                    max(1, left_width - 4),
                    1,
                )
            return True

        if self.form_panel_focus == "right":
            if key in (curses.KEY_UP, ord("k")):
                self.scroll_preview(-1)
                return True
            if key in (curses.KEY_DOWN, ord("j")):
                self.scroll_preview(1)
                return True
            if key == curses.KEY_PPAGE:
                self.scroll_preview(-1, page=True)
                return True
            if key == curses.KEY_NPAGE:
                self.scroll_preview(1, page=True)
                return True
            if key == curses.KEY_HOME:
                self.preview_scroll = 0
                return True
            if key == curses.KEY_END:
                self.preview_scroll = self.preview_max_scroll()
                return True
            if key in (10, 13, curses.KEY_ENTER, ord("e"), ord("E"), ord(" ")):
                self.form_panel_focus = "left"
                return True
            if key in (ord("r"), ord("R")):
                self.run_current_command()
                return True
            if key in (ord("b"), ord("B")):
                self.state = "menu"
                return True
            if key in (ord("q"), ord("Q")):
                return False
            return True

        if key in (curses.KEY_UP, ord("k")):
            self.move_form(-1)
            return True
        if key in (curses.KEY_DOWN, ord("j")):
            self.move_form(1)
            return True
        if key in (ord("h"),):
            if self.active_command != "exec":
                field = self.current_field()
                if field:
                    self.cycle_field(field, -1)
            return True
        if key in (ord("l"),):
            if self.active_command != "exec":
                field = self.current_field()
                if field:
                    self.cycle_field(field, 1)
            return True
        if key in (10, 13, curses.KEY_ENTER, ord("e"), ord("E"), ord(" ")):
            self.edit_current_field()
            return True
        if key in (ord("c"), ord("C")):
            self.clear_current_field()
            return True
        if key in (ord("r"), ord("R")):
            self.run_current_command()
            return True
        if key in (ord("b"), ord("B")):
            self.state = "menu"
            return True
        if key in (ord("q"), ord("Q")):
            return False
        return True
