    def move_install_local(self, delta):
        total_rows = 1 + len(self.install_local_entries)
        if total_rows <= 0:
            self.install_local_index = 0
            return
        self.install_local_index = (self.install_local_index + delta) % total_rows
        self.reset_panel_scroll("install_local_detail_scroll", "install_local_detail_hscroll")
