    def draw_settings(self, height, width):
        content_top, content_height, _ = self.screen_content_layout(height, width)
        left_width = max(32, int(width * 0.46))
        right_left = left_width + 2
        right_width = width - right_left - 1

        left_active = self.settings_panel_focus != "right"
        right_active = self.settings_panel_focus == "right"
        draw_box(
            self.stdscr,
            content_top,
            0,
            content_height,
            left_width,
            f"SETTINGS{' [ACTIVE]' if left_active else ''}",
            self.color(2) if left_active else self.color(4),
            self.color(2, curses.A_BOLD) if left_active else self.color(1, curses.A_BOLD),
        )
        draw_box(
            self.stdscr,
            content_top,
            right_left,
            content_height,
            right_width,
            f"DETAILS{' [ACTIVE]' if right_active else ''}",
            self.color(2) if right_active else self.color(4),
            self.color(2, curses.A_BOLD) if right_active else self.color(1, curses.A_BOLD),
        )

        if not self.settings_rows:
            addstr_clipped(self.stdscr, content_top + 2, 2, "No settings loaded. Press r to refresh.", left_width - 4, self.color(5))
            return

        row = self.current_setting()
        list_top = content_top + 1
        visible_rows = max(1, content_height - 2)
        start = max(0, self.settings_index - visible_rows + 1)
        end = min(len(self.settings_rows), start + visible_rows)

        for idx in range(start, end):
            item = self.settings_rows[idx]
            key = item.get("key", "")
            current = item.get("current_text", "")
            pending = self.settings_pending.get(key, current)
            changed = "*" if str(pending) != str(current) else " "
            marker = "->" if idx == self.settings_index else "  "
            line = f"{marker}{changed} {key} = {pending}"
            if self.settings_left_hscroll > 0:
                line = line[self.settings_left_hscroll:]
            style = self.color(2, curses.A_BOLD) if idx == self.settings_index else self.color(0)
            addstr_clipped(self.stdscr, list_top + (idx - start), 2, line, left_width - 4, style)

        if not row:
            return

        key = row.get("key", "")
        current = row.get("current_text", "")
        pending = self.settings_pending.get(key, current)

        rows = self.settings_detail_rows_for_width(right_width)
        self.draw_text_panel_rows(
            content_top,
            right_left,
            content_height,
            right_width,
            rows,
            "settings_detail_scroll",
            "settings_detail_hscroll",
        )

    def settings_left_rows(self):
        rows = []
        for item in self.settings_rows:
            key = item.get("key", "")
            current = item.get("current_text", "")
            pending = self.settings_pending.get(key, current)
            changed = "*" if str(pending) != str(current) else " "
            rows.append((f"{changed} {key} = {pending}", self.color(0)))
        return rows

    def settings_detail_rows_for_width(self, right_width):
        row = self.current_setting()
        if not row:
            return []
        key = row.get("key", "")
        current = row.get("current_text", "")
        pending = self.settings_pending.get(key, current)
        rows = [
            (key, self.color(2, curses.A_BOLD)),
            ("", self.color(0)),
            (f"Current: {current}", self.color(0)),
            (f"Pending: {pending}", self.color(1, curses.A_BOLD)),
            (f"Default: {row.get('default_text','')}", self.color(0)),
            (f"Allowed: {row.get('allowed_text','')}", self.color(6)),
            (f"Status: {row.get('status','')}", self.color(0)),
            ("", self.color(0)),
            ("Description:", self.color(6, curses.A_BOLD)),
        ]
        rows.extend(self.wrapped_panel_rows(row.get("description", ""), right_width - 4, self.color(0)))
        return rows
