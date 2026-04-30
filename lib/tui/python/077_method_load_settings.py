    def load_settings(self, back_state="settings"):
        cmd = [self.runner, "settings", "--json"]
        rc, stdout, stderr, duration, rendered, merged_output = self.capture_command(cmd)
        if rc != 0:
            self.show_result(rendered, stdout, stderr, rc, duration, back_state=back_state, rerun_cmd=cmd, merged_output=merged_output)
            return False
        try:
            payload = parse_json_payload(stdout)
        except Exception as exc:
            parse_out = (stdout or "") + f"\nparse error: {exc}\n" + (stderr or "")
            self.show_result(rendered, parse_out, "", 1, duration, back_state=back_state, rerun_cmd=cmd)
            return False

        rows = payload.get("settings", [])
        if not isinstance(rows, list):
            rows = []
        rows.sort(key=lambda x: str(x.get("key", "")))

        prev_key = None
        if self.settings_rows and 0 <= self.settings_index < len(self.settings_rows):
            prev_key = self.settings_rows[self.settings_index].get("key")

        self.settings_rows = rows
        self.settings_pending = {row.get("key", ""): str(row.get("current_text", "")) for row in rows if row.get("key")}

        self.settings_index = 0
        if prev_key:
            for idx, row in enumerate(rows):
                if row.get("key") == prev_key:
                    self.settings_index = idx
                    break
        return True
