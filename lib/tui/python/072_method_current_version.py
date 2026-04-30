    def current_version(self):
        distro = self.current_distro()
        if not distro:
            return None
        versions = distro.get("versions", [])
        if not versions:
            return None
        self.distros_version_index = max(0, min(self.distros_version_index, len(versions) - 1))
        return versions[self.distros_version_index]

