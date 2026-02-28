    def draw_current_state(self):
        height, width = self.stdscr.getmaxyx()
        self.stdscr.erase()
        if height < 14 or width < 54:
            self.draw_too_small(height, width)
            return height, width
        self.draw_header(height, width)
        if self.state == "menu":
            self.draw_menu(height, width)
        elif self.state == "form":
            self.draw_form(height, width)
        elif self.state == "distros":
            self.draw_distros(height, width)
        elif self.state == "settings":
            self.draw_settings(height, width)
        elif self.state == "result":
            self.draw_result(height, width)
        self.draw_footer(height, width)
        return height, width

