    def hscroll_step(self):
        return 8

    def text_panel_rows(self, rows, default_attr=None):
        normalized = []
        if default_attr is None:
            default_attr = self.color(0)
        for row in rows or []:
            if isinstance(row, tuple) and len(row) >= 2:
                normalized.append((str(row[0] or ""), row[1]))
            else:
                normalized.append((str(row or ""), default_attr))
        return normalized

    def text_panel_max_hscroll(self, rows, inner_width):
        inner_width = max(1, int(inner_width))
        return max(0, max((len(text) for text, _attr in self.text_panel_rows(rows)), default=0) - inner_width)

    def clamp_text_panel_scroll(self, scroll_attr, hscroll_attr, rows, visible_height, inner_width):
        normalized = self.text_panel_rows(rows)
        visible_height = max(1, int(visible_height))
        inner_width = max(1, int(inner_width))
        max_scroll = max(0, len(normalized) - visible_height)
        current_scroll = max(0, min(int(getattr(self, scroll_attr, 0) or 0), max_scroll))
        setattr(self, scroll_attr, current_scroll)
        max_hscroll = self.text_panel_max_hscroll(normalized, inner_width)
        current_hscroll = max(0, min(int(getattr(self, hscroll_attr, 0) or 0), max_hscroll))
        setattr(self, hscroll_attr, current_hscroll)
        return normalized, current_scroll, current_hscroll

    def scroll_text_panel_vertical(self, scroll_attr, hscroll_attr, rows, visible_height, inner_width, delta, page=False):
        normalized, current_scroll, _current_hscroll = self.clamp_text_panel_scroll(
            scroll_attr,
            hscroll_attr,
            rows,
            visible_height,
            inner_width,
        )
        step = max(1, int(visible_height)) if page else 1
        max_scroll = max(0, len(normalized) - max(1, int(visible_height)))
        setattr(self, scroll_attr, max(0, min(max_scroll, current_scroll + (delta * step))))

    def scroll_text_panel_horizontal(self, scroll_attr, hscroll_attr, rows, visible_height, inner_width, delta):
        normalized = self.text_panel_rows(rows)
        inner_width = max(1, int(inner_width))
        max_hscroll = self.text_panel_max_hscroll(normalized, inner_width)
        current_hscroll = max(0, min(int(getattr(self, hscroll_attr, 0) or 0), max_hscroll))
        setattr(
            self,
            hscroll_attr,
            max(0, min(max_hscroll, current_hscroll + (delta * self.hscroll_step()))),
        )

    def draw_text_panel_rows(self, top, left, height, width, rows, scroll_attr, hscroll_attr):
        visible_height = max(1, height - 2)
        inner_width = max(1, width - 4)
        normalized, scroll, hscroll = self.clamp_text_panel_scroll(
            scroll_attr,
            hscroll_attr,
            rows,
            visible_height,
            inner_width,
        )
        for idx in range(visible_height):
            row_idx = scroll + idx
            if row_idx >= len(normalized):
                break
            text, attr = normalized[row_idx]
            if hscroll > 0:
                text = text[hscroll:]
            addstr_clipped(self.stdscr, top + 1 + idx, left + 2, text, inner_width, attr)

    def wrapped_panel_rows(self, text, width, attr=None):
        if attr is None:
            attr = self.color(0)
        return [(line, attr) for line in wrap_lines(text, width)]

    def reset_panel_scroll(self, *attrs):
        for attr in attrs:
            setattr(self, attr, 0)
