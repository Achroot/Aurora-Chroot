    def cycle_setting_pending(self, direction=1):
        row = self.current_setting()
        if not row:
            return
        key = row.get("key", "")
        choices = self.allowed_choices_for_setting(row)
        if not choices:
            return
        current = self.settings_pending.get(key, str(row.get("current_text", "")))
        if current not in choices:
            current = choices[0]
        idx = choices.index(current)
        idx = (idx + direction) % len(choices)
        self.settings_pending[key] = choices[idx]

