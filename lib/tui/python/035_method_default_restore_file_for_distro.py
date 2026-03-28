    def default_restore_file_for_distro(self, distro):
        key = str(distro or "").strip()
        if not key:
            return ""
        files = self.restore_backups.get(key, [])
        if not files:
            return ""
        return files[-1]

