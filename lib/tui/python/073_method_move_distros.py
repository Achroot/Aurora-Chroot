    def move_distros(self, delta):
        if self.distros_stage == "distros":
            if not self.distros_catalog:
                return
            self.distros_index = (self.distros_index + delta) % len(self.distros_catalog)
            self.distros_version_index = 0
            return
        distro = self.current_distro()
        versions = distro.get("versions", []) if distro else []
        if not versions:
            return
        self.distros_version_index = (self.distros_version_index + delta) % len(versions)

