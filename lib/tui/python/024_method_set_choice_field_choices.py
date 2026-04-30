    def set_choice_field_choices(self, command, field_id, choices, empty_label):
        field = self.choice_field_spec(command, field_id)
        if not field:
            return
        field["choices"] = choices if choices else [("", empty_label)]
        if self.active_command == command and field_id in self.form_values:
            current = self.form_values.get(field_id, "")
            self.form_values[field_id] = normalize_choice_value(field, current)

