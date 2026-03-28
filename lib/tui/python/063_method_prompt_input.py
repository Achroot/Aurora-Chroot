    def prompt_input(self, label, current_value):
        height, width = self.stdscr.getmaxyx()
        prompt = str(label)
        current_text = str(current_value)
        is_exec = (self.active_command == "exec")

        min_w = 74 if is_exec else 50
        box_w = min(width - 2, max(min_w, len(prompt) + 20))
        box_w = max(30, box_w)

        curses.noecho()
        try:
            curses.curs_set(1)
        except curses.error:
            pass

        result = list(current_text)
        cursor_pos = len(result)
        view_top = 0
        preferred_col = None

        try:
            while True:
                content = "".join(result)
                display_w = max(10, box_w - 6)
                lines, starts = self.editor_wrapped_lines(content, display_w)
                row, col = self.editor_cursor_row_col(cursor_pos, starts, lines)

                min_h = 11 if is_exec else 8
                desired_h = len(lines) + 5
                box_h = min(height - 4, max(min_h, desired_h))
                box_h = max(6, box_h)
                visible_rows = max(1, box_h - 5)

                if row < view_top:
                    view_top = row
                elif row >= view_top + visible_rows:
                    view_top = row - visible_rows + 1
                max_view_top = max(0, len(lines) - visible_rows)
                view_top = max(0, min(view_top, max_view_top))

                top = max(2, (height - box_h) // 2)
                left = max(0, (width - box_w) // 2)
                title = "EDIT COMMAND" if is_exec and prompt.lower().startswith("command") else "EDIT VALUE"
                helper = "Enter: save  Esc: cancel  Arrows: move cursor"

                draw_box(self.stdscr, top, left, box_h, box_w, title, self.color(4), self.color(2, curses.A_BOLD))
                addstr_clipped(self.stdscr, top + 1, left + 2, prompt, box_w - 4, self.color(1, curses.A_BOLD))
                addstr_clipped(self.stdscr, top + box_h - 2, left + 2, helper, box_w - 4, self.color(3))

                for i in range(visible_rows):
                    line_y = top + 2 + i
                    line_idx = view_top + i
                    line = lines[line_idx] if line_idx < len(lines) else ""
                    try:
                        self.stdscr.addstr(line_y, left + 2, " " * (box_w - 4))
                        if line:
                            self.stdscr.addstr(line_y, left + 2, line)
                    except curses.error:
                        pass

                cursor_y = top + 2 + (row - view_top)
                cursor_x = left + 2 + col
                try:
                    self.stdscr.move(cursor_y, cursor_x)
                except curses.error:
                    pass
                self.stdscr.refresh()

                try:
                    ch = self.stdscr.getch()
                except Exception:
                    continue

                if ch in (10, 13, curses.KEY_ENTER):
                    break
                if ch == 27:
                    return current_value
                if ch in (curses.KEY_BACKSPACE, 127, 8):
                    preferred_col = None
                    if cursor_pos > 0:
                        result.pop(cursor_pos - 1)
                        cursor_pos -= 1
                    continue
                if ch == curses.KEY_DC:
                    preferred_col = None
                    if cursor_pos < len(result):
                        result.pop(cursor_pos)
                    continue
                if ch == curses.KEY_LEFT:
                    preferred_col = None
                    if cursor_pos > 0:
                        cursor_pos -= 1
                    continue
                if ch == curses.KEY_RIGHT:
                    preferred_col = None
                    if cursor_pos < len(result):
                        cursor_pos += 1
                    continue
                if ch == curses.KEY_HOME:
                    preferred_col = None
                    cursor_pos = starts[row]
                    continue
                if ch == curses.KEY_END:
                    preferred_col = None
                    cursor_pos = starts[row] + len(lines[row])
                    continue
                if ch == curses.KEY_UP:
                    if preferred_col is None:
                        preferred_col = col
                    if row > 0:
                        target_col = min(len(lines[row - 1]), preferred_col)
                        cursor_pos = starts[row - 1] + target_col
                    continue
                if ch == curses.KEY_DOWN:
                    if preferred_col is None:
                        preferred_col = col
                    if row + 1 < len(lines):
                        target_col = min(len(lines[row + 1]), preferred_col)
                        cursor_pos = starts[row + 1] + target_col
                    continue
                if 32 <= ch <= 126:
                    preferred_col = None
                    result.insert(cursor_pos, chr(ch))
                    cursor_pos += 1
        except Exception:
            pass
        finally:
            try:
                curses.curs_set(0)
            except curses.error:
                pass

        return "".join(result)

