    def run(self):
        self.setup()
        while True:
            height, width = self.draw_current_state()
            self.stdscr.refresh()
            
            if height < 14 or width < 54:
                key = self.stdscr.getch()
                if key in (ord("q"), ord("Q")):
                    return
                continue

            try:
                key = self.stdscr.getch()
            except KeyboardInterrupt:
                return

            if key == curses.KEY_RESIZE:
                continue
            if key == curses.KEY_MOUSE:
                self.handle_mouse()
                continue

            if self.state == "menu":
                if not self.handle_menu_key(key):
                    return
            elif self.state == "form":
                if not self.handle_form_key(key):
                    return
            elif self.state == "distros":
                if not self.handle_distros_key(key):
                    return
            elif self.state == "settings":
                if not self.handle_settings_key(key):
                    return
            else:
                if not self.handle_result_key(key):
                    return


