    def require_text(self, key, label):
        value = self.read_text(key)
        if not value:
            raise ValueError(f"{label} is required")
        return value

