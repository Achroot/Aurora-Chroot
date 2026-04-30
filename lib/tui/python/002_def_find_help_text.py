def find_help_text(base_dir):
    env_help = os.environ.get("CHROOT_HELP_TEXT", "").strip()
    if env_help:
        return env_help
    return "# Chroot Command Help\n\nHelp file not found."

