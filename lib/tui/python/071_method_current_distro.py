    def current_distro(self):
        if not self.distros_catalog:
            return None
        self.distros_index = max(0, min(self.distros_index, len(self.distros_catalog) - 1))
        return self.distros_catalog[self.distros_index]

