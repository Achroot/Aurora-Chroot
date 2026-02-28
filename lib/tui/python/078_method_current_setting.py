    def current_setting(self):
        if not self.settings_rows:
            return None
        self.settings_index = max(0, min(self.settings_index, len(self.settings_rows) - 1))
        return self.settings_rows[self.settings_index]

