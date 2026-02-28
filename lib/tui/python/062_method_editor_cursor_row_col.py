    def editor_cursor_row_col(self, cursor_pos, starts, lines):
        if not lines:
            return 0, 0
        cursor = max(0, int(cursor_pos))
        row = len(lines) - 1
        col = len(lines[-1])
        for idx, start in enumerate(starts):
            end = start + len(lines[idx])
            if cursor <= end:
                row = idx
                col = cursor - start
                break
        return row, max(0, col)

