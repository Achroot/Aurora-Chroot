    def current_field(self):
        fields = self.visible_fields()
        if not fields:
            return None
        if self.form_index >= len(fields):
            self.form_index = len(fields) - 1
        return fields[self.form_index]

