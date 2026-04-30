    def open_selected_menu_command(self):
        selected = self.commands[self.menu_index]
        if selected == "distros":
            self.enter_distros()
            return True
        if selected == "install-local":
            self.set_active_command(selected)
            self.enter_install_local()
            return True
        if selected == "settings":
            self.enter_settings()
            return True
        if selected == "busybox":
            self.enter_busybox()
            return True
        if selected == "info":
            self.set_active_command(selected)
            return self.enter_info_dashboard(back_state="menu")
        self.set_active_command(selected)
        self.state = "form"
        self.status(f"Configuring {selected}")
        return True
