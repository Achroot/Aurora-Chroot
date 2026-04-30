    def busybox_actions(self):
        return [
            ("fetch", "Fetch device BusyBox"),
            ("path", "Use local BusyBox path"),
            ("status", "Status"),
        ]

    def enter_busybox(self):
        self.state = "busybox"
        self.busybox_action_index = max(0, min(self.busybox_action_index, len(self.busybox_actions()) - 1))
        self.status("BusyBox fallback manager")
        return True

    def busybox_selected_action(self):
        actions = self.busybox_actions()
        if not actions:
            return ("status", "Status")
        self.busybox_action_index = max(0, min(self.busybox_action_index, len(actions) - 1))
        return actions[self.busybox_action_index]

    def busybox_selected_info(self):
        action, _label = self.busybox_selected_action()
        if action == "fetch":
            return (
                "Fetch detects the current architecture, selects the matching BusyBox NDK binary from the allowed GitHub source, "
                "downloads one file, validates required applets, and registers the result as standby fallback when native tools are already enough."
            )
        if action == "path":
            return (
                "Path mode accepts one executable BusyBox binary or an applet directory, validates the required tools first, then copies a managed "
                "binary or required applets into Aurora runtime storage without modifying the original path."
            )
        return "Status reports current native, Toybox, built-in BusyBox, and managed fallback decisions for Aurora's required backend tools."

    def busybox_rows(self, width):
        inner_width = max(20, width - 4)
        rows = []
        rows.append(("Actions", self.color(2, curses.A_BOLD)))
        for idx, (_action, label) in enumerate(self.busybox_actions()):
            marker = "->" if idx == self.busybox_action_index else "  "
            attr = self.color(2, curses.A_BOLD) if idx == self.busybox_action_index else self.color(0)
            rows.append((f"{marker} {idx + 1}. {label}", attr))
        rows.append(("", self.color(0)))
        rows.append(("General BusyBox Information", self.color(2, curses.A_BOLD)))
        general = (
            "Aurora uses managed BusyBox only as a fallback when required native tools are missing or unusable. "
            "Fetched and single-binary sources are called as busybox <command>, while directory sources copy only the required applets into Aurora runtime storage."
        )
        rows.extend(self.wrapped_panel_rows(general, inner_width, self.color(0)))
        rows.append(("", self.color(0)))
        rows.append(("Selected Command Information", self.color(2, curses.A_BOLD)))
        rows.extend(self.wrapped_panel_rows(self.busybox_selected_info(), inner_width, self.color(0)))
        rows.append(("", self.color(0)))
        rows.append(("Dynamic Last Status Summary", self.color(2, curses.A_BOLD)))
        if self.busybox_last_summary:
            rows.extend(self.wrapped_panel_rows(self.busybox_last_summary, inner_width, self.color(0)))
        else:
            rows.append(("", self.color(0)))
        return rows

    def draw_busybox(self, height, width):
        content_top, content_height, _ = self.screen_content_layout(height, width)
        draw_box(
            self.stdscr,
            content_top,
            0,
            content_height,
            width - 1,
            "BUSYBOX",
            self.color(4),
            self.color(1, curses.A_BOLD),
        )
        rows = self.busybox_rows(width - 1)
        self.draw_text_panel_rows(
            content_top,
            0,
            content_height,
            width - 1,
            rows,
            "busybox_scroll",
            "busybox_hscroll",
        )

    def move_busybox_action(self, delta):
        actions = self.busybox_actions()
        if not actions:
            return
        self.busybox_action_index = (self.busybox_action_index + delta) % len(actions)
        self.busybox_scroll = 0
        self.busybox_hscroll = 0

    def run_busybox_action(self):
        action, _label = self.busybox_selected_action()
        if action == "fetch":
            self.execute_command_stream([self.runner, "busybox", "fetch"], back_state="busybox")
            return True
        if action == "path":
            source_path = self.prompt_input("BusyBox binary or applet directory path", "")
            if getattr(self, "prompt_cancelled", False):
                return True
            source_path = str(source_path or "").strip()
            if not source_path:
                self.status("BusyBox path is required", "error")
                return True
            self.execute_command_stream([self.runner, "busybox", source_path], back_state="busybox")
            return True
        self.execute_command_stream([self.runner, "busybox", "status"], back_state="busybox")
        return True

    def handle_busybox_key(self, key):
        height, width = self.stdscr.getmaxyx()
        _content_top, content_height, _ = self.screen_content_layout(height, width)
        rows = self.busybox_rows(width - 1)
        if key in (curses.KEY_UP, ord("k")):
            self.move_busybox_action(-1)
            return True
        if key in (curses.KEY_DOWN, ord("j")):
            self.move_busybox_action(1)
            return True
        if key in (curses.KEY_LEFT, ord("<")):
            self.scroll_text_panel_horizontal("busybox_scroll", "busybox_hscroll", rows, max(1, content_height - 2), max(1, width - 5), -1)
            return True
        if key in (curses.KEY_RIGHT, ord(">")):
            self.scroll_text_panel_horizontal("busybox_scroll", "busybox_hscroll", rows, max(1, content_height - 2), max(1, width - 5), 1)
            return True
        if key == curses.KEY_PPAGE:
            self.scroll_text_panel_vertical("busybox_scroll", "busybox_hscroll", rows, max(1, content_height - 2), max(1, width - 5), -1, page=True)
            return True
        if key == curses.KEY_NPAGE:
            self.scroll_text_panel_vertical("busybox_scroll", "busybox_hscroll", rows, max(1, content_height - 2), max(1, width - 5), 1, page=True)
            return True
        if key in (ord("r"), ord("R")):
            return self.run_busybox_action()
        if key in (ord("b"), ord("B")):
            self.state = "menu"
            return True
        if key in (ord("q"), ord("Q")):
            return False
        return True

    def update_busybox_last_summary_from_result(self):
        first_banner = ""
        source_line = ""
        for line in self.result_lines:
            text = str(line or "").strip()
            if not text:
                continue
            if not first_banner and text.startswith("BusyBox check:"):
                first_banner = text
            if not source_line and (
                text.startswith("Active managed BusyBox source:")
                or text.startswith("Downloaded/imported BusyBox")
                or text.startswith("Managed BusyBox fallback")
                or text.startswith("BusyBox fetch/path is not required")
            ):
                source_line = text
        pieces = []
        pieces.append("Last result: exit=%s" % self.result_exit_code)
        if first_banner:
            pieces.append(first_banner)
        if source_line:
            pieces.append(source_line)
        self.busybox_last_summary = " ".join(pieces)
