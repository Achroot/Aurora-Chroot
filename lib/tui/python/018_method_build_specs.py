    def build_specs(self):
        return {
            "help": {
                "fields": [
                    {
                        "id": "view",
                        "label": "View",
                        "type": "choice",
                        "choices": [
                            ("guide", "Guide + docs"),
                            ("raw", "Raw command list"),
                        ],
                        "default": "guide",
                    }
                ],
                "about": "Open the same full help text shown by `chroot help`. Switch View to Raw command list for the compact command-only reference.",
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
                            ("apps-tunneling", "Apps Tunneling"),
                            ("exit-tunneling", "Exit Tunneling"),
                            ("remove", "Remove Tor data (keep packages)"),
                        ],
                        "default": "status",
                    },
                    {
                        "id": "run_mode",
                        "label": "Run mode",
                        "type": "choice",
                        "choices": [
                            ("default", "Default run (ignore saved Apps Tunneling/exit config)"),
                            ("configured", "Configured run (use saved Apps Tunneling + exit config)"),
                            ("configured-apps", "Configured run (Apps Tunneling only; ignore saved exit config)"),
                            ("configured-exit", "Configured run (exit only; ignore saved Apps Tunneling config)"),
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
