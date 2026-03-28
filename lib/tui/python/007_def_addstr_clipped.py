def addstr_clipped(win, y, x, text, max_width, attr=0):
    if max_width <= 0:
        return
    height, width = win.getmaxyx()
    if y < 0 or y >= height:
        return
    if x < 0 or x >= width:
        return
    max_len = min(max_width, width - x - 1)
    if max_len <= 0:
        return
    snippet = str(text)[:max_len]
    try:
        win.addstr(y, x, snippet, attr)
    except curses.error:
        return


