def find_help_text(base_dir):
    env_md = os.environ.get("CHROOT_HELP_MD", "").strip()
    if env_md:
        return env_md
    candidates = [
        os.path.join(base_dir, "HELP.md"),
        os.path.join(base_dir, "..", "HELP.md"),
    ]
    for path in candidates:
        if os.path.exists(path):
            with open(path, "r", encoding="utf-8") as handle:
                return handle.read()
    env_help = os.environ.get("CHROOT_HELP_TEXT", "").strip()
    if env_help:
        return env_help
    return "# Chroot Command Help\n\nHelp file not found."


