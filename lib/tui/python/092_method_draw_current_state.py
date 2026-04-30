    def draw_current_state(self):
        height, width = self.stdscr.getmaxyx()
        self.stdscr.erase()
        if self.screen_too_small(height, width):
            self.draw_too_small(height, width)
            return height, width
        self.draw_header(height, width)
        if self.state == "menu":
            self.draw_menu(height, width)
        elif self.state == "form":
            self.draw_form(height, width)
        elif self.state == "distros":
            self.draw_distros(height, width)
        elif self.state == "install_local":
            self.draw_install_local(height, width)
        elif self.state == "settings":
            self.draw_settings(height, width)
        elif self.state == "busybox":
            self.draw_busybox(height, width)
        elif self.state == "tor_apps_tunneling":
            self.draw_tor_apps_tunneling(height, width)
        elif self.state == "tor_exit_mode":
            self.draw_tor_exit_mode(height, width)
        elif self.state == "info":
            self.draw_info_dashboard(height, width)
        elif self.state == "result":
            self.draw_result(height, width)
        self.draw_footer(height, width)
        return height, width
