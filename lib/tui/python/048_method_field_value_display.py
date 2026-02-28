    def field_value_display(self, field):
        value = self.form_values.get(field["id"])
        ftype = field.get("type")
        if ftype == "bool":
            return "ON" if bool(value) else "OFF"
        if ftype == "choice":
            return choice_label(field, value)
        text = str(value).strip()
        return text if text else "<empty>"

