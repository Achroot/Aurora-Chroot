    def backup_default_extension(self):
        return "tar.zst" if shutil.which("zstd") else "tar.xz"

