    def get_section(self, command):
        section = self.section_by_name.get(command)
        if section is not None:
            return section
        registry = getattr(self, "registry_command_by_id", {}).get(command)
        if registry is not None:
            raw_usage = registry.get("raw_usage", [])
            usage = command
            if isinstance(raw_usage, list) and raw_usage:
                usage = str(raw_usage[0] or "").strip() or command
                if usage.startswith("chroot "):
                    usage = usage[len("chroot "):]
            return {
                "title": command,
                "usage": usage,
                "summary": str(registry.get("summary", "") or "No additional docs found in bundled help text."),
                "lines": [],
            }
        spec = self.get_spec(command)
        return {
            "title": command,
            "usage": spec.get("usage", command),
            "summary": spec.get("about", "No additional docs found in bundled help text."),
            "lines": [],
        }
