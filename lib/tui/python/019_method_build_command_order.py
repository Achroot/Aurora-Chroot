    def build_command_order(self):
        if getattr(self, "registry_commands", None):
            ordered = []
            for row in self.registry_commands:
                name = str(row.get("id", "")).strip()
                if name and name not in ordered:
                    ordered.append(name)
            if ordered:
                return ordered

        discovered = []
        for section in self.sections:
            name = section.get("title", "").strip()
            if name and name not in discovered:
                discovered.append(name)

        preferred = [
            "help",
            "init",
            "doctor",
            "distros",
            "install-local",
            "status",
            "tor",
            "service",
            "sessions",
            "login",
            "exec",
            "mount",
            "unmount",
            "backup",
            "restore",
            "settings",
            "logs",
            "clear-cache",
            "remove",
            "nuke",
        ]

        ordered = []
        for name in preferred:
            if (name in discovered or name in self.specs) and name not in ordered:
                ordered.append(name)

        for name in discovered:
            if name not in ordered:
                ordered.append(name)

        for name in self.specs:
            if name not in ordered:
                ordered.append(name)

        return ordered
