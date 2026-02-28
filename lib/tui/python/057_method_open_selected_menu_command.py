    def open_selected_menu_command(self):
        selected = self.commands[self.menu_index]
        if selected == "distros":
            self.enter_distros()
            return True
        if selected == "settings":
            self.enter_settings()
            return True
        self.set_active_command(selected)
        self.state = "form"
        self.status(f"Configuring {selected}")
        return True

