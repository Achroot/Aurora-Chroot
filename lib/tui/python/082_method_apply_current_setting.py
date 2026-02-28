    def apply_current_setting(self):
        to_apply = []
        for row in self.settings_rows:
            key = row.get("key", "")
            if not key:
                continue
            current = str(row.get("current_text", ""))
            pending = self.settings_pending.get(key, current).strip()
            if pending and pending != current:
                to_apply.append((key, pending))

        if not to_apply:
            self.status("No pending changes", "error")
            return

        ok_count = 0
        fail_count = 0
        for key, value in to_apply:
            cmd = [self.runner, "settings", "set", key, value]
            rc, stdout, stderr, duration, rendered = self.capture_command(cmd)
            if rc == 0:
                ok_count += 1
            else:
                fail_count += 1

        if fail_count == 0:
            self.status(f"Applied {ok_count} setting(s)", "ok")
        else:
            self.status(f"Applied {ok_count}, failed {fail_count}", "error")

        self.load_settings(back_state="settings")
