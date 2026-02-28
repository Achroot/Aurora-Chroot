    def handle_form_key(self, key):
        if key in (curses.KEY_UP, ord("k")):
            self.move_form(-1)
            return True
        if key in (curses.KEY_DOWN, ord("j")):
            self.move_form(1)
            return True
        if key in (ord("h"),):
            if self.active_command != "exec":
                field = self.current_field()
                if field:
                    self.cycle_field(field, -1)
            return True
        if key in (ord("l"),):
            if self.active_command != "exec":
                field = self.current_field()
                if field:
                    self.cycle_field(field, 1)
            return True
        if key in (10, 13, curses.KEY_ENTER, ord("e"), ord("E"), ord(" ")):
            self.edit_current_field()
            return True
        if key in (ord("c"), ord("C")):
            self.clear_current_field()
            return True
        if key in (ord("r"), ord("R")):
            self.run_current_command()
            return True
        if key in (ord("b"), ord("B")):
            self.state = "menu"
            return True
        if key in (ord("q"), ord("Q")):
            return False
        return True

