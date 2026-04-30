    def build_specs(self):
        specs = dict(getattr(self, "registry_specs", {}))
        specs.update({
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
                ],
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
        })
        return specs
