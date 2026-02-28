    def draw_settings(self, height, width):
        content_top = 2
        content_height = height - content_top - 3
        left_width = max(32, int(width * 0.46))
        right_left = left_width + 2
        right_width = width - right_left - 1

        draw_box(self.stdscr, content_top, 0, content_height, left_width, "SETTINGS", self.color(4), self.color(1, curses.A_BOLD))
        draw_box(self.stdscr, content_top, right_left, content_height, right_width, "DETAILS", self.color(4), self.color(1, curses.A_BOLD))

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
            style = self.color(2, curses.A_BOLD) if idx == self.settings_index else self.color(0)
            addstr_clipped(self.stdscr, list_top + (idx - start), 2, line, left_width - 4, style)

        if not row:
            return

        key = row.get("key", "")
        current = row.get("current_text", "")
        pending = self.settings_pending.get(key, current)

        y = content_top + 2
        addstr_clipped(self.stdscr, y, right_left + 2, key, right_width - 4, self.color(2, curses.A_BOLD))
        y += 2
        addstr_clipped(self.stdscr, y, right_left + 2, f"Current: {current}", right_width - 4, self.color(0))
        y += 1
        addstr_clipped(self.stdscr, y, right_left + 2, f"Pending: {pending}", right_width - 4, self.color(1, curses.A_BOLD))
        y += 1
        addstr_clipped(self.stdscr, y, right_left + 2, f"Default: {row.get('default_text','')}", right_width - 4, self.color(0))
        y += 1
        addstr_clipped(self.stdscr, y, right_left + 2, f"Allowed: {row.get('allowed_text','')}", right_width - 4, self.color(6))
        y += 1
        addstr_clipped(self.stdscr, y, right_left + 2, f"Status: {row.get('status','')}", right_width - 4, self.color(0))
        y += 2
        addstr_clipped(self.stdscr, y, right_left + 2, "Description:", right_width - 4, self.color(6, curses.A_BOLD))
        y += 1
        for line in wrap_lines(row.get("description", ""), right_width - 4):
            if y >= content_top + content_height - 2:
                break
            addstr_clipped(self.stdscr, y, right_left + 2, line, right_width - 4, self.color(0))
            y += 1

