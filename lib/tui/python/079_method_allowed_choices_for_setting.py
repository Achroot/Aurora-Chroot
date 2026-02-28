    def allowed_choices_for_setting(self, row):
        if not row:
            return []
        stype = row.get("type")
        if stype == "bool":
            return ["true", "false"]
        if stype == "enum":
            choices = row.get("choices", [])
            if isinstance(choices, list):
                return [str(item) for item in choices]
        return []

