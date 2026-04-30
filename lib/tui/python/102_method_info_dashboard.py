    def info_header_status_text(self):
        current_id = self.current_info_section_id()
        current_title = ""
        if current_id:
            label = str(self.info_sections.get(current_id, {}).get("title", current_id.title()) or current_id.title())
            current_title = f"{self.info_section_index + 1:02d} {label}"
        focus = "RIGHT" if self.info_panel_focus == "right" else "LEFT"
        prefix = ""
        if current_title:
            prefix = f"{current_title} | focus:{focus}"
        generated_at = str(self.info_payload_data.get("generated_at", "") or "").strip()
        if generated_at:
            match = re.match(r"^\d{4}-\d{2}-\d{2}T(\d{2}:\d{2})", generated_at)
            if match and prefix:
                return f"{prefix} | {match.group(1)} UTC"
            if match:
                return f"{match.group(1)} UTC"
        return prefix or "loading"

    def run_json_command_quiet(self, cmd, stdin_data="", log_user_triggered=False, timeout=None):
        rendered = " ".join(shlex.quote(part) for part in cmd)
        rc, stdout, stderr, duration, _rendered, _merged_output = self.capture_command(
            cmd,
            stdin_data=stdin_data,
            loading_text="Loading info-hub...",
            interactive=False,
            log_user_triggered=log_user_triggered,
            timeout=timeout,
        )
        return rc, stdout, stderr, duration, rendered

    def reset_info_dashboard_state(self):
        self.info_payload_data = {}
        self.info_sections = {}
        self.info_section_order = []
        self.info_section_index = 0
        self.info_panel_focus = "left"
        self.info_scroll = 0
        self.info_list_hscroll = 0
        self.info_hscroll = 0
        self.info_back_state = "menu"
        self.info_loaded_at = 0.0

    def enter_info_dashboard(self, back_state="menu"):
        self.reset_info_dashboard_state()
        self.info_back_state = back_state or "menu"
        return self.refresh_info_dashboard(initial_load=True)

    def set_info_payload(self, payload):
        if not isinstance(payload, dict):
            return False
        sections = payload.get("sections", {})
        if not isinstance(sections, dict):
            sections = {}
        normalized_sections = {}
        for section_id, section in sections.items():
            if not isinstance(section, dict):
                continue
            normalized_sections[str(section_id)] = dict(section)
        order = payload.get("section_order", [])
        normalized_order = []
        if isinstance(order, list):
            normalized_order = [str(item).strip() for item in order if str(item).strip() in normalized_sections]
        if not normalized_order:
            normalized_order = list(normalized_sections.keys())
        self.info_payload_data = dict(payload)
        self.info_sections = normalized_sections
        self.info_section_order = normalized_order
        self.info_payload_data["sections"] = dict(self.info_sections)
        self.info_payload_data["section_order"] = list(self.info_section_order)
        self.info_section_index = max(0, min(self.info_section_index, max(0, len(self.info_section_order) - 1)))
        self.info_scroll = max(0, self.info_scroll)
        self.info_hscroll = max(0, self.info_hscroll)
        self.info_loaded_at = time.time()
        return True

    def current_info_section_id(self):
        if not self.info_section_order:
            return ""
        self.info_section_index = max(0, min(self.info_section_index, len(self.info_section_order) - 1))
        return self.info_section_order[self.info_section_index]

    def current_info_section(self):
        current_id = self.current_info_section_id()
        return self.info_sections.get(current_id, {}) if current_id else {}

    def info_layout(self, height, width):
        content_top, content_height, _ = self.screen_content_layout(height, width, footer_entries=self.footer_entries())
        left_width = max(16, min(28, int(width * 0.28)))
        right_left = left_width + 2
        right_width = max(20, width - right_left - 1)
        return {
            "left_top": content_top,
            "left_left": 0,
            "left_width": left_width,
            "left_height": content_height,
            "detail_top": content_top,
            "detail_left": right_left,
            "detail_width": right_width,
            "detail_height": content_height,
            "detail_visible": max(1, content_height - 2),
        }

    def info_wrap_text(self, text, width):
        if width <= 1:
            return []
        text = str(text or "")
        if not text:
            return [""]
        try:
            return textwrap.wrap(text, width=width, break_long_words=True, replace_whitespace=False) or [text[:width]]
        except Exception:
            return [text[:width]]

    def info_fit_lines(self, lines, width):
        out = []
        for raw in lines or []:
            text = str(raw or "")
            if not text:
                out.append("")
                continue
            if len(text) <= width:
                out.append(text)
                continue
            out.extend(self.info_wrap_text(text, width))
        return out or [""]

    def info_render_label_rows(self, rows, width):
        rows = rows or []
        label_width = 8
        for row in rows:
            if isinstance(row, dict):
                label_width = max(label_width, len(str(row.get("label", "") or "")))
        label_width = max(8, min(14, label_width))
        compact = width < 72
        value_width = max(18, width - label_width - 2)
        out = []
        for row in rows:
            if not isinstance(row, dict):
                continue
            label = str(row.get("label", "") or "")
            value = str(row.get("value", "") or "")
            if compact and (len(value) > value_width or len(label) + 2 + len(value) > width):
                out.append(label)
                for line in self.info_wrap_text(value, max(18, width - 2)):
                    out.append(f"  {line}")
                continue
            lines = self.info_wrap_text(value, value_width)
            out.append(f"{label.ljust(label_width)}  {lines[0]}")
            pad = " " * (label_width + 2)
            for line in lines[1:]:
                out.append(f"{pad}{line}")
        return out

    def info_render_distros_table(self, rows, width):
        cols = [
            ("NAME", 10, lambda row: row.get("distro", "")),
            ("RELEASE", 10, lambda row: row.get("release", "")),
            ("MNT", 5, lambda row: "yes" if row.get("mounted") else "no"),
            ("SES", 4, lambda row: str(row.get("sessions", 0))),
            ("SVC", 4, lambda row: str(row.get("services", 0))),
            ("DESKTOP", 8, lambda row: row.get("desktop", "")),
            ("TOR", 4, lambda row: "on" if row.get("tor") else "off"),
            ("ROOTFS", 8, lambda row: row.get("rootfs_text", "...")),
        ]
        required = sum(col_width for _name, col_width, _getter in cols) + len(cols) - 1
        if width < required:
            return []
        header = " ".join(name.ljust(col_width) for name, col_width, _getter in cols)
        sep = " ".join("-" * col_width for _name, col_width, _getter in cols)
        out = [header, sep]
        for row in rows:
            parts = []
            for _name, col_width, getter in cols:
                value = str(getter(row) or "")
                parts.append(value[:col_width].ljust(col_width))
            out.append(" ".join(parts))
        return out

    def info_render_distros_stacked(self, rows, width):
        out = []
        for idx, row in enumerate(rows):
            if idx:
                out.append("")
            title = str(row.get("distro", "") or "<distro>")
            out.append(title)
            out.append("~" * len(title))
            out.extend(
                self.info_render_label_rows(
                    [
                        {"label": "Release", "value": row.get("release", "")},
                        {"label": "Mounted", "value": "yes" if row.get("mounted") else "no"},
                        {"label": "Sessions", "value": str(row.get("sessions", 0))},
                        {"label": "Services", "value": str(row.get("services", 0))},
                        {"label": "Desktop", "value": row.get("desktop", "no")},
                        {"label": "Tor", "value": "on" if row.get("tor") else "off"},
                        {"label": "Rootfs", "value": row.get("rootfs_text", "...")},
                    ],
                    width,
                )
            )
        return out or ["No installed distros."]

    def info_section_lines(self, section_id, width):
        section = self.info_sections.get(section_id, {})
        if not isinstance(section, dict):
            return ["No data available."]
        if section_id == "storage":
            lines = self.info_render_label_rows(section.get("rows", []), width)
            distro_sizes = section.get("distro_sizes", [])
            if distro_sizes:
                lines.append("")
                lines.append("Per-Distro Sizes")
                lines.append("~" * len("Per-Distro Sizes"))
                for row in distro_sizes:
                    distro = str(row.get("distro", "") or "<distro>")
                    value = f"rootfs {row.get('rootfs_text', '...')}"
                    lines.extend(self.info_render_label_rows([{"label": distro, "value": value}], width))
            return lines or ["No data available."]
        if section_id == "distro":
            lines = self.info_render_label_rows(section.get("summary_rows", []), width)
            rows = section.get("distros", [])
            if not rows:
                lines.append("")
                lines.append("No installed distros.")
                return lines
            lines.append("")
            table = self.info_render_distros_table(rows, width)
            if table:
                lines.extend(table)
            else:
                lines.extend(self.info_render_distros_stacked(rows, width))
            return lines
        return self.info_render_label_rows(section.get("rows", []), width) or ["No data available."]

    def info_current_lines(self, width):
        current_id = self.current_info_section_id()
        if not current_id:
            return ["Loading info-hub..."]
        return self.info_section_lines(current_id, width)

    def normalize_info_view(self):
        lines = self.info_current_lines(96)
        layout = self.info_layout(*self.stdscr.getmaxyx())
        visible = layout["detail_visible"]
        max_scroll = max(0, len(lines) - visible)
        self.info_scroll = max(0, min(self.info_scroll, max_scroll))
        inner_width = max(18, layout["detail_width"] - 4)
        max_hscroll = max(0, max((len(line) for line in lines), default=0) - inner_width)
        self.info_hscroll = max(0, min(self.info_hscroll, max_hscroll))
        return lines

    def move_info_section(self, delta):
        if not self.info_section_order:
            return
        self.info_section_index = (self.info_section_index + delta) % len(self.info_section_order)
        self.info_scroll = 0
        self.info_hscroll = 0
        self.info_panel_focus = "left"
        self.normalize_info_view()

    def scroll_info_content(self, delta, page=False):
        self.info_panel_focus = "right"
        lines = self.normalize_info_view()
        layout = self.info_layout(*self.stdscr.getmaxyx())
        step = layout["detail_visible"] if page else 1
        max_scroll = max(0, len(lines) - layout["detail_visible"])
        self.info_scroll = max(0, min(max_scroll, self.info_scroll + (delta * step)))

    def info_visible_section_start(self, layout):
        visible = max(1, layout["left_height"] - 2)
        entries = self.info_section_list_entries(layout)
        if not entries:
            return 0
        start = 0
        while start < len(entries):
            used = 0
            last = start - 1
            idx = start
            while idx < len(entries):
                need = len(entries[idx]["lines"])
                if used + need > visible:
                    break
                used += need
                last = idx
                idx += 1
            if last < start:
                return start
            if start <= self.info_section_index <= last:
                return start
            start += 1
        return max(0, min(self.info_section_index, len(entries) - 1))

    def info_section_list_entries(self, layout):
        inner_width = max(8, layout["left_width"] - 4)
        label_width = max(4, inner_width - 4)
        entries = []
        for idx, section_id in enumerate(self.info_section_order):
            section = self.info_sections.get(section_id, {})
            label = str(section.get("title", section_id.title()) or section_id.title())
            wrapped = self.info_wrap_text(label, label_width)
            rendered = []
            for line_idx, line in enumerate(wrapped):
                marker = ">" if idx == self.info_section_index and line_idx == 0 else " "
                prefix = f"{marker} {idx + 1:02d} " if line_idx == 0 else "     "
                rendered.append(prefix + line)
            entries.append({"index": idx, "lines": rendered})
        return entries

    def info_section_row_at(self, y, layout):
        if y <= layout["left_top"] or y >= layout["left_top"] + layout["left_height"] - 1:
            return None
        entries = self.info_section_list_entries(layout)
        start = self.info_visible_section_start(layout)
        visible = max(1, layout["left_height"] - 2)
        current_y = layout["left_top"] + 1
        used = 0
        for entry in entries[start:]:
            need = len(entry["lines"])
            if used + need > visible:
                break
            if current_y <= y < current_y + need:
                return entry["index"]
            current_y += need
            used += need
        return None

    def refresh_info_dashboard(self, initial_load=False):
        selected_id = self.current_info_section_id()
        cmd = [self.runner, "info", "--json"]
        rc, stdout, stderr, duration, rendered = self.run_json_command_quiet(cmd, log_user_triggered=True, timeout=120.0)
        if rc != 0:
            self.show_result(rendered, stdout, stderr, rc, duration, back_state=self.info_back_state, rerun_cmd=cmd)
            return False
        try:
            payload = parse_json_payload(stdout)
        except Exception as exc:
            parse_out = (stdout or "") + f"\nparse error: {exc}\n" + (stderr or "")
            self.show_result(rendered, parse_out, "", 1, duration, back_state=self.info_back_state, rerun_cmd=cmd)
            return False
        if not self.set_info_payload(payload):
            self.show_result(rendered, stdout, "invalid info payload\n", 1, duration, back_state=self.info_back_state, rerun_cmd=cmd)
            return False
        if selected_id and selected_id in self.info_section_order:
            self.info_section_index = self.info_section_order.index(selected_id)
        self.info_scroll = 0
        self.info_hscroll = 0
        self.normalize_info_view()
        self.state = "info"
        self.status("info-hub loaded" if initial_load else "info-hub refreshed", "ok")
        return True

    def draw_info_section_list(self, layout, height, width):
        box_attr = self.color(2, curses.A_BOLD) if self.info_panel_focus == "left" else self.color(4)
        title_attr = self.color(2, curses.A_BOLD) if self.info_panel_focus == "left" else self.color(1, curses.A_BOLD)
        draw_box(
            self.stdscr,
            layout["left_top"],
            layout["left_left"],
            layout["left_height"],
            layout["left_width"],
            "SECTIONS",
            box_attr,
            title_attr,
        )
        entries = self.info_section_list_entries(layout)
        start = self.info_visible_section_start(layout)
        visible = max(1, layout["left_height"] - 2)
        current_y = layout["left_top"] + 1
        used = 0
        inner_width = max(1, layout["left_width"] - 4)
        for entry in entries[start:]:
            need = len(entry["lines"])
            if used + need > visible:
                break
            selected = entry["index"] == self.info_section_index
            attr = self.color(2, curses.A_BOLD | curses.A_REVERSE) if selected else self.color(0)
            for line in entry["lines"]:
                if self.info_list_hscroll > 0:
                    line = line[self.info_list_hscroll:]
                addstr_clipped(
                    self.stdscr,
                    current_y,
                    layout["left_left"] + 2,
                    line,
                    inner_width,
                    attr,
                )
                current_y += 1
            used += need

    def draw_info_detail_box(self, layout, height, width):
        current_id = self.current_info_section_id()
        section = self.info_sections.get(current_id, {})
        title = str(section.get("title", current_id.title()) or current_id.title()) if current_id else "Info"
        box_attr = self.color(2, curses.A_BOLD) if self.info_panel_focus == "right" else self.color(4)
        title_attr = self.color(2, curses.A_BOLD) if self.info_panel_focus == "right" else self.color(1, curses.A_BOLD)
        draw_box(
            self.stdscr,
            layout["detail_top"],
            layout["detail_left"],
            layout["detail_height"],
            layout["detail_width"],
            f"INFO-HUB: {title}".upper(),
            box_attr,
            title_attr,
        )
        visible = layout["detail_visible"]
        inner_width = max(18, layout["detail_width"] - 4)
        lines = self.normalize_info_view()
        end = min(len(lines), self.info_scroll + visible)
        for row_idx, line_idx in enumerate(range(self.info_scroll, end)):
            line = lines[line_idx]
            if self.info_hscroll > 0:
                line = line[self.info_hscroll:]
            addstr_clipped(
                self.stdscr,
                layout["detail_top"] + 1 + row_idx,
                layout["detail_left"] + 2,
                line,
                inner_width,
                self.color(0),
            )

    def draw_info_dashboard(self, height, width):
        self.normalize_info_view()
        layout = self.info_layout(height, width)
        self.draw_info_section_list(layout, height, width)
        self.draw_info_detail_box(layout, height, width)

    def exit_info_dashboard(self):
        self.state = self.info_back_state or "menu"
        self.status("Closed info-hub", "info")
        return True

    def handle_info_key(self, key):
        if key in (9, curses.KEY_BTAB):
            self.info_panel_focus = "right" if self.info_panel_focus == "left" else "left"
            self.normalize_info_view()
            return True
        if key == curses.KEY_UP:
            if self.info_panel_focus == "left":
                self.move_info_section(-1)
            else:
                self.scroll_info_content(-1)
            return True
        if key == curses.KEY_DOWN:
            if self.info_panel_focus == "left":
                self.move_info_section(1)
            else:
                self.scroll_info_content(1)
            return True
        if key in (ord("<"), curses.KEY_LEFT):
            if self.info_panel_focus == "right":
                self.info_hscroll = max(0, self.info_hscroll - self.hscroll_step())
                self.normalize_info_view()
            else:
                layout = self.info_layout(*self.stdscr.getmaxyx())
                rows = []
                for entry in self.info_section_list_entries(layout):
                    rows.extend((line, self.color(0)) for line in entry["lines"])
                self.scroll_text_panel_horizontal(
                    "info_section_index",
                    "info_list_hscroll",
                    rows,
                    max(1, layout["left_height"] - 2),
                    max(1, layout["left_width"] - 4),
                    -1,
                )
            return True
        if key in (ord(">"), curses.KEY_RIGHT):
            if self.info_panel_focus == "right":
                self.info_hscroll += self.hscroll_step()
                self.normalize_info_view()
            else:
                layout = self.info_layout(*self.stdscr.getmaxyx())
                rows = []
                for entry in self.info_section_list_entries(layout):
                    rows.extend((line, self.color(0)) for line in entry["lines"])
                self.scroll_text_panel_horizontal(
                    "info_section_index",
                    "info_list_hscroll",
                    rows,
                    max(1, layout["left_height"] - 2),
                    max(1, layout["left_width"] - 4),
                    1,
                )
            return True
        if key in (ord("r"), ord("R")):
            return self.refresh_info_dashboard(initial_load=False)
        if key in (ord("b"), ord("B")):
            return self.exit_info_dashboard()
        if key in (ord("q"), ord("Q")):
            return False
        return True
