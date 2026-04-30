    def load_install_local_entries(self, show_loading=False, select_first_entry=False):
        path = str(self.install_local_path or "").strip()
        if show_loading:
            height, width = self.stdscr.getmaxyx()
            self.stdscr.erase()
            self.draw_header(height, width)
            self.draw_loading_box("Scanning local archives...", height, width)
            self.draw_footer(height, width)
            self.stdscr.refresh()

        entries = []
        status_message = ""
        status_kind = "info"
        self.install_local_path_kind = ""

        if not path:
            status_message = "Tarball path is empty"
            status_kind = "error"
        else:
            cmd = [self.runner, "install-local", "--file", path, "--json"]
            rc, stdout, stderr, _duration, _rendered, _merged_output = self.capture_command(cmd)
            if rc != 0:
                status_message = str(stderr or stdout or "Could not scan local archives").strip()
                status_kind = "error"
            else:
                try:
                    payload = parse_json_payload(stdout)
                except Exception:
                    payload = {}

                runtime_root = str(payload.get("runtime_root", "") or "").strip()
                if runtime_root:
                    runtime_root = os.path.normpath(runtime_root)
                    self.runtime_root_hint = runtime_root
                    self.distros_runtime_root = runtime_root

                raw_entries = payload.get("entries", [])
                if isinstance(raw_entries, list):
                    entries = [row for row in raw_entries if isinstance(row, dict)]
                self.install_local_path_kind = str(payload.get("path_kind", "") or "").strip()
                status_message = str(payload.get("message", "") or "").strip()
                status_kind = str(payload.get("status", "") or "info").strip().lower()
                if status_kind not in ("ok", "error", "info"):
                    status_kind = "info"
                if not status_message:
                    if entries:
                        status_message = f"Found {len(entries)} local archive(s)"
                        status_kind = "ok"
                    else:
                        status_message = "No installable tar archives found under this path"
                        if status_kind == "ok":
                            status_kind = "info"

        self.install_local_entries = entries
        if select_first_entry and self.install_local_entries:
            self.install_local_index = 1
        else:
            max_index = len(self.install_local_entries)
            self.install_local_index = max(0, min(self.install_local_index, max_index))
        self.status(status_message, status_kind)
        return bool(self.install_local_entries)
