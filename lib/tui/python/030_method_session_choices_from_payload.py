    def session_choices_from_payload(self, payload):
        rows = payload if isinstance(payload, list) else []
        out = []
        for row in rows:
            if not isinstance(row, dict):
                continue
            session_id = str(row.get("session_id", "")).strip()
            if not session_id:
                continue
            pid_raw = row.get("pid")
            pid = str(pid_raw).strip() if pid_raw is not None else "-"
            mode = str(row.get("mode", "")).strip() or "unknown"
            state = str(row.get("state", "")).strip() or "unknown"
            started = str(row.get("started_local", "")).strip() or str(row.get("started_at", "")).strip() or "-"
            command = str(row.get("command", "")).strip()
            label = f"{session_id} [{state}] pid:{pid} start:{started} mode:{mode}"
            if command:
                label = f"{label} cmd:{command}"
            out.append((session_id, label))
        out.sort(key=lambda item: item[0])
        return out
