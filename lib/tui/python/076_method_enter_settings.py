    def enter_settings(self):
        if self.load_settings(back_state="menu"):
            self.state = "settings"
            self.status("Settings loaded", "ok")

