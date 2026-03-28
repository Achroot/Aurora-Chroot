    def handle_distros_key(self, key):
        if key in (curses.KEY_UP, ord("k")):
            self.move_distros(-1)
            return True
        if key in (curses.KEY_DOWN, ord("j")):
            self.move_distros(1)
            return True
        if key in (ord("r"), ord("R")):
            self.load_distros_catalog(back_state="distros", refresh=True)
            if self.state != "result":
                self.status("Catalog fetched from network", "ok")
            return True
        if key in (10, 13, curses.KEY_ENTER, curses.KEY_RIGHT):
            if self.distros_stage == "distros":
                self.distros_stage = "versions"
                self.distros_version_index = 0
            elif self.distros_stage == "versions":
                self.distros_stage = "detail"
            return True
        if key in (ord("i"), ord("I")):
            if self.distros_stage in ("versions", "detail"):
                self.install_selected_distro_version()
            return True
        if key in (ord("b"), ord("B"), curses.KEY_LEFT):
            if self.distros_stage == "detail":
                self.distros_stage = "versions"
            elif self.distros_stage == "versions":
                self.distros_stage = "distros"
            else:
                self.state = "menu"
            return True
        if key in (ord("q"), ord("Q")):
            return False
        return True

