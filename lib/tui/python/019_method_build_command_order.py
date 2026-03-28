    def build_command_order(self):
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
            "confirm-unmount",
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
