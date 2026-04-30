    def enter_install_local(self):
        self.state = "install_local"
        if not self.install_local_runtime_root() and not self.default_install_local_path():
            self.load_status_payload(show_error=False)
        default_path = self.default_install_local_path()
        current_path = str(self.form_values.get("file", "") or "").strip()
        self.install_local_path = current_path or default_path
        self.form_values["file"] = self.install_local_path
        self.install_local_entries = []
        self.install_local_index = 0
        self.load_install_local_entries(show_loading=False, select_first_entry=True)
