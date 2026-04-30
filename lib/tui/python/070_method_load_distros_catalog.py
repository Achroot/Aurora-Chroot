    def load_distros_catalog(self, back_state="distros", refresh=False):
        cmd = [self.runner, "distros", "--json"]
        if refresh:
            cmd.append("--refresh")
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

        distros = payload.get("distros", [])
        if not isinstance(distros, list):
            distros = []
        runtime_root = str(payload.get("runtime_root", "") or "").strip()
        if runtime_root:
            runtime_root = os.path.normpath(runtime_root)
        self.distros_runtime_root = runtime_root
        if runtime_root:
            self.runtime_root_hint = runtime_root
        for item in distros:
            versions = item.get("versions", [])
            if not isinstance(versions, list):
                versions = []
            item["versions"] = versions

        self.distros_catalog = distros
        self.distros_index = 0
        self.distros_version_index = 0
        self.distros_stage = "distros"
        return True
