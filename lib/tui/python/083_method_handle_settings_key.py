    def handle_settings_key(self, key):
        if key in (curses.KEY_UP, ord("k")):
            if self.settings_rows:
                self.settings_index = (self.settings_index - 1) % len(self.settings_rows)
            return True
        if key in (curses.KEY_DOWN, ord("j")):
            if self.settings_rows:
                self.settings_index = (self.settings_index + 1) % len(self.settings_rows)
            return True
        if key in (curses.KEY_LEFT, ord("h")):
            self.cycle_setting_pending(-1)
            return True
        if key in (curses.KEY_RIGHT, ord("l")):
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

