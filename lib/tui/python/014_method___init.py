    def __init__(self, stdscr, base_dir):
        self.stdscr = stdscr
        self.base_dir = base_dir
        self.help_text = find_help_text(base_dir)
        self.help_rendered_text = os.environ.get("CHROOT_HELP_RENDERED_TEXT", "").strip()
        self.help_raw_text = os.environ.get("CHROOT_HELP_RAW_TEXT", "").strip()
        self.help_raw_rendered_text = os.environ.get("CHROOT_HELP_RAW_RENDERED_TEXT", "").strip()
        self.sections = parse_help(self.help_text)
        self.section_by_name = {section["title"]: section for section in self.sections}
        self.specs = self.build_specs()
        self.commands = self.build_command_order()
        if not self.commands:
            self.commands = ["help"]

        self.runner = os.environ.get("CHROOT_TUI_RUNNER", "chroot").strip() or "chroot"

        self.state = "menu"
        self.menu_index = 0
        self.menu_scroll = 0

        self.active_command = self.commands[0]
        self.form_values = {}
        self.form_index = 0
        self.form_panel_focus = "left"
        self.preview_scroll = 0

        self.result_command = ""
        self.result_exit_code = 0
        self.result_duration = 0.0
        self.result_lines = ["No command executed yet."]
        self.result_scroll = 0
        self.result_hscroll = 0
        self.result_back_state = "menu"
        self.result_rerun_cmd = None
        self.result_rerun_stdin = ""
        self.result_rerun_interactive = False
        self.last_capture_used_live_output = False

        self.distros_catalog = []
        self.distros_runtime_root = ""
        self.runtime_root_hint = ""
        self.distros_stage = "distros"
        self.distros_index = 0
        self.distros_version_index = 0
        self.restore_backups = {}

        self.settings_rows = []
        self.settings_index = 0
        self.settings_pending = {}
        self.service_payload_data = None
        self.service_builtin_payload_data = None
        self.desktop_profile_payload_data = None
        self.tor_status_payload_data = None
        self.tor_apps_payload_data = None
        self.tor_exit_payload_data = None
        self.tor_country_payload_data = None
        self.tor_apps_tunneling_distro = ""
        self.tor_apps_tunneling_rows = []
        self.tor_apps_tunneling_scope = "all"
        self.tor_apps_tunneling_query = ""
        self.tor_apps_tunneling_index = 0
        self.tor_apps_tunneling_scroll = 0
        self.tor_apps_tunneling_dirty = False
        self.tor_apps_tunneling_back_state = "form"
        self.tor_apps_tunneling_generated_at = ""
        self.tor_exit_mode_distro = ""
        self.tor_exit_mode_rows = []
        self.tor_exit_mode_filter = "all"
        self.tor_exit_mode_query = ""
        self.tor_exit_mode_index = 0
        self.tor_exit_mode_scroll = 0
        self.tor_exit_mode_dirty = False
        self.tor_exit_mode_back_state = "form"
        self.tor_exit_mode_generated_at = ""
        self.tor_exit_mode_saved_strict = False
        self.tor_exit_mode_pending_strict = False

        self.status_message = ""
        self.status_kind = "info"
        self.status_time = 0.0

        self.set_active_command(self.active_command)
