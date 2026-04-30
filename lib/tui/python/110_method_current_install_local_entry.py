    def current_install_local_entry(self):
        if not self.install_local_entries:
            return None
        if self.install_local_index <= 0:
            return None
        idx = max(0, min(self.install_local_index - 1, len(self.install_local_entries) - 1))
        return self.install_local_entries[idx]
