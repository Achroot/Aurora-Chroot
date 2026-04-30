    def run(self):
        self.setup()
        while True:
            height, width = self.draw_current_state()
            self.stdscr.refresh()
            
            if self.screen_too_small(height, width):
                key = self.stdscr.getch()
                if key in (ord("q"), ord("Q")):
                    return
                continue

            try:
                self.stdscr.timeout(self.status_poll_timeout_ms())
                key = self.stdscr.getch()
            except KeyboardInterrupt:
                return

            if key == -1:
                continue
            if key == curses.KEY_RESIZE:
                continue
            if key == curses.KEY_MOUSE:
                self.handle_mouse()
                continue
            self.dismiss_status_for_key(key)

            if self.state == "menu":
                if not self.handle_menu_key(key):
                    return
            elif self.state == "form":
                if not self.handle_form_key(key):
                    return
            elif self.state == "distros":
                if not self.handle_distros_key(key):
                    return
            elif self.state == "install_local":
                if not self.handle_install_local_key(key):
                    return
            elif self.state == "settings":
                if not self.handle_settings_key(key):
                    return
            elif self.state == "busybox":
                if not self.handle_busybox_key(key):
                    return
            elif self.state == "tor_apps_tunneling":
                if not self.handle_tor_apps_tunneling_key(key):
                    return
            elif self.state == "tor_exit_mode":
                if not self.handle_tor_exit_mode_key(key):
                    return
            elif self.state == "info":
                if not self.handle_info_key(key):
                    return
            else:
                if not self.handle_result_key(key):
                    return
