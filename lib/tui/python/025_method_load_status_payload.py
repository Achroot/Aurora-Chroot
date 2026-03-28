    def load_status_payload(self, show_error=False):
        cmd = [self.runner, "status", "--json"]
        rc, stdout, stderr, duration, rendered = self.capture_command(cmd)
        if rc != 0:
            if show_error:
                self.show_result(rendered, stdout, stderr, rc, duration, back_state="form", rerun_cmd=cmd)
            else:
                self.status("Could not load runtime status", "error")
            return None

        try:
            payload = parse_json_payload(stdout)
            if isinstance(payload, dict):
                runtime_root = str(payload.get("runtime_root", "") or "").strip()
                if runtime_root:
                    self.runtime_root_hint = runtime_root
            return payload
        except Exception as exc:
            parse_out = (stdout or "") + f"\nparse error: {exc}\n" + (stderr or "")
            if show_error:
                self.show_result(rendered, parse_out, "", 1, duration, back_state="form", rerun_cmd=cmd)
            else:
                self.status("Could not parse runtime status", "error")
            return None

