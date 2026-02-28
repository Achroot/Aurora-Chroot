    def get_section(self, command):
        return self.section_by_name.get(
            command,
            {
                "title": command,
                "usage": command,
                "summary": "No additional docs found in HELP.md.",
                "lines": [],
            },
        )

