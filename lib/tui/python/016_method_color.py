    def color(self, pair, extra=0):
        if curses.has_colors() and pair > 0:
            return curses.color_pair(pair) | extra
        return extra

