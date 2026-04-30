    def move_menu(self, delta):
        if not self.commands:
            return
        self.menu_index = (self.menu_index + delta) % len(self.commands)

