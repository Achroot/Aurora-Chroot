def addstr_safe(win, y, x, text, attr=0):
    height, width = win.getmaxyx()
    if y < 0 or y >= height:
        return
    if x < 0 or x >= width:
        return
    max_len = width - x - 1
    if max_len <= 0:
        return
    snippet = str(text)[:max_len]
    try:
        win.addstr(y, x, snippet, attr)
    except curses.error:
        return


