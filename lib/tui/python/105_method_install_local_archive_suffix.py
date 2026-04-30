    def install_local_archive_suffix(self, name):
        lowered = str(name or "").strip().lower()
        if not lowered:
            return ""
        if lowered.endswith(".tar"):
            return ".tar"
        match = re.search(r"(\.tar\.[a-z0-9]+)$", lowered)
        if match:
            return match.group(1)
        for suffix in (".tgz", ".tbz", ".tbz2", ".txz", ".tzst", ".tlz", ".tlzma"):
            if lowered.endswith(suffix):
                return suffix
        return ""
