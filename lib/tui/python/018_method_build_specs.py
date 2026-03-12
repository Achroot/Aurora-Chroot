    def build_specs(self):
        return {
            "help": {
                "fields": [],
                "about": "Show embedded HELP.md content.",
            },
            "init": {
                "fields": [],
                "about": "Show first-run setup guidance and dependency status.",
            },
            "doctor": {
                "fields": [
                    {"id": "json", "label": "JSON output", "type": "bool", "default": False},
                    {
                        "id": "repair",
                        "label": "Repair stale lockdirs",
                        "type": "bool",
                        "default": False,
                    },
                ],
            },
            "status": {
                "fields": [
                    {
                        "id": "scope",
                        "label": "Scope",
                        "type": "choice",
                        "choices": [("all", "All distros"), ("distro", "Single distro")],
                        "default": "all",
                    },
                    {
                        "id": "distro",
                        "label": "Distro id",
                        "type": "text",
                        "default": "",
                        "show_if": {"id": "scope", "equals": "distro"},
                    },
                    {"id": "json", "label": "JSON output", "type": "bool", "default": False},
                    {
                        "id": "live",
                        "label": "Include live fields (--live)",
                        "type": "bool",
                        "default": False,
                        "show_if": {"id": "json", "equals": True},
                    },
                ]
            },
            "tor": {
                "fields": [
                    {
                        "id": "distro",
                        "label": "Installed distro",
                        "type": "choice",
                        "choices": [("", "<loading installed distros>")],
                        "default": "",
                    },
                    {
                        "id": "action",
                        "label": "Action",
                        "type": "choice",
                        "choices": [
                            ("status", "Show Tor status"),
                            ("on", "Enable Tor mode"),
                            ("off", "Disable Tor mode"),
                            ("restart", "Restart Tor mode"),
                            ("freeze", "Freeze current exit"),
                            ("logs", "Show Tor logs"),
                            ("newnym", "Request new identity"),
                            ("doctor", "Run Tor doctor"),
                            ("apps", "Manage app bypass list"),
                            ("exit", "Manage exit countries"),
                            ("remove", "Remove Tor data (keep packages)"),
                        ],
                        "default": "status",
                    },
                    {
                        "id": "run_mode",
                        "label": "Run mode",
                        "type": "choice",
                        "choices": [
                            ("default", "Default run (ignore saved app/exit config)"),
                            ("configured", "Configured run (use saved app + exit config)"),
                            ("configured-apps", "Configured run (apps only; ignore saved exit config)"),
                            ("configured-exit", "Configured run (exit only; ignore saved app config)"),
                        ],
                        "default": "default",
                        "show_if": {"id": "action", "equals": ["on", "restart"]},
                    },
                    {
                        "id": "no_lan_bypass",
                        "label": "Block local/LAN direct access",
                        "type": "bool",
                        "default": False,
                        "show_if": {"id": "action", "equals": ["on", "restart"]},
                    },
                    {
                        "id": "json",
                        "label": "JSON output",
                        "type": "bool",
                        "default": False,
                        "show_if": {"id": "action", "equals": ["status", "doctor"]},
                    },
                    {
                        "id": "tail",
                        "label": "Tail lines (logs action)",
                        "type": "text",
                        "default": "120",
                        "show_if": {"id": "action", "equals": "logs"},
                    },
                    {
                        "id": "apps_action",
                        "label": "Apps action",
                        "type": "choice",
                        "choices": [
                            ("browse", "Browse/search apps"),
                            ("bypass-add", "Add app to bypass"),
                            ("bypass-remove", "Remove app from bypass"),
                            ("bypass-show", "Show bypassed apps"),
                        ],
                        "default": "browse",
                        "show_if": {"id": "action", "equals": "apps"},
                    },
                    {
                        "id": "apps_scope",
                        "label": "App scope",
                        "type": "choice",
                        "choices": [
                            ("all", "All apps"),
                            ("user", "User apps only"),
                            ("system", "System apps only"),
                        ],
                        "default": "all",
                        "show_if": {"id": "action", "equals": "apps"},
                    },
                    {
                        "id": "apps_query",
                        "label": "App query",
                        "type": "text",
                        "default": "",
                        "show_if": {
                            "all": [
                                {"id": "action", "equals": "apps"},
                                {"id": "apps_action", "equals": ["browse", "bypass-add", "bypass-remove"]},
                            ]
                        },
                    },
                    {
                        "id": "app_pick",
                        "label": "Matching app",
                        "type": "choice",
                        "choices": [("", "<loading apps>")],
                        "default": "",
                        "show_if": {
                            "all": [
                                {"id": "action", "equals": "apps"},
                                {"id": "apps_action", "equals": ["bypass-add", "bypass-remove"]},
                            ]
                        },
                    },
                    {
                        "id": "exit_action",
                        "label": "Exit action",
                        "type": "choice",
                        "choices": [
                            ("show", "Show exit config"),
                            ("list", "Browse/search countries"),
                            ("add", "Add preferred exit country"),
                            ("remove", "Remove preferred exit country"),
                            ("clear", "Clear saved exit config"),
                            ("strict-on", "Set strict mode on"),
                            ("strict-off", "Set strict mode off"),
                        ],
                        "default": "show",
                        "show_if": {"id": "action", "equals": "exit"},
                    },
                    {
                        "id": "country_query",
                        "label": "Country query",
                        "type": "text",
                        "default": "",
                        "show_if": {
                            "all": [
                                {"id": "action", "equals": "exit"},
                                {"id": "exit_action", "equals": ["list", "add", "remove"]},
                            ]
                        },
                    },
                    {
                        "id": "country_pick",
                        "label": "Matching country",
                        "type": "choice",
                        "choices": [("", "<loading countries>")],
                        "default": "",
                        "show_if": {
                            "all": [
                                {"id": "action", "equals": "exit"},
                                {"id": "exit_action", "equals": ["add", "remove"]},
                            ]
                        },
                    },
                ],
            },
            "logs": {
                "fields": [
                    {
                        "id": "tail",
                        "label": "Tail lines (blank keeps default)",
                        "type": "text",
                        "default": "120",
                    }
                ]
            },
            "install-local": {
                "fields": [
                    {"id": "distro", "label": "Distro id", "type": "text", "default": ""},
                    {"id": "file", "label": "Tarball path", "type": "text", "default": ""},
                    {
                        "id": "sha256",
                        "label": "SHA256 (optional)",
                        "type": "text",
                        "default": "",
                    },
                    {
                        "id": "stdin_reply",
                        "label": "Prompt reply (optional)",
                        "type": "text",
                        "default": "",
                    },
                ]
            },
            "login": {
                "fields": [
                    {
                        "id": "distro",
                        "label": "Installed distro",
                        "type": "choice",
                        "choices": [("", "<loading installed distros>")],
                        "default": "",
                    }
                ]
            },
            "service": {
                "fields": [
                    {
                        "id": "distro",
                        "label": "Installed distro",
                        "type": "choice",
                        "choices": [("", "<loading installed distros>")],
                        "default": "",
                    },
                    {
                        "id": "action",
                        "label": "Action",
                        "type": "choice",
                        "choices": [
                            ("list", "List services"),
                            ("start", "Start service"),
                            ("stop", "Stop service"),
                            ("restart", "Restart service"),
                            ("add", "Add service definition"),
                            ("install", "Install built-in service"),
                            ("remove", "Remove service definition")
                        ],
                        "default": "list",
                    },
                    {
                        "id": "service_pick",
                        "label": "Service",
                        "type": "choice",
                        "choices": [("", "<loading services>")],
                        "default": "",
                        "show_if": {"id": "action", "equals": ["start", "stop", "restart", "remove"]},
                    },
                    {
                        "id": "service_name",
                        "label": "Service name (for add)",
                        "type": "text",
                        "default": "",
                        "show_if": {"id": "action", "equals": "add"},
                    },
                    {
                        "id": "service_builtin",
                        "label": "Built-in service",
                        "type": "choice",
                        "choices": [("", "<loading built-ins>")],
                        "default": "",
                        "show_if": {"id": "action", "equals": "install"},
                    },
                    {
                        "id": "desktop_profile",
                        "label": "Desktop profile",
                        "type": "choice",
                        "choices": [("", "<loading desktop profiles>")],
                        "default": "",
                        "show_if": {
                            "all": [
                                {"id": "action", "equals": "install"},
                                {"id": "service_builtin", "equals": "desktop"},
                            ]
                        },
                    },
                    {
                        "id": "desktop_reinstall",
                        "label": "Allow profile switch / reinstall",
                        "type": "bool",
                        "default": False,
                        "show_if": {
                            "all": [
                                {"id": "action", "equals": "install"},
                                {"id": "service_builtin", "equals": "desktop"},
                            ]
                        },
                    },
                    {
                        "id": "service_cmd",
                        "label": "Command (for add action)",
                        "type": "text",
                        "default": "",
                        "show_if": {"id": "action", "equals": "add"}
                    }
                ]
            },
            "sessions": {
                "fields": [
                    {
                        "id": "distro",
                        "label": "Installed distro",
                        "type": "choice",
                        "choices": [("", "<loading installed distros>")],
                        "default": "",
                    },
                    {
                        "id": "action",
                        "label": "Action",
                        "type": "choice",
                        "choices": [
                            ("list", "List sessions"),
                            ("kill", "Kill one session"),
                            ("kill-all", "Kill all sessions"),
                        ],
                        "default": "list",
                    },
                    {
                        "id": "json",
                        "label": "JSON output (list only)",
                        "type": "bool",
                        "default": False,
                        "show_if": {"id": "action", "equals": "list"},
                    },
                    {
                        "id": "session_pick",
                        "label": "Session (select tracked)",
                        "type": "choice",
                        "choices": [("", "<loading sessions>")],
                        "default": "",
                        "show_if": {"id": "action", "equals": "kill"},
                    },
                    {
                        "id": "grace",
                        "label": "Grace seconds (kill-all)",
                        "type": "text",
                        "default": "3",
                        "show_if": {"id": "action", "equals": "kill-all"},
                    },
                ],
            },
            "exec": {
                "fields": [
                    {
                        "id": "distro",
                        "label": "Installed distro",
                        "type": "choice",
                        "choices": [("", "<loading installed distros>")],
                        "default": "",
                    },
                    {
                        "id": "command",
                        "label": "Command to run",
                        "type": "text",
                        "default": "echo hello",
                    },
                    {
                        "id": "stdin_reply",
                        "label": "STDIN text (optional)",
                        "type": "text",
                        "default": "",
                    },
                ]
            },
            "mount": {
                "fields": [
                    {
                        "id": "distro",
                        "label": "Installed distro",
                        "type": "choice",
                        "choices": [("", "<loading installed distros>")],
                        "default": "",
                    }
                ],
            },
            "unmount": {
                "fields": [
                    {
                        "id": "distro",
                        "label": "Installed distro",
                        "type": "choice",
                        "choices": [("", "<loading installed distros>")],
                        "default": "",
                    },
                    {
                        "id": "kill_sessions",
                        "label": "Kill sessions before unmount",
                        "type": "bool",
                        "default": False,
                    },
                ],
            },
            "confirm-unmount": {
                "fields": [
                    {
                        "id": "distro",
                        "label": "Installed distro",
                        "type": "choice",
                        "choices": [("", "<loading installed distros>")],
                        "default": "",
                    },
                    {"id": "json", "label": "JSON output", "type": "bool", "default": False},
                ],
            },
            "backup": {
                "fields": [
                    {
                        "id": "distro",
                        "label": "Installed distro",
                        "type": "choice",
                        "choices": [("", "<loading installed distros>")],
                        "default": "",
                    },
                    {
                        "id": "mode",
                        "label": "Backup mode",
                        "type": "choice",
                        "choices": [("full", "Full"), ("rootfs", "Rootfs"), ("state", "State")],
                        "default": "full",
                    },
                    {"id": "out", "label": "Output directory (optional)", "type": "text", "default": ""},
                ]
            },
            "restore": {
                "fields": [
                    {
                        "id": "distro",
                        "label": "Backup distro",
                        "type": "choice",
                        "choices": [("", "<loading backup distros>")],
                        "default": "",
                    },
                    {
                        "id": "file",
                        "label": "Backup archive path (optional)",
                        "type": "text",
                        "default": "",
                    },
                ]
            },
            "remove": {
                "fields": [
                    {
                        "id": "distro",
                        "label": "Installed distro",
                        "type": "choice",
                        "choices": [("", "<loading installed distros>")],
                        "default": "",
                    },
                    {"id": "full", "label": "Delete related cache files", "type": "bool", "default": False},
                ]
            },
            "nuke": {
                "fields": [],
                "about": "Danger: remove all Aurora runtime data (distros/backups/cache/state).",
            },
            "clear-cache": {
                "about": "Remove cached downloads or, with all, disposable runtime files like tmp leftovers, staging dirs, and stale runtime logs.",
                "fields": [
                    {
                        "id": "strategy",
                        "label": "Cleanup mode",
                        "type": "choice",
                        "choices": [
                            ("default", "Older than 14 days"),
                            ("older", "Custom age"),
                            ("all", "Delete all disposable files"),
                        ],
                        "default": "default",
                    },
                    {
                        "id": "days",
                        "label": "Days threshold",
                        "type": "text",
                        "default": "14",
                        "show_if": {"id": "strategy", "equals": "older"},
                    }
                ]
            },
        }
