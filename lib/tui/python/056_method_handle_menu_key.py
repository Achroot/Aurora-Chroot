    def handle_menu_key(self, key):
        if key in (curses.KEY_UP, ord("k")):
            self.move_menu(-1)
            return True
        if key in (curses.KEY_DOWN, ord("j")):
            self.move_menu(1)
            return True
        if key in (10, 13, curses.KEY_ENTER, curses.KEY_RIGHT):
            return self.open_selected_menu_command()
        if key in (ord("r"), ord("R")):
            selected = self.commands[self.menu_index]
            if selected in ("distros", "settings"):
                return self.open_selected_menu_command()
            self.set_active_command(selected)
            self.run_current_command()
            return True
        if key in (ord("q"), ord("Q")):
            return False
        return True

