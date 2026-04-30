    def install_local_runtime_root(self):
        runtime_root = str(os.environ.get("CHROOT_TUI_RUNTIME_ROOT", "") or "").strip()
        if runtime_root:
            return os.path.normpath(runtime_root)
        runtime_root = str(self.runtime_root_hint or self.distros_runtime_root or "").strip()
        if runtime_root:
            return os.path.normpath(runtime_root)
        cache_dir = str(os.environ.get("CHROOT_TUI_CACHE_DIR", "") or "").strip()
        if cache_dir:
            return os.path.dirname(os.path.normpath(cache_dir))
        return ""
