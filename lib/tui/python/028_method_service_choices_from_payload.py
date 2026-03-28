    def service_choices_from_payload(self, payload):
        rows = payload if isinstance(payload, list) else []
        out = []
        for row in rows:
            if not isinstance(row, dict):
                continue
            name = str(row.get("name", "")).strip()
            if not name:
                continue
            state = str(row.get("state", "")).strip() or "unknown"
            pid = str(row.get("pid", "")).strip() or "-"
            command = str(row.get("command", "")).strip()
            label = f"{name} [{state}] pid:{pid}"
            if command:
                label = f"{label} cmd:{command}"
            out.append((name, label))
        out.sort(key=lambda item: item[0])
        return out

    def service_builtin_choices_from_payload(self, payload):
        rows = payload if isinstance(payload, list) else []
        out = []
        for row in rows:
            if not isinstance(row, dict):
                continue
            builtin_id = str(row.get("id", "")).strip()
            if not builtin_id:
                continue
            service_name = str(row.get("service_name", "")).strip() or builtin_id
            command = str(row.get("command", "")).strip()
            description = str(row.get("description", "")).strip()
            label = f"{builtin_id} -> {service_name}"
            if row.get("requires_profile"):
                label = f"{label} profile:required"
            if command:
                label = f"{label} cmd:{command}"
            if description:
                label = f"{label} ({description})"
            out.append((builtin_id, label))
        out.sort(key=lambda item: item[0])
        return out
