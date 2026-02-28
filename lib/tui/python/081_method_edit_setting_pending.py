    def edit_setting_pending(self):
        row = self.current_setting()
        if not row:
            return
        key = row.get("key", "")
        choices = self.allowed_choices_for_setting(row)
        if choices:
            self.cycle_setting_pending(1)
            return

        current = self.settings_pending.get(key, str(row.get("current_text", "")))
        allowed = row.get("allowed_text", "")
        label = f"{key} ({allowed})" if allowed else key
        new_value = self.prompt_input(label, current)
        self.settings_pending[key] = new_value.strip()

