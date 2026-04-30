    def validate_service_name_value(self, value, label):
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", value):
            raise ValueError(f"{label} has invalid format (use letters, numbers, ., _, -)")
        return value

