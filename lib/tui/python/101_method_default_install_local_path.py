    def default_install_local_path(self):
        cache_dir = str(os.environ.get("CHROOT_TUI_CACHE_DIR", "") or "").strip()
        if cache_dir:
            return os.path.normpath(cache_dir)

        runtime_root = str(os.environ.get("CHROOT_TUI_RUNTIME_ROOT", "") or "").strip()
        if not runtime_root:
            runtime_root = str(self.runtime_root_hint or self.distros_runtime_root or "").strip()
        if not runtime_root:
            return ""

        runtime_root = os.path.normpath(runtime_root)
        return os.path.join(runtime_root, "cache")
