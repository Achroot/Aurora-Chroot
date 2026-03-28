    def move_form(self, delta):
        fields = self.visible_fields()
        if not fields:
            self.form_index = 0
            return
        self.form_index = (self.form_index + delta) % len(fields)

