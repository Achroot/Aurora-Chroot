    def visible_fields(self):
        spec = self.get_spec(self.active_command)
        out = []
        for field in spec.get("fields", []):
            if self.field_visible(field):
                out.append(field)
        return out

