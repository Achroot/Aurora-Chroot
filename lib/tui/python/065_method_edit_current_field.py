    def edit_current_field(self):
        field = self.current_field()
        if not field:
            return
        ftype = field.get("type")
        if ftype in ("bool", "choice"):
            self.cycle_field(field, 1)
            return
        fid = field["id"]
        current = self.form_values.get(fid, "")
        new_value = self.prompt_input(field["label"], current)
        self.form_values[fid] = new_value.strip()
        self.preview_scroll = 0
        if self.active_command == "tor":
            self.handle_tor_field_change(fid)
