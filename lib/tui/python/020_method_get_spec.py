    def get_spec(self, command):
        if command in self.specs:
            return self.specs[command]
        return {
            "fields": [{"id": "raw_args", "label": "Arguments", "type": "text", "default": ""}],
            "about": "Generic command runner for commands discovered in help text.",
        }

