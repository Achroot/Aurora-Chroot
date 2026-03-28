    def editor_wrapped_lines(self, text, width):
        width = max(1, int(width))
        content = str(text or "")
        if not content:
            return [""], [0]
        lines = []
        starts = []
        idx = 0
        size = len(content)
        while idx < size:
            starts.append(idx)
            lines.append(content[idx : idx + width])
            idx += width
        return lines, starts

