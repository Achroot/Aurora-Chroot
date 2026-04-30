    def choice_field_spec(self, command, field_id):
        spec = self.specs.get(command, {})
        for field in spec.get("fields", []):
            if field.get("id") == field_id:
                return field
        return None

