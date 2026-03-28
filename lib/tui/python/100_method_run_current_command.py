    def run_current_command(self):
        command = self.active_command
        if command == "help":
            view_mode = str(self.form_values.get("view", "guide")).strip().lower() or "guide"
            if view_mode == "raw":
                lines = (self.help_raw_rendered_text or self.help_raw_text).splitlines() or ["No raw command list available."]
                self.result_command = "embedded help raw"
                self.status("Rendered raw command list", "ok")
            else:
                lines = (self.help_rendered_text or self.help_text).splitlines() or ["No help text available."]
                self.result_command = "embedded help"
                self.status("Rendered help text", "ok")
            self.result_exit_code = 0
            self.result_duration = 0.0
            self.result_lines = lines
            self.result_scroll = 0
            self.result_hscroll = 0
            self.result_back_state = "form"
            self.result_rerun_cmd = None
            self.result_rerun_stdin = ""
            self.result_rerun_interactive = False
            self.state = "result"
            return
        if command == "tor" and str(self.form_values.get("action", "")).strip().lower() == "apps-tunneling":
            try:
                distro = self.require_text("distro", "Installed distro")
            except Exception as exc:
                self.status(str(exc), "error")
                return
            self.open_tor_apps_tunneling(distro, back_state="form")
            return
        if command == "tor" and str(self.form_values.get("action", "")).strip().lower() == "exit-tunneling":
            try:
                distro = self.require_text("distro", "Installed distro")
            except Exception as exc:
                self.status(str(exc), "error")
                return
            self.open_tor_exit_mode(distro, back_state="form")
            return

        try:
            args, stdin_data = self.build_command(command)
        except Exception as exc:
            self.status(str(exc), "error")
            return

        if command == "remove":
            distro = args[0] if args else self.form_values.get("distro", "")
            if not self.prompt_yes_no(f"Remove distro '{distro}' now?", default_no=True):
                self.status("Remove canceled", "info")
                return
            stdin_data = "y\n"
        elif command == "tor" and len(args) >= 2 and args[1] == "remove":
            distro = args[0] if args else self.form_values.get("distro", "")
            if not self.prompt_yes_no(
                f"Remove Tor state/config/log/cache for distro '{distro}' and keep packages installed?",
                default_no=True,
            ):
                self.status("Tor remove canceled", "info")
                return
        elif command == "clear-cache" and "--all" in args:
            if not self.prompt_yes_no("Clear cached downloads and disposable runtime files?", default_no=True):
                self.status("Clear-cache canceled", "info")
                return
        elif command == "nuke":
            if not self.prompt_yes_no("DANGER: NUKE all Aurora data now?", default_no=True):
                self.status("Nuke canceled", "info")
                return
            args.append("--yes")

        cmd = self.build_cli_command(command, args)
        if command == "service":
            action = str(self.form_values.get("action", "list"))
            svc_name = self.read_text("service_pick")
            if action == "remove" and not svc_name:
                self.execute_command_interactive(cmd, back_state="form")
                return
            if action in ("start", "restart") and str(svc_name).strip().lower() == "pcbridge":
                self.execute_command(cmd, stdin_data=stdin_data, back_state="form", interactive=True)
                return
            if action == "install" and str(self.form_values.get("service_builtin", "")).strip().lower() == "zsh":
                self.execute_command(cmd, stdin_data=stdin_data, back_state="form", interactive=True)
                return
        if command == "login":
            self.execute_command_interactive(cmd, back_state="form")
        elif command == "exec":
            self.execute_command(cmd, stdin_data=stdin_data, back_state="form", interactive=True)
        else:
            self.execute_command_stream(cmd, stdin_data=stdin_data, back_state="form")

    def open_tor_apps_tunneling(self, distro, back_state="form"):
        distro = str(distro).strip()
        cached_distro = str(self.tor_apps_tunneling_distro or "").strip()
        self.tor_apps_tunneling_distro = distro
        self.tor_apps_tunneling_scope = "all"
        self.tor_apps_tunneling_query = ""
        self.tor_apps_tunneling_back_state = back_state
        if self.tor_apps_tunneling_rows and cached_distro == distro:
            self.tor_apps_tunneling_index = 0
            self.tor_apps_tunneling_scroll = 0
            self.state = "tor_apps_tunneling"
            self.status("Apps Tunneling loaded from memory cache", "ok")
            return True
        if self.load_tor_apps_tunneling_cached_file(distro):
            self.tor_apps_tunneling_index = 0
            self.tor_apps_tunneling_scroll = 0
            self.state = "tor_apps_tunneling"
            self.status("Apps Tunneling loaded from saved cache", "ok")
            return True
        return self.load_tor_apps_tunneling(refresh=True)

    def tor_runtime_root(self):
        root = str(os.environ.get("CHROOT_RUNTIME_ROOT", "") or "").strip()
        if root:
            return root
        root = str(self.runtime_root_hint or self.distros_runtime_root or "").strip()
        if root:
            return root
        payload = self.load_status_payload(show_error=False)
        if isinstance(payload, dict):
            root = str(payload.get("runtime_root", "") or "").strip()
            if root:
                self.runtime_root_hint = root
                return root
        return "/data/local/chroot"

    def tor_apps_tunneling_cache_file(self, distro):
        root = self.tor_runtime_root()
        distro = str(distro or "").strip()
        if not root or not distro:
            return ""
        return os.path.join(root, "state", distro, "tor", "apps.json")

    def load_tor_apps_tunneling_cached_file(self, distro):
        cache_file = self.tor_apps_tunneling_cache_file(distro)
        if not cache_file or not os.path.isfile(cache_file):
            return False
        try:
            with open(cache_file, "r", encoding="utf-8") as fh:
                payload = json.load(fh)
        except Exception:
            return False
        if not isinstance(payload, dict):
            return False
        self.tor_apps_payload_data = payload
        self.set_tor_apps_tunneling_payload(payload)
        return True

    def load_tor_apps_tunneling(self, refresh=False):
        distro = str(self.tor_apps_tunneling_distro or "").strip()
        if not distro:
            self.status("Installed distro is required", "error")
            return False
        cmd = [self.runner, distro, "tor", "apps", "refresh", "--json"]
        rc, stdout, stderr, duration, rendered = self.capture_command(cmd)
        if rc != 0:
            self.show_result(rendered, stdout, stderr, rc, duration, back_state=self.tor_apps_tunneling_back_state, rerun_cmd=cmd)
            return False
        try:
            payload = parse_json_payload(stdout)
        except Exception as exc:
            parse_out = (stdout or "") + f"\nparse error: {exc}\n" + (stderr or "")
            self.show_result(rendered, parse_out, "", 1, duration, back_state=self.tor_apps_tunneling_back_state, rerun_cmd=cmd)
            return False
        self.tor_apps_payload_data = payload if isinstance(payload, dict) else None
        self.set_tor_apps_tunneling_payload(payload)
        self.state = "tor_apps_tunneling"
        self.status(
            "Apps Tunneling refreshed" if refresh else "Apps Tunneling loaded",
            "ok",
        )
        return True

    def set_tor_apps_tunneling_payload(self, payload):
        rows = payload.get("packages", []) if isinstance(payload, dict) else []
        normalized = []
        for row in rows:
            if not isinstance(row, dict):
                continue
            package = str(row.get("package", "")).strip()
            if not package:
                continue
            label = str(row.get("label", "")).strip()
            display_name = str(row.get("display_name", "")).strip() or label or package
            saved_bypassed = bool(row.get("bypassed"))
            row_copy = dict(row)
            row_copy["label"] = label or None
            row_copy["display_name"] = display_name
            row_copy["saved_bypassed"] = saved_bypassed
            row_copy["pending_bypassed"] = saved_bypassed
            row_copy["tunneled"] = not saved_bypassed
            normalized.append(row_copy)
        normalized.sort(
            key=lambda item: (
                0 if item.get("saved_bypassed") else 1,
                str(item.get("display_name") or item.get("package") or "").lower(),
                str(item.get("package") or "").lower(),
            )
        )
        self.tor_apps_tunneling_rows = normalized
        self.tor_apps_tunneling_generated_at = str(payload.get("generated_at", "") or "")
        self.tor_apps_tunneling_dirty = False
        self.tor_apps_tunneling_index = 0
        self.tor_apps_tunneling_scroll = 0
        self.refresh_tor_apps_tunneling_dirty()

    def tor_apps_tunneling_layout(self, height, width):
        top = 2
        content_height = height - top - 3
        list_top = top + 4
        visible_rows = max(1, content_height - 5)
        return {
            "top": top,
            "height": content_height,
            "left": 0,
            "width": width,
            "list_top": list_top,
            "visible_rows": visible_rows,
        }

    def tor_apps_tunneling_scope_regions(self, layout):
        labels = [("all", "ALL"), ("user", "USR"), ("system", "SYSTM"), ("unknown", "UNKWN")]
        x = 2
        regions = []
        for key, label in labels:
            text = f"[{label}]" if self.tor_apps_tunneling_scope == key else f" {label} "
            regions.append({"key": key, "x1": x, "x2": x + len(text) - 1, "text": text})
            x += len(text) + 2
        return regions

    def tor_apps_tunneling_scope_from_x(self, x, layout):
        for region in self.tor_apps_tunneling_scope_regions(layout):
            if region["x1"] <= x <= region["x2"]:
                return region["key"]
        return ""

    def tor_apps_tunneling_filtered_rows(self):
        query = str(self.tor_apps_tunneling_query or "").strip().lower()
        rows = []
        for row in self.tor_apps_tunneling_rows:
            if not isinstance(row, dict):
                continue
            scope = str(row.get("scope", "unknown") or "unknown").strip().lower()
            if self.tor_apps_tunneling_scope in ("user", "system", "unknown") and scope != self.tor_apps_tunneling_scope:
                continue
            haystack = " ".join(
                part
                for part in [
                    str(row.get("package", "")).lower(),
                    str(row.get("label", "")).lower(),
                    str(row.get("display_name", "")).lower(),
                ]
                if part
            )
            if query and query not in haystack:
                continue
            rows.append(row)
        return rows

    def normalize_tor_apps_tunneling_view(self):
        rows = self.tor_apps_tunneling_filtered_rows()
        if not rows:
            self.tor_apps_tunneling_index = 0
            self.tor_apps_tunneling_scroll = 0
            return rows
        self.tor_apps_tunneling_index = max(0, min(self.tor_apps_tunneling_index, len(rows) - 1))
        layout = self.tor_apps_tunneling_layout(*self.stdscr.getmaxyx())
        visible = layout["visible_rows"]
        max_scroll = max(0, len(rows) - visible)
        if self.tor_apps_tunneling_index < self.tor_apps_tunneling_scroll:
            self.tor_apps_tunneling_scroll = self.tor_apps_tunneling_index
        if self.tor_apps_tunneling_index >= self.tor_apps_tunneling_scroll + visible:
            self.tor_apps_tunneling_scroll = self.tor_apps_tunneling_index - visible + 1
        self.tor_apps_tunneling_scroll = max(0, min(self.tor_apps_tunneling_scroll, max_scroll))
        return rows

    def move_tor_apps_tunneling(self, delta, page=False):
        rows = self.normalize_tor_apps_tunneling_view()
        if not rows:
            return
        step = self.tor_apps_tunneling_layout(*self.stdscr.getmaxyx())["visible_rows"] if page else 1
        self.tor_apps_tunneling_index = max(0, min(len(rows) - 1, self.tor_apps_tunneling_index + (delta * step)))
        self.normalize_tor_apps_tunneling_view()

    def current_tor_apps_tunneling_row(self):
        rows = self.normalize_tor_apps_tunneling_view()
        if not rows:
            return None
        if self.tor_apps_tunneling_index >= len(rows):
            return None
        return rows[self.tor_apps_tunneling_index]

    def refresh_tor_apps_tunneling_dirty(self):
        self.tor_apps_tunneling_dirty = any(
            bool(row.get("saved_bypassed")) != bool(row.get("pending_bypassed"))
            for row in self.tor_apps_tunneling_rows
            if isinstance(row, dict)
        )

    def restore_tor_apps_tunneling_saved_state(self):
        for row in self.tor_apps_tunneling_rows:
            if not isinstance(row, dict):
                continue
            saved_bypassed = bool(row.get("saved_bypassed"))
            row["pending_bypassed"] = saved_bypassed
            row["tunneled"] = not saved_bypassed
        self.refresh_tor_apps_tunneling_dirty()

    def toggle_current_tor_apps_tunneling(self):
        row = self.current_tor_apps_tunneling_row()
        if not row:
            return
        row["pending_bypassed"] = not bool(row.get("pending_bypassed"))
        row["tunneled"] = not bool(row.get("pending_bypassed"))
        self.refresh_tor_apps_tunneling_dirty()

    def change_tor_apps_tunneling_scope(self, delta):
        scopes = ["all", "user", "system", "unknown"]
        current = self.tor_apps_tunneling_scope if self.tor_apps_tunneling_scope in scopes else "all"
        idx = scopes.index(current)
        self.tor_apps_tunneling_scope = scopes[(idx + delta) % len(scopes)]
        self.tor_apps_tunneling_index = 0
        self.tor_apps_tunneling_scroll = 0
        self.normalize_tor_apps_tunneling_view()

    def tor_apps_tunneling_row_at(self, y, layout):
        rows = self.normalize_tor_apps_tunneling_view()
        if not rows:
            return None
        if y < layout["list_top"] or y >= layout["list_top"] + layout["visible_rows"]:
            return None
        idx = self.tor_apps_tunneling_scroll + (y - layout["list_top"])
        if 0 <= idx < len(rows):
            return idx
        return None

    def prompt_tor_apps_tunneling_search(self):
        value = self.prompt_input("Apps search", self.tor_apps_tunneling_query)
        self.tor_apps_tunneling_query = str(value or "").strip()
        self.tor_apps_tunneling_index = 0
        self.tor_apps_tunneling_scroll = 0
        self.normalize_tor_apps_tunneling_view()

    def save_tor_apps_tunneling(self):
        if not self.tor_apps_tunneling_dirty:
            self.status("No Apps Tunneling changes to save", "info")
            return True
        bypassed_packages = [
            str(row.get("package", "")).strip()
            for row in self.tor_apps_tunneling_rows
            if isinstance(row, dict) and bool(row.get("pending_bypassed")) and str(row.get("package", "")).strip()
        ]
        stdin_data = json.dumps({"bypassed_packages": sorted(set(bypassed_packages))}, indent=2, sort_keys=True) + "\n"
        try:
            cmd = [self.runner, self.tor_apps_tunneling_distro, "tor", "apps", "apply", "--stdin", "--json"]
            rc, stdout, stderr, duration, rendered = self.capture_command(cmd, stdin_data=stdin_data)
            if rc != 0:
                self.show_result(rendered, stdout, stderr, rc, duration, back_state="tor_apps_tunneling", rerun_cmd=cmd)
                return False
            payload = parse_json_payload(stdout)
            self.tor_apps_payload_data = payload if isinstance(payload, dict) else None
            self.set_tor_apps_tunneling_payload(payload)
            self.state = "tor_apps_tunneling"
            self.status("Apps Tunneling saved", "ok")
            return True
        except Exception as exc:
            self.status(f"Failed to save Apps Tunneling: {exc}", "error")
            return False

    def refresh_tor_apps_tunneling(self):
        if self.tor_apps_tunneling_dirty:
            if not self.prompt_yes_no("Discard unsaved Apps Tunneling changes and refresh?", default_no=True):
                self.status("Apps Tunneling refresh canceled", "info")
                return True
            self.restore_tor_apps_tunneling_saved_state()
        return self.load_tor_apps_tunneling(refresh=True)

    def exit_tor_apps_tunneling(self):
        if self.tor_apps_tunneling_dirty:
            if not self.prompt_yes_no("Discard unsaved Apps Tunneling changes?", default_no=True):
                self.status("Apps Tunneling back canceled", "info")
                return True
            self.restore_tor_apps_tunneling_saved_state()
        self.state = self.tor_apps_tunneling_back_state or "form"
        return True

    def handle_tor_apps_tunneling_key(self, key):
        if key in (curses.KEY_UP, ord("k")):
            self.move_tor_apps_tunneling(-1)
            return True
        if key in (curses.KEY_DOWN, ord("j")):
            self.move_tor_apps_tunneling(1)
            return True
        if key == curses.KEY_PPAGE:
            self.move_tor_apps_tunneling(-1, page=True)
            return True
        if key == curses.KEY_NPAGE:
            self.move_tor_apps_tunneling(1, page=True)
            return True
        if key == curses.KEY_HOME:
            self.tor_apps_tunneling_index = 0
            self.tor_apps_tunneling_scroll = 0
            return True
        if key == curses.KEY_END:
            rows = self.normalize_tor_apps_tunneling_view()
            if rows:
                self.tor_apps_tunneling_index = len(rows) - 1
                self.normalize_tor_apps_tunneling_view()
            return True
        if key in (curses.KEY_LEFT, ord("h")):
            self.change_tor_apps_tunneling_scope(-1)
            return True
        if key in (curses.KEY_RIGHT, ord("l")):
            self.change_tor_apps_tunneling_scope(1)
            return True
        if key in (10, 13, curses.KEY_ENTER, ord(" ")):
            self.toggle_current_tor_apps_tunneling()
            return True
        if key in (ord("/"),):
            self.prompt_tor_apps_tunneling_search()
            return True
        if key in (ord("c"), ord("C")):
            self.tor_apps_tunneling_query = ""
            self.tor_apps_tunneling_index = 0
            self.tor_apps_tunneling_scroll = 0
            self.status("Apps search cleared", "ok")
            return True
        if key in (ord("s"), ord("S")):
            self.save_tor_apps_tunneling()
            return True
        if key in (ord("r"), ord("R")):
            self.refresh_tor_apps_tunneling()
            return True
        if key in (ord("b"), ord("B")):
            return self.exit_tor_apps_tunneling()
        if key in (ord("q"), ord("Q")):
            return self.exit_tor_apps_tunneling()
        return True

    def draw_tor_apps_tunneling(self, height, width):
        layout = self.tor_apps_tunneling_layout(height, width)
        top = layout["top"]
        content_height = layout["height"]
        draw_box(
            self.stdscr,
            top,
            0,
            content_height,
            width,
            "APPS TUNNELING",
            self.color(4),
            self.color(1, curses.A_BOLD),
        )

        distro = self.tor_apps_tunneling_distro or "<distro>"
        addstr_clipped(self.stdscr, top + 1, 2, f"TOP APPS : {distro}", width - 4, self.color(2, curses.A_BOLD))

        regions = self.tor_apps_tunneling_scope_regions(layout)
        for region in regions:
            attr = self.color(3, curses.A_BOLD) if self.tor_apps_tunneling_scope == region["key"] else self.color(0)
            addstr_clipped(self.stdscr, top + 2, region["x1"], region["text"], len(region["text"]), attr)
        right_text = "UNTICK APPS = TOR OFF FOR THEM"
        if self.tor_apps_tunneling_query:
            right_text = f"/ {self.tor_apps_tunneling_query}"
            if self.tor_apps_tunneling_dirty:
                right_text = f"{right_text} | UNSAVED"
        elif self.tor_apps_tunneling_dirty:
            right_text = f"{right_text} | UNSAVED"
        right_x = max(2, width - len(right_text) - 3)
        addstr_clipped(self.stdscr, top + 2, right_x, right_text, width - right_x - 2, self.color(6))

        rows = self.normalize_tor_apps_tunneling_view()
        list_top = layout["list_top"]
        visible_rows = layout["visible_rows"]

        if not rows:
            message = "No apps match the current filter." if self.tor_apps_tunneling_rows else "No app inventory loaded. Press r to refresh."
            addstr_clipped(self.stdscr, list_top, 2, message, width - 4, self.color(5))
            return

        end = min(len(rows), self.tor_apps_tunneling_scroll + visible_rows)
        for visible_idx, idx in enumerate(range(self.tor_apps_tunneling_scroll, end)):
            row = rows[idx]
            y = list_top + visible_idx
            selected = idx == self.tor_apps_tunneling_index
            pending_bypassed = bool(row.get("pending_bypassed"))
            marker = "[ ]" if pending_bypassed else "[x]"
            marker_attr = self.color(5, curses.A_BOLD) if pending_bypassed else self.color(3, curses.A_BOLD)
            name = str(row.get("display_name") or row.get("package") or "")
            base_attr = self.color(2, curses.A_BOLD | curses.A_REVERSE) if selected else self.color(0)
            try:
                self.stdscr.addstr(y, 1, " " * max(1, width - 2), self.color(4, curses.A_REVERSE) if selected else self.color(0))
            except curses.error:
                pass
            addstr_clipped(self.stdscr, y, 2, marker, len(marker), marker_attr | (curses.A_REVERSE if selected else 0))
            name_x = 6
            max_name = max(1, width - name_x - 3)
            shown_name = name[:max_name]
            addstr_clipped(self.stdscr, y, name_x, shown_name, max_name, base_attr)
            dot_x = name_x + len(shown_name) + 1
            if dot_x < width - 2:
                dots = "." * max(0, width - dot_x - 2)
                addstr_clipped(self.stdscr, y, dot_x, dots, width - dot_x - 2, self.color(4))

    def open_tor_exit_mode(self, distro, back_state="form"):
        distro = str(distro).strip()
        cached_distro = str(self.tor_exit_mode_distro or "").strip()
        self.tor_exit_mode_distro = distro
        self.tor_exit_mode_filter = "all"
        self.tor_exit_mode_query = ""
        self.tor_exit_mode_back_state = back_state
        if self.tor_exit_mode_rows and cached_distro == distro:
            self.tor_exit_mode_index = 0
            self.tor_exit_mode_scroll = 0
            self.state = "tor_exit_mode"
            self.status("Exit Tunneling loaded from memory cache", "ok")
            return True
        if self.load_tor_exit_mode_cached_file(distro):
            self.tor_exit_mode_index = 0
            self.tor_exit_mode_scroll = 0
            self.state = "tor_exit_mode"
            self.status("Exit Tunneling loaded from saved cache", "ok")
            return True
        return self.load_tor_exit_mode(refresh=False)

    def tor_exit_mode_cache_file(self, distro):
        root = self.tor_runtime_root()
        distro = str(distro or "").strip()
        if not root or not distro:
            return ""
        return os.path.join(root, "state", distro, "tor", "exit.json")

    def load_tor_exit_mode_cached_file(self, distro):
        cache_file = self.tor_exit_mode_cache_file(distro)
        if not cache_file or not os.path.isfile(cache_file):
            return False
        try:
            with open(cache_file, "r", encoding="utf-8") as fh:
                payload = json.load(fh)
        except Exception:
            return False
        if not isinstance(payload, dict):
            return False
        self.set_tor_exit_mode_payload(payload)
        return True

    def load_tor_exit_mode(self, refresh=False):
        distro = str(self.tor_exit_mode_distro or "").strip()
        if not distro:
            self.status("Installed distro is required", "error")
            return False
        action = "refresh" if refresh else "list"
        cmd = [self.runner, distro, "tor", "exit", action, "--json"]
        rc, stdout, stderr, duration, rendered = self.capture_command(cmd)
        if rc != 0:
            self.show_result(rendered, stdout, stderr, rc, duration, back_state=self.tor_exit_mode_back_state, rerun_cmd=cmd)
            return False
        try:
            payload = parse_json_payload(stdout)
        except Exception as exc:
            parse_out = (stdout or "") + f"\nparse error: {exc}\n" + (stderr or "")
            self.show_result(rendered, parse_out, "", 1, duration, back_state=self.tor_exit_mode_back_state, rerun_cmd=cmd)
            return False
        self.tor_exit_payload_data = payload if isinstance(payload, dict) else None
        self.set_tor_exit_mode_payload(payload)
        self.state = "tor_exit_mode"
        self.status("Exit Tunneling refreshed" if refresh else "Exit Tunneling loaded", "ok")
        return True

    def set_tor_exit_mode_payload(self, payload):
        rows = payload.get("countries", []) if isinstance(payload, dict) else []
        normalized = []
        for row in rows:
            if not isinstance(row, dict):
                continue
            code = str(row.get("code", "")).strip().lower()
            if not code:
                continue
            name = str(row.get("name", "")).strip()
            display_name = str(row.get("display_name", "")).strip() or f"{name} ({code.upper()})"
            selected = bool(row.get("selected"))
            item = dict(row)
            item["code"] = code
            item["name"] = name
            item["display_name"] = display_name
            item["saved_selected"] = selected
            item["pending_selected"] = selected
            normalized.append(item)
        normalized.sort(key=lambda row: (0 if row.get("saved_selected") else 1, str(row.get("name") or "").lower()))
        self.tor_exit_mode_rows = normalized
        self.tor_exit_mode_generated_at = str(payload.get("generated_at", "") or "")
        self.tor_exit_mode_saved_strict = bool(payload.get("strict"))
        self.tor_exit_mode_pending_strict = bool(payload.get("strict"))
        self.tor_exit_mode_dirty = False
        self.tor_exit_mode_index = 0
        self.tor_exit_mode_scroll = 0
        self.refresh_tor_exit_mode_dirty()

    def tor_exit_mode_layout(self, height, width):
        top = 2
        content_height = height - top - 3
        list_top = top + 4
        visible_rows = max(1, content_height - 5)
        return {
            "top": top,
            "height": content_height,
            "left": 0,
            "width": width,
            "list_top": list_top,
            "visible_rows": visible_rows,
        }

    def tor_exit_mode_filter_regions(self, layout):
        labels = [("all", "ALL"), ("selected", "SELECTED")]
        x = 2
        regions = []
        for key, label in labels:
            text = f"[{label}]" if self.tor_exit_mode_filter == key else f" {label} "
            regions.append({"key": key, "x1": x, "x2": x + len(text) - 1, "text": text})
            x += len(text) + 2
        return regions

    def tor_exit_mode_filter_from_x(self, x, layout):
        for region in self.tor_exit_mode_filter_regions(layout):
            if region["x1"] <= x <= region["x2"]:
                return region["key"]
        return ""

    def tor_exit_mode_filtered_rows(self):
        query = str(self.tor_exit_mode_query or "").strip().lower()
        rows = []
        for row in self.tor_exit_mode_rows:
            if not isinstance(row, dict):
                continue
            if self.tor_exit_mode_filter == "selected" and not bool(row.get("pending_selected")):
                continue
            haystack = " ".join(
                part
                for part in [
                    str(row.get("code", "")).lower(),
                    str(row.get("name", "")).lower(),
                    str(row.get("display_name", "")).lower(),
                ]
                if part
            )
            if query and query not in haystack:
                continue
            rows.append(row)
        return rows

    def normalize_tor_exit_mode_view(self):
        rows = self.tor_exit_mode_filtered_rows()
        if not rows:
            self.tor_exit_mode_index = 0
            self.tor_exit_mode_scroll = 0
            return rows
        self.tor_exit_mode_index = max(0, min(self.tor_exit_mode_index, len(rows) - 1))
        layout = self.tor_exit_mode_layout(*self.stdscr.getmaxyx())
        visible = layout["visible_rows"]
        max_scroll = max(0, len(rows) - visible)
        if self.tor_exit_mode_index < self.tor_exit_mode_scroll:
            self.tor_exit_mode_scroll = self.tor_exit_mode_index
        if self.tor_exit_mode_index >= self.tor_exit_mode_scroll + visible:
            self.tor_exit_mode_scroll = self.tor_exit_mode_index - visible + 1
        self.tor_exit_mode_scroll = max(0, min(self.tor_exit_mode_scroll, max_scroll))
        return rows

    def move_tor_exit_mode(self, delta, page=False):
        rows = self.normalize_tor_exit_mode_view()
        if not rows:
            return
        step = self.tor_exit_mode_layout(*self.stdscr.getmaxyx())["visible_rows"] if page else 1
        self.tor_exit_mode_index = max(0, min(len(rows) - 1, self.tor_exit_mode_index + (delta * step)))
        self.normalize_tor_exit_mode_view()

    def current_tor_exit_mode_row(self):
        rows = self.normalize_tor_exit_mode_view()
        if not rows:
            return None
        if self.tor_exit_mode_index >= len(rows):
            return None
        return rows[self.tor_exit_mode_index]

    def refresh_tor_exit_mode_dirty(self):
        self.tor_exit_mode_dirty = bool(self.tor_exit_mode_saved_strict) != bool(self.tor_exit_mode_pending_strict) or any(
            bool(row.get("saved_selected")) != bool(row.get("pending_selected"))
            for row in self.tor_exit_mode_rows
            if isinstance(row, dict)
        )

    def restore_tor_exit_mode_saved_state(self):
        self.tor_exit_mode_pending_strict = bool(self.tor_exit_mode_saved_strict)
        for row in self.tor_exit_mode_rows:
            if not isinstance(row, dict):
                continue
            row["pending_selected"] = bool(row.get("saved_selected"))
        self.refresh_tor_exit_mode_dirty()

    def toggle_current_tor_exit_mode(self):
        row = self.current_tor_exit_mode_row()
        if not row:
            return
        row["pending_selected"] = not bool(row.get("pending_selected"))
        self.refresh_tor_exit_mode_dirty()

    def toggle_tor_exit_mode_strict(self):
        self.tor_exit_mode_pending_strict = not bool(self.tor_exit_mode_pending_strict)
        self.refresh_tor_exit_mode_dirty()

    def change_tor_exit_mode_filter(self, delta):
        filters = ["all", "selected"]
        current = self.tor_exit_mode_filter if self.tor_exit_mode_filter in filters else "all"
        idx = filters.index(current)
        self.tor_exit_mode_filter = filters[(idx + delta) % len(filters)]
        self.tor_exit_mode_index = 0
        self.tor_exit_mode_scroll = 0
        self.normalize_tor_exit_mode_view()

    def tor_exit_mode_row_at(self, y, layout):
        rows = self.normalize_tor_exit_mode_view()
        if not rows:
            return None
        if y < layout["list_top"] or y >= layout["list_top"] + layout["visible_rows"]:
            return None
        idx = self.tor_exit_mode_scroll + (y - layout["list_top"])
        if 0 <= idx < len(rows):
            return idx
        return None

    def prompt_tor_exit_mode_search(self):
        value = self.prompt_input("Exit search", self.tor_exit_mode_query)
        self.tor_exit_mode_query = str(value or "").strip()
        self.tor_exit_mode_index = 0
        self.tor_exit_mode_scroll = 0
        self.normalize_tor_exit_mode_view()

    def save_tor_exit_mode(self):
        if not self.tor_exit_mode_dirty:
            self.status("No Exit Tunneling changes to save", "info")
            return True
        selected_codes = [
            str(row.get("code", "")).strip().lower()
            for row in self.tor_exit_mode_rows
            if isinstance(row, dict) and bool(row.get("pending_selected")) and str(row.get("code", "")).strip()
        ]
        if self.tor_exit_mode_pending_strict and not selected_codes:
            self.status("Strict mode requires at least one selected country", "error")
            return False
        stdin_data = json.dumps(
            {
                "selected_codes": sorted(set(selected_codes)),
                "strict": bool(self.tor_exit_mode_pending_strict),
            },
            indent=2,
            sort_keys=True,
        ) + "\n"
        try:
            cmd = [self.runner, self.tor_exit_mode_distro, "tor", "exit", "apply", "--stdin", "--json"]
            rc, stdout, stderr, duration, rendered = self.capture_command(cmd, stdin_data=stdin_data)
            if rc != 0:
                self.show_result(rendered, stdout, stderr, rc, duration, back_state="tor_exit_mode", rerun_cmd=cmd)
                return False
            payload = parse_json_payload(stdout)
            self.tor_exit_payload_data = payload if isinstance(payload, dict) else None
            self.set_tor_exit_mode_payload(payload)
            self.state = "tor_exit_mode"
            self.status("Exit Tunneling saved", "ok")
            return True
        except Exception as exc:
            self.status(f"Failed to save Exit Tunneling: {exc}", "error")
            return False

    def refresh_tor_exit_mode(self):
        if self.tor_exit_mode_dirty:
            if not self.prompt_yes_no("Discard unsaved Exit Tunneling changes and refresh?", default_no=True):
                self.status("Exit Tunneling refresh canceled", "info")
                return True
            self.restore_tor_exit_mode_saved_state()
        return self.load_tor_exit_mode(refresh=True)

    def exit_tor_exit_mode(self):
        if self.tor_exit_mode_dirty:
            if not self.prompt_yes_no("Discard unsaved Exit Tunneling changes?", default_no=True):
                self.status("Exit Tunneling back canceled", "info")
                return True
            self.restore_tor_exit_mode_saved_state()
        self.state = self.tor_exit_mode_back_state or "form"
        return True

    def handle_tor_exit_mode_key(self, key):
        if key in (curses.KEY_UP, ord("k")):
            self.move_tor_exit_mode(-1)
            return True
        if key in (curses.KEY_DOWN, ord("j")):
            self.move_tor_exit_mode(1)
            return True
        if key == curses.KEY_PPAGE:
            self.move_tor_exit_mode(-1, page=True)
            return True
        if key == curses.KEY_NPAGE:
            self.move_tor_exit_mode(1, page=True)
            return True
        if key == curses.KEY_HOME:
            self.tor_exit_mode_index = 0
            self.tor_exit_mode_scroll = 0
            return True
        if key == curses.KEY_END:
            rows = self.normalize_tor_exit_mode_view()
            if rows:
                self.tor_exit_mode_index = len(rows) - 1
                self.normalize_tor_exit_mode_view()
            return True
        if key in (curses.KEY_LEFT, ord("h")):
            self.change_tor_exit_mode_filter(-1)
            return True
        if key in (curses.KEY_RIGHT, ord("l")):
            self.change_tor_exit_mode_filter(1)
            return True
        if key in (10, 13, curses.KEY_ENTER, ord(" ")):
            self.toggle_current_tor_exit_mode()
            return True
        if key in (ord("t"), ord("T")):
            self.toggle_tor_exit_mode_strict()
            return True
        if key in (ord("/"),):
            self.prompt_tor_exit_mode_search()
            return True
        if key in (ord("c"), ord("C")):
            self.tor_exit_mode_query = ""
            self.tor_exit_mode_index = 0
            self.tor_exit_mode_scroll = 0
            self.status("Exit search cleared", "ok")
            return True
        if key in (ord("s"), ord("S")):
            self.save_tor_exit_mode()
            return True
        if key in (ord("r"), ord("R")):
            self.refresh_tor_exit_mode()
            return True
        if key in (ord("b"), ord("B")):
            return self.exit_tor_exit_mode()
        if key in (ord("q"), ord("Q")):
            return self.exit_tor_exit_mode()
        return True

    def draw_tor_exit_mode(self, height, width):
        layout = self.tor_exit_mode_layout(height, width)
        top = layout["top"]
        content_height = layout["height"]
        draw_box(
            self.stdscr,
            top,
            0,
            content_height,
            width,
            "EXIT TUNNELING",
            self.color(4),
            self.color(1, curses.A_BOLD),
        )

        distro = self.tor_exit_mode_distro or "<distro>"
        addstr_clipped(self.stdscr, top + 1, 2, f"TOP EXIT : {distro}", width - 4, self.color(2, curses.A_BOLD))

        regions = self.tor_exit_mode_filter_regions(layout)
        for region in regions:
            attr = self.color(3, curses.A_BOLD) if self.tor_exit_mode_filter == region["key"] else self.color(0)
            addstr_clipped(self.stdscr, top + 2, region["x1"], region["text"], len(region["text"]), attr)

        strict_text = "STRICT: ON" if self.tor_exit_mode_pending_strict else "STRICT: OFF"
        strict_attr = self.color(3, curses.A_BOLD) if self.tor_exit_mode_pending_strict else self.color(5, curses.A_BOLD)
        right_text = f"/ {self.tor_exit_mode_query}" if self.tor_exit_mode_query else strict_text
        right_attr = self.color(6) if self.tor_exit_mode_query else strict_attr
        if self.tor_exit_mode_query and self.tor_exit_mode_dirty:
            right_text = f"{right_text} | UNSAVED"
        elif not self.tor_exit_mode_query and self.tor_exit_mode_dirty:
            right_text = f"{strict_text} | UNSAVED"
        right_x = max(2, width - len(right_text) - 3)
        addstr_clipped(self.stdscr, top + 2, right_x, right_text, width - right_x - 2, right_attr)

        rows = self.normalize_tor_exit_mode_view()
        list_top = layout["list_top"]
        visible_rows = layout["visible_rows"]
        if not rows:
            message = "No countries match the current filter." if self.tor_exit_mode_rows else "No exit inventory loaded. Press r to refresh."
            addstr_clipped(self.stdscr, list_top, 2, message, width - 4, self.color(5))
            return

        end = min(len(rows), self.tor_exit_mode_scroll + visible_rows)
        for visible_idx, idx in enumerate(range(self.tor_exit_mode_scroll, end)):
            row = rows[idx]
            y = list_top + visible_idx
            selected = idx == self.tor_exit_mode_index
            pending_selected = bool(row.get("pending_selected"))
            marker = "[x]" if pending_selected else "[ ]"
            marker_attr = self.color(3, curses.A_BOLD) if pending_selected else self.color(5, curses.A_BOLD)
            name = str(row.get("display_name") or row.get("name") or row.get("code") or "")
            base_attr = self.color(2, curses.A_BOLD | curses.A_REVERSE) if selected else self.color(0)
            try:
                self.stdscr.addstr(y, 1, " " * max(1, width - 2), self.color(4, curses.A_REVERSE) if selected else self.color(0))
            except curses.error:
                pass
            addstr_clipped(self.stdscr, y, 2, marker, len(marker), marker_attr | (curses.A_REVERSE if selected else 0))
            name_x = 6
            max_name = max(1, width - name_x - 3)
            shown_name = name[:max_name]
            addstr_clipped(self.stdscr, y, name_x, shown_name, max_name, base_attr)
            dot_x = name_x + len(shown_name) + 1
            if dot_x < width - 2:
                dots = "." * max(0, width - dot_x - 2)
                addstr_clipped(self.stdscr, y, dot_x, dots, width - dot_x - 2, self.color(4))
