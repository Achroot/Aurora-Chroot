    def handle_menu_key(self, key):
        selected = self.commands[self.menu_index] if self.commands else ""
        self.menu_panel_focus = "left"
        self.menu_left_hscroll = 0
        self.menu_detail_scroll = 0
        self.menu_detail_hscroll = 0

        if key in (9, curses.KEY_BTAB):
            return True
        if key in (curses.KEY_UP, ord("k")):
            self.move_menu(-1)
            return True
        if key in (curses.KEY_DOWN, ord("j")):
            self.move_menu(1)
            return True
        if key in (
            curses.KEY_LEFT,
            curses.KEY_RIGHT,
            curses.KEY_PPAGE,
            curses.KEY_NPAGE,
            curses.KEY_HOME,
            curses.KEY_END,
            ord("<"),
            ord(">"),
        ):
            return True
        if key in (10, 13, curses.KEY_ENTER):
            return self.open_selected_menu_command()
        if key in (ord("r"), ord("R")):
            if not self.main_menu_run_enabled(selected):
                return True
            if selected in ("distros", "settings", "busybox"):
                return self.open_selected_menu_command()
            self.set_active_command(selected)
            self.run_current_command()
            return True
        if key in (ord("q"), ord("Q")):
            return False
        return True
