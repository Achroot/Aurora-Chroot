def draw_box(win, top, left, height, width, title="", attr=0, title_attr=0):
    if height < 2 or width < 2:
        return
    addstr_safe(win, top, left, "+" + "-" * (width - 2) + "+", attr)
    for row in range(top + 1, top + height - 1):
        addstr_safe(win, row, left, "|", attr)
        addstr_safe(win, row, left + width - 1, "|", attr)
    addstr_safe(win, top + height - 1, left, "+" + "-" * (width - 2) + "+", attr)
    if title:
        label = f" {title} "
        x = min(left + 2, left + max(1, width - len(label) - 2))
        addstr_clipped(win, top, x, label, width - 4, title_attr or attr)


