    def read_positive_int(self, key, label, required=True):
        value = self.read_text(key)
        if not value:
            if required:
                raise ValueError(f"{label} is required")
            return None
        try:
            parsed = int(value)
        except ValueError as exc:
            raise ValueError(f"{label} must be numeric") from exc
        if parsed <= 0:
            raise ValueError(f"{label} must be > 0")
        return parsed

