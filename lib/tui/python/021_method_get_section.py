    def get_section(self, command):
        section = self.section_by_name.get(command)
        if section is not None:
            return section
        spec = self.get_spec(command)
        return {
            "title": command,
            "usage": spec.get("usage", command),
            "summary": spec.get("about", "No additional docs found in bundled help text."),
            "lines": [],
        }
