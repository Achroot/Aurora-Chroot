    def __init__(self, stdscr, base_dir):
        self.stdscr = stdscr
        self.base_dir = base_dir
        self.help_text = find_help_text(base_dir)
        self.help_rendered_text = os.environ.get("CHROOT_HELP_RENDERED_TEXT", "").strip()
        self.help_raw_text = os.environ.get("CHROOT_HELP_RAW_TEXT", "").strip()
        self.help_raw_rendered_text = os.environ.get("CHROOT_HELP_RAW_RENDERED_TEXT", "").strip()
        self.sections = parse_help(self.help_text)
        self.section_by_name = {section["title"]: section for section in self.sections}
        self.registry_tui = {}
        self.registry_commands = []
        self.registry_command_by_id = {}
        self.registry_specs = {}
        registry_tui_text = os.environ.get("CHROOT_TUI_COMMANDS_JSON", "").strip()
        if registry_tui_text:
            try:
                parsed_registry_tui = json.loads(registry_tui_text)
            except Exception:
                parsed_registry_tui = {}
            if isinstance(parsed_registry_tui, dict):
                self.registry_tui = parsed_registry_tui
                commands = parsed_registry_tui.get("commands", [])
                if isinstance(commands, list):
                    self.registry_commands = [row for row in commands if isinstance(row, dict)]
                    self.registry_command_by_id = {
                        str(row.get("id", "")).strip(): row
                        for row in self.registry_commands
                        if str(row.get("id", "")).strip()
                    }
        registry_specs_text = os.environ.get("CHROOT_TUI_SPECS_JSON", "").strip()
        if registry_specs_text:
            try:
                parsed_registry_specs = json.loads(registry_specs_text)
            except Exception:
                parsed_registry_specs = {}
            if isinstance(parsed_registry_specs, dict):
                specs = parsed_registry_specs.get("specs", {})
                if isinstance(specs, dict):
                    for command, spec in specs.items():
                        if not isinstance(spec, dict):
                            continue
                        normalized_spec = dict(spec)
                        normalized_fields = []
                        for field in spec.get("fields", []):
                            if not isinstance(field, dict):
                                continue
                            normalized_field = dict(field)
                            choices = normalized_field.get("choices", [])
                            if isinstance(choices, list):
                                normalized_choices = []
                                for choice in choices:
                                    if isinstance(choice, list) and len(choice) == 2:
                                        normalized_choices.append((choice[0], choice[1]))
                                    else:
                                        normalized_choices.append(choice)
                                normalized_field["choices"] = normalized_choices
                            normalized_fields.append(normalized_field)
                        normalized_spec["fields"] = normalized_fields
                        self.registry_specs[str(command).strip()] = normalized_spec
        self.specs = self.build_specs()
        self.commands = self.build_command_order()
        if not self.commands:
            self.commands = ["help"]

        self.runner = os.environ.get("CHROOT_TUI_RUNNER", "chroot").strip() or "chroot"

        self.state = "menu"
        self.menu_panel_focus = "left"
        self.menu_index = 0
        self.menu_scroll = 0
        self.menu_left_hscroll = 0
        self.menu_detail_scroll = 0
        self.menu_detail_hscroll = 0

        self.active_command = self.commands[0]
        self.form_values = {}
        self.form_index = 0
        self.form_panel_focus = "left"
        self.form_hscroll = 0
        self.preview_scroll = 0
        self.preview_hscroll = 0

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
        self.result_info_mode = False
        self.last_capture_used_live_output = False

        env_runtime_root = str(os.environ.get("CHROOT_TUI_RUNTIME_ROOT", "") or "").strip()
        if env_runtime_root:
            env_runtime_root = os.path.normpath(env_runtime_root)

        self.distros_catalog = []
        self.distros_runtime_root = env_runtime_root
        self.runtime_root_hint = env_runtime_root
        self.distros_stage = "distros"
        self.distros_panel_focus = "left"
        self.distros_index = 0
        self.distros_version_index = 0
        self.distros_left_hscroll = 0
        self.distros_detail_scroll = 0
        self.distros_detail_hscroll = 0
        self.install_local_path = ""
        self.install_local_entries = []
        self.install_local_index = 0
        self.install_local_path_kind = ""
        self.install_local_panel_focus = "left"
        self.install_local_left_hscroll = 0
        self.install_local_detail_scroll = 0
        self.install_local_detail_hscroll = 0
        self.restore_backups = {}

        self.settings_rows = []
        self.settings_index = 0
        self.settings_pending = {}
        self.settings_panel_focus = "left"
        self.settings_left_hscroll = 0
        self.settings_detail_scroll = 0
        self.settings_detail_hscroll = 0
        self.busybox_action_index = 0
        self.busybox_scroll = 0
        self.busybox_hscroll = 0
        self.busybox_last_summary = ""
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
        self.tor_apps_tunneling_hscroll = 0
        self.tor_apps_tunneling_dirty = False
        self.tor_apps_tunneling_back_state = "form"
        self.tor_apps_tunneling_generated_at = ""
        self.tor_exit_mode_distro = ""
        self.tor_exit_mode_rows = []
        self.tor_exit_mode_filter = "all"
        self.tor_exit_mode_query = ""
        self.tor_exit_mode_index = 0
        self.tor_exit_mode_scroll = 0
        self.tor_exit_mode_hscroll = 0
        self.tor_exit_mode_dirty = False
        self.tor_exit_mode_back_state = "form"
        self.tor_exit_mode_generated_at = ""
        self.tor_exit_mode_focus_area = "list"
        self.tor_exit_mode_header_focus = "all"
        self.tor_exit_mode_saved_performance = False
        self.tor_exit_mode_pending_performance = False
        self.tor_exit_mode_saved_strict = False
        self.tor_exit_mode_pending_strict = False
        self.info_payload_data = {}
        self.info_sections = {}
        self.info_section_order = []
        self.info_section_index = 0
        self.info_panel_focus = "left"
        self.info_scroll = 0
        self.info_list_hscroll = 0
        self.info_hscroll = 0
        self.info_back_state = "menu"
        self.info_loaded_at = 0.0

        self.status_message = ""
        self.status_kind = "info"
        self.status_time = 0.0

        self.set_active_command(self.active_command)
