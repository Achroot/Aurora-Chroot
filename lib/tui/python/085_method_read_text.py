    def read_text(self, key):
        return str(self.form_values.get(key, "")).strip()

