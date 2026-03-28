    def handle_mouse(self):
        try:
            _, x, y, _, bstate = curses.getmouse()
        except Exception:
            return False

        button4 = getattr(curses, "BUTTON4_PRESSED", 0x80000)
        button5 = getattr(curses, "BUTTON5_PRESSED", 0x200000)
        height, width = self.stdscr.getmaxyx()
        content_top = 2
        list_top = content_top + 1
        form_left = False
        form_right = False
        if self.state == "form" and height >= 14 and width >= 54:
            panel_top, panel_height, left_width, right_left, right_width = self.form_panel_layout(height, width)
            panel_bottom = panel_top + panel_height - 1
            form_left = (0 <= x < left_width) and (panel_top < y < panel_bottom)
            form_right = (right_left <= x < (right_left + right_width)) and (panel_top < y < panel_bottom)

        if bstate & button4:
            if self.state == "menu":
                self.move_menu(1)
            elif self.state == "form":
                if form_right or (self.form_panel_focus == "right" and not form_left):
                    self.form_panel_focus = "right"
                    self.scroll_preview(-1)
                else:
                    self.form_panel_focus = "left"
                    self.move_form(1)
            elif self.state == "distros":
                self.move_distros(1)
            elif self.state == "settings":
                if self.settings_rows:
                    self.settings_index = (self.settings_index + 1) % len(self.settings_rows)
            elif self.state == "tor_apps_tunneling":
                self.move_tor_apps_tunneling(1)
            elif self.state == "tor_exit_mode":
                self.move_tor_exit_mode(1)
            else:
                self.result_scroll = max(0, self.result_scroll - 1)
            return True

        if bstate & button5:
            if self.state == "menu":
                self.move_menu(-1)
            elif self.state == "form":
                if form_right or (self.form_panel_focus == "right" and not form_left):
                    self.form_panel_focus = "right"
                    self.scroll_preview(1)
                else:
                    self.form_panel_focus = "left"
                    self.move_form(-1)
            elif self.state == "distros":
                self.move_distros(-1)
            elif self.state == "settings":
                if self.settings_rows:
                    self.settings_index = (self.settings_index - 1) % len(self.settings_rows)
            elif self.state == "tor_apps_tunneling":
                self.move_tor_apps_tunneling(-1)
            elif self.state == "tor_exit_mode":
                self.move_tor_exit_mode(-1)
            else:
                view_height = max(1, self.stdscr.getmaxyx()[0] - 9)
                max_scroll = max(0, len(self.result_lines) - view_height)
                self.result_scroll = min(max_scroll, self.result_scroll + 1)
            return True

        if self.state == "tor_apps_tunneling":
            click_mask = curses.BUTTON1_CLICKED | curses.BUTTON1_RELEASED
            if bstate & click_mask:
                layout = self.tor_apps_tunneling_layout(height, width)
                filter_y = layout["top"] + 2
                if y == filter_y:
                    choice = self.tor_apps_tunneling_scope_from_x(x, layout)
                    if choice:
                        self.tor_apps_tunneling_scope = choice
                        self.tor_apps_tunneling_index = 0
                        self.tor_apps_tunneling_scroll = 0
                        return True
                row = self.tor_apps_tunneling_row_at(y, layout)
                if row is not None:
                    self.tor_apps_tunneling_index = row
                    self.toggle_current_tor_apps_tunneling()
                    return True
            elif bstate & curses.BUTTON1_PRESSED:
                layout = self.tor_apps_tunneling_layout(height, width)
                row = self.tor_apps_tunneling_row_at(y, layout)
                if row is not None:
                    self.tor_apps_tunneling_index = row
                    self.normalize_tor_apps_tunneling_view()
                    return True

        if self.state == "tor_exit_mode":
            click_mask = curses.BUTTON1_CLICKED | curses.BUTTON1_RELEASED
            if bstate & click_mask:
                layout = self.tor_exit_mode_layout(height, width)
                filter_y = layout["top"] + 2
                if y == filter_y:
                    choice = self.tor_exit_mode_filter_from_x(x, layout)
                    if choice:
                        self.tor_exit_mode_filter = choice
                        self.tor_exit_mode_index = 0
                        self.tor_exit_mode_scroll = 0
                        return True
                row = self.tor_exit_mode_row_at(y, layout)
                if row is not None:
                    self.tor_exit_mode_index = row
                    self.toggle_current_tor_exit_mode()
                    return True
            elif bstate & curses.BUTTON1_PRESSED:
                layout = self.tor_exit_mode_layout(height, width)
                row = self.tor_exit_mode_row_at(y, layout)
                if row is not None:
                    self.tor_exit_mode_index = row
                    self.normalize_tor_exit_mode_view()
                    return True

        if bstate & (curses.BUTTON1_CLICKED | curses.BUTTON1_PRESSED | curses.BUTTON1_RELEASED):
            if self.state == "menu":
                left_width = max(24, int(width * 0.33))
                if x < left_width and y >= list_top:
                    idx = self.menu_scroll + (y - list_top)
                    if 0 <= idx < len(self.commands):
                        self.menu_index = idx
                        self.open_selected_menu_command()
                        return True
            elif self.state == "form":
                if form_right:
                    self.form_panel_focus = "right"
                    return True
                if form_left and y >= list_top:
                    self.form_panel_focus = "left"
                    idx = (y - list_top)
                    fields = self.visible_fields()
                    if 0 <= idx < len(fields):
                        self.form_index = idx
                        self.edit_current_field()
                        return True
                    return True
            elif self.state == "distros":
                left_width = max(28, int(width * 0.42))
                if x < left_width and y >= list_top:
                    visible_rows = max(1, height - content_top - 5)
                    if self.distros_stage == "distros":
                        start = max(0, self.distros_index - visible_rows + 1)
                        idx = start + (y - list_top)
                        if 0 <= idx < len(self.distros_catalog):
                            self.distros_index = idx
                            self.distros_stage = "versions"
                            self.distros_version_index = 0
                            return True
                    elif self.distros_stage in ("versions", "detail"):
                        distro = self.current_distro()
                        versions = distro.get("versions", []) if distro else []
                        start = max(0, self.distros_version_index - visible_rows + 1)
                        idx = start + (y - list_top)
                        if 0 <= idx < len(versions):
                            self.distros_version_index = idx
                            self.distros_stage = "detail"
                            return True
            elif self.state == "settings":
                left_width = max(32, int(width * 0.46))
                if x < left_width and y >= list_top:
                    visible_rows = max(1, height - content_top - 5)
                    start = max(0, self.settings_index - visible_rows + 1)
                    idx = start + (y - list_top)
                    if 0 <= idx < len(self.settings_rows):
                        self.settings_index = idx
                        self.edit_setting_pending()
                        return True
        return False
