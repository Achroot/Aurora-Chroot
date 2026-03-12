    def service_row_for_name(self, name):
        wanted = str(name or "").strip().lower()
        if not wanted:
            return None
        for row in self.service_payload():
            if not isinstance(row, dict):
                continue
            if str(row.get("name", "")).strip().lower() == wanted:
                return row
        return None

    def service_builtin_row_for_id(self, builtin_id):
        wanted = str(builtin_id or "").strip().lower()
        if not wanted:
            return None
        for row in self.service_builtin_payload():
            if not isinstance(row, dict):
                continue
            if str(row.get("id", "")).strip().lower() == wanted:
                return row
        return None

    def service_status_label(self, row):
        if not isinstance(row, dict):
            return "unknown"
        return str(row.get("state", "")).strip().lower() or "unknown"

    def desktop_profile_status_label(self, row):
        if not isinstance(row, dict):
            return "unknown"
        if row.get("recommended"):
            return "recommended"
        if row.get("blocked"):
            return "blocked"
        if row.get("can_install"):
            return "allowed"
        if not row.get("supported", True):
            return "unsupported"
        return "unavailable"

    def desktop_profile_summary_lines(self, wrap_width):
        payload = self.desktop_profile_payload()
        if not isinstance(payload, dict):
            return []

        memory = payload.get("memory", {})
        requirements = payload.get("requirements", {})
        profiles = payload.get("profiles", [])
        status = payload.get("status", {})
        selected_profile = str(self.form_values.get("desktop_profile", "")).strip()
        installed_profile = str(status.get("installed_profile_id", "")).strip()

        recommended_row = None
        selected_row = None
        for row in profiles:
            if not isinstance(row, dict):
                continue
            if row.get("recommended") and recommended_row is None:
                recommended_row = row
            if str(row.get("id", "")).strip() == selected_profile:
                selected_row = row

        lines = [
            f"Distro: {payload.get('distro', '') or '<none>'}",
            f"Detected family: {payload.get('distro_family', '') or 'unknown'}",
            f"Desktop installed: {'yes' if status.get('desktop_installed') else 'no'}",
            f"Service definition: {'present' if status.get('service_defined') else 'missing'} | running: {'yes' if status.get('service_running') else 'no'}",
            f"Host RAM: total={memory.get('total_mb', '?')}MB available={memory.get('available_mb', '?')}MB",
            (
                "Requirements: "
                f"x11={'ok' if requirements.get('x11_requirement_met') else 'missing'} | "
                f"termux-x11 binary={'found' if requirements.get('termux_x11_binary_found') else 'missing'} | "
                f"x11 socket dir={'found' if requirements.get('termux_x11_socket_dir_found') else 'missing'}"
            ),
        ]

        if installed_profile:
            lines.append(f"Current installed profile: {installed_profile}")
        if status.get("incomplete"):
            lines.append("Desktop state: incomplete. Repair or reinstall is still required before start will work.")
        last_error = str(status.get("last_error", "")).strip()
        if last_error:
            lines.append(f"Last error: {last_error}")

        for row in profiles:
            if not isinstance(row, dict):
                continue
            name = str(row.get("name", "")).strip() or str(row.get("id", "")).strip()
            status_label = self.desktop_profile_status_label(row)
            lines.append(
                f"{name}: {status_label}. Min {row.get('minimum_total_mb', '?')}/{row.get('minimum_available_mb', '?')}MB total/free, "
                f"recommended {row.get('recommended_total_mb', '?')}/{row.get('recommended_available_mb', '?')}MB."
            )

        if not selected_profile:
            lines.append("Select LXQt or XFCE to see install behavior for the chosen profile.")
        elif isinstance(selected_row, dict):
            selected_name = str(selected_row.get("name", "")).strip() or selected_profile
            lines.append(f"Selected profile: {selected_name} [{self.desktop_profile_status_label(selected_row)}]")
            reason = str(selected_row.get("reason", "")).strip()
            if reason:
                lines.append(f"Why: {reason}")

            if installed_profile and selected_profile != installed_profile:
                if self.form_values.get("desktop_reinstall"):
                    lines.append("Reinstall switch: ON. Install will replace the current managed desktop profile.")
                else:
                    lines.append("Selected profile differs from the current install. Enable reinstall to switch profiles.")
            elif installed_profile and selected_profile == installed_profile:
                if self.form_values.get("desktop_reinstall"):
                    lines.append("Reinstall switch: ON. Install will refresh the current managed desktop profile.")
                else:
                    lines.append("Selected profile matches the current install. Re-running install refreshes managed desktop assets.")
            elif self.form_values.get("desktop_reinstall"):
                lines.append("Reinstall switch: ON.")

        if isinstance(recommended_row, dict):
            lines.append(
                f"Recommendation: {recommended_row.get('name', recommended_row.get('id', 'desktop'))} is the best fit on current device RAM."
            )
        else:
            lines.append("Recommendation: no profile is currently installable until the missing requirements are fixed.")

        return lines

    def service_inventory_lines(self):
        rows = self.service_payload()
        if not rows:
            return ["Defined services: none in the selected distro."]

        lines = [f"Defined services: {len(rows)}"]
        for row in rows[:4]:
            name = str(row.get("name", "")).strip() or "<unknown>"
            state = self.service_status_label(row)
            pid = str(row.get("pid", "")).strip() or "-"
            lines.append(f"{name}: {state} (pid {pid})")
        if len(rows) > 4:
            lines.append(f"Additional services not shown: {len(rows) - 4}")
        return lines

    def service_builtin_inventory_lines(self):
        rows = self.service_builtin_payload()
        if not rows:
            return ["Available built-ins: none returned for the selected distro."]

        lines = [f"Available built-ins: {len(rows)}"]
        for row in rows[:4]:
            builtin_id = str(row.get("id", "")).strip() or "<unknown>"
            description = str(row.get("description", "")).strip()
            qualifiers = []
            if row.get("install_only"):
                qualifiers.append("install-only")
            else:
                qualifiers.append("managed service")
            if row.get("requires_profile"):
                qualifiers.append("profile required")
            qualifier_text = f" [{' | '.join(qualifiers)}]" if qualifiers else ""
            lines.append(f"{builtin_id}{qualifier_text}: {description or 'No description available.'}")
        if len(rows) > 4:
            lines.append(f"Additional built-ins not shown: {len(rows) - 4}")
        return lines

    def service_action_summary_lines(self, wrap_width):
        distro = self.read_text("distro")
        action = str(self.form_values.get("action", "")).strip().lower() or "list"
        selected_service = self.read_text("service_pick")
        selected_builtin = self.read_text("service_builtin")
        lines = [f"Distro: {distro or '<select distro>'}", f"Action: {action}"]

        if not distro:
            lines.append("Select an installed distro first. Service choices and built-ins are loaded per distro.")
            return lines

        if action == "list":
            lines.append("Shows all defined services for the selected distro with live state, PID, and command.")
            lines.append("This action is read-only. It does not start, stop, or edit anything.")
            lines.extend(self.service_inventory_lines())
            return lines

        if action == "add":
            service_name = self.read_text("service_name")
            service_cmd = self.read_text("service_cmd")
            lines.append("Creates a new service definition only. It does not start the service.")
            lines.append("The command must keep the daemon in the foreground so Aurora can track it.")
            lines.append("Service names must match ^[A-Za-z0-9][A-Za-z0-9._-]*$.")
            lines.append(f"Typed name: {service_name or '<empty>'}")
            lines.append(f"Typed command: {service_cmd or '<empty>'}")
            return lines

        if action == "install":
            lines.append("Installs Aurora-managed built-in wrapper files for the selected distro.")
            if not selected_builtin:
                lines.append("Select a built-in service to see what install will add and what it does later at runtime.")
                lines.extend(self.service_builtin_inventory_lines())
                return lines

            row = self.service_builtin_row_for_id(selected_builtin) or {}
            service_name = str(row.get("service_name", "")).strip() or selected_builtin
            command = str(row.get("command", "")).strip() or "<none>"
            description = str(row.get("description", "")).strip() or "No description available."
            lines.append(f"Built-in: {selected_builtin} -> service {service_name}")
            lines.append(f"Install type: {'install-only' if row.get('install_only') else 'service wrapper + definition'}")
            lines.append(f"Command: {command}")
            lines.append(f"Summary: {description}")

            if selected_builtin == "desktop":
                desktop_lines = self.desktop_profile_summary_lines(wrap_width)
                if desktop_lines:
                    lines.extend(desktop_lines)
                else:
                    lines.append("Desktop profile metadata could not be loaded. The selected distro may be unsupported or the probe failed.")
            elif selected_builtin == "zsh":
                lines.append("Supported only on Ubuntu/Arch family distros.")
                lines.append("Installs Zsh tooling and configures root shell startup. No background service is created.")
                lines.append("Safe to rerun. Existing managed shell config blocks are refreshed rather than duplicated.")
            elif selected_builtin == "sshd":
                lines.append("Install adds the Aurora SSH wrapper and service definition. It does not start SSH immediately.")
                lines.append("After install, use service start sshd and Aurora will print SSH connect commands.")
                lines.append("Runtime dependency checks happen when the service starts inside the distro.")
            elif selected_builtin == "pcbridge":
                lines.append("Install adds the Aurora pcbridge wrapper and service definition. It does not start pairing immediately.")
                lines.append("Start or restart later to choose pairing mode [f]/[c] or normal mode [s].")
                lines.append("Normal mode requires an existing paired PC key. Pairing mode prints one-time bootstrap or cleanup commands.")

            return lines

        if action in ("start", "stop", "restart", "remove"):
            verb_lines = {
                "start": "Starts the selected service in the background, tracks its PID, and auto-mounts the distro if needed.",
                "stop": "Stops the selected service with SIGTERM, then SIGKILL if it refuses to exit.",
                "restart": "Stops and starts the selected service again.",
                "remove": "Stops the selected service if needed, then removes its Aurora service definition.",
            }
            lines.append(verb_lines.get(action, "Operates on the selected service."))

            if not selected_service:
                lines.append("Select a defined service to see action-specific behavior.")
                lines.extend(self.service_inventory_lines())
                return lines

            row = self.service_row_for_name(selected_service) or {}
            state = self.service_status_label(row)
            pid = str(row.get("pid", "")).strip() or "-"
            command = str(row.get("command", "")).strip() or "<unknown>"
            lines.append(f"Target service: {selected_service}")
            lines.append(f"Current state: {state} | pid: {pid}")
            lines.append(f"Command: {command}")

            if selected_service == "desktop":
                if action == "start":
                    lines.append("Starts the managed desktop session. Desktop must already be installed for this distro.")
                    lines.append("Requires settings x11=true. After start, open Termux:X11 manually to view the GUI.")
                elif action == "stop":
                    lines.append("Uses the desktop-specific stop path so Aurora also updates desktop runtime state.")
                elif action == "restart":
                    lines.append("Runs the desktop-specific stop/start path and refreshes managed desktop assets before launch.")
                elif action == "remove":
                    lines.append("Removes Aurora-managed desktop service/config files only. Desktop packages inside the distro remain installed.")
            elif selected_service == "pcbridge":
                if action == "start":
                    lines.append("Start prompts for mode selection: first-run setup [f], cleanup [c], or normal [s].")
                    lines.append("Normal mode needs a previously paired PC key. Pairing modes print bootstrap or cleanup commands after launch.")
                elif action == "restart":
                    lines.append("Restart is the normal way to switch pcbridge mode after it has already been installed.")
                elif action == "remove":
                    lines.append("Remove deletes the service definition. It does not clean up paired PC files by itself.")
                else:
                    lines.append("Stopping pcbridge ends the managed SSH/bootstrap process and any active pairing token task.")
            elif selected_service in ("sshd", "ssh"):
                if action == "start":
                    lines.append("Starts the managed SSH daemon. Aurora prints copy-ready SSH connect commands after success.")
                elif action == "stop":
                    lines.append("Stops the managed SSH daemon. Existing SSH sessions may be terminated by the daemon shutdown.")
                elif action == "restart":
                    lines.append("Restarts the managed SSH daemon and refreshes the printed connect commands.")
                elif action == "remove":
                    lines.append("Remove deletes only the Aurora service definition. SSH packages and config files inside the distro remain.")
            else:
                lines.append("This is a generic foreground-command service managed by Aurora.")
                if action == "remove":
                    lines.append("Remove deletes only the Aurora service definition, not the command or package itself.")

            return lines

        return lines

    def tor_action_summary_lines(self, wrap_width):
        payload = self.tor_status_payload()
        distro = self.read_text("distro")
        action = str(self.form_values.get("action", "status")).strip().lower() or "status"
        lines = [f"Distro: {distro or '<select distro>'}", f"Action: {action}"]

        if not distro:
            lines.append("Select an installed distro first.")
            return lines

        if payload is None:
            lines.append("Tor status is not loaded yet.")
            return lines

        daemon = payload.get("daemon", {}) if isinstance(payload.get("daemon"), dict) else {}
        routing = payload.get("routing", {}) if isinstance(payload.get("routing"), dict) else {}
        runtime = payload.get("runtime", {}) if isinstance(payload.get("runtime"), dict) else {}
        saved = payload.get("saved_config", {}) if isinstance(payload.get("saved_config"), dict) else {}
        backend = payload.get("backend", {}) if isinstance(payload.get("backend"), dict) else {}
        active_exit = payload.get("active_exit", {}) if isinstance(payload.get("active_exit"), dict) else {}
        public_exit = payload.get("public_exit", {}) if isinstance(payload.get("public_exit"), dict) else {}
        freeze = payload.get("freeze", {}) if isinstance(payload.get("freeze"), dict) else {}
        run_mode = str(payload.get("run_mode", "") or "").strip().lower()
        warnings = payload.get("warnings", [])
        if not isinstance(warnings, list):
            warnings = []

        def run_mode_status_line(mode):
            if mode == "configured":
                return "Configured prefs: apps + exit active."
            if mode == "configured-apps":
                return "Configured prefs: apps active; exit prefs ignored."
            if mode == "configured-exit":
                return "Configured prefs: exit prefs active; app bypass ignored."
            if mode == "default":
                return "Configured prefs: saved only; current run ignores them."
            return "Configured prefs: run mode unknown."

        def run_mode_action_line(mode, verb):
            if mode == "configured":
                return f"{verb} Tor and apply saved bypass/exit prefs."
            if mode == "configured-apps":
                return f"{verb} Tor with saved bypass prefs only; saved exit prefs are ignored."
            if mode == "configured-exit":
                return f"{verb} Tor with saved exit prefs only; saved bypass prefs are ignored."
            return f"{verb} Tor with plain defaults; saved prefs are ignored."

        lines.append(
            f"Mode: {'enabled' if payload.get('enabled') else 'disabled'} | "
            f"health: {'healthy' if payload.get('healthy') else 'degraded'} | "
            f"active-distro: {payload.get('active_distro') or 'none'}"
        )
        lines.append(
            f"Daemon: {daemon.get('state', 'stopped')} | pid: {daemon.get('pid') or '-'} | "
            f"user: {daemon.get('user', '') or 'unknown'} | "
            f"identity: {daemon.get('identity_mode', '') or 'unknown'} | uid: {daemon.get('uid') if daemon.get('uid') is not None else '-'}"
        )
        lines.append(
            f"Routing: app-uids={routing.get('app_uid_count', 0)} targets={routing.get('target_uid_count', 0)} "
            f"ranges={routing.get('uid_range_count', 0)} termux={'yes' if routing.get('termux_uid_included') else 'no'}"
        )
        lines.append(
            f"Saved config: bypass={saved.get('bypass_package_count', 0)} "
            f"exit={saved.get('exit_country_count', 0)} strict={'on' if saved.get('exit_strict') else 'off'}"
        )
        if payload.get("enabled"):
            lines.append(run_mode_status_line(run_mode))
            lines.append(f"Exit freeze: {'active' if freeze.get('active') else 'off'}")
        if saved.get("exit_resolved"):
            lines.append(f"Saved exit countries: {saved.get('exit_resolved')}")
        if active_exit.get("available"):
            exit_geo = " ".join(
                str(part)
                for part in [str(active_exit.get("country_code") or "").upper(), active_exit.get("country")]
                if part
            )
            exit_parts = [active_exit.get("ip"), exit_geo, active_exit.get("nickname") or active_exit.get("fingerprint")]
            lines.append(f"Tor exit: {' | '.join(str(part) for part in exit_parts if part)}")
        if freeze.get("active"):
            frozen_parts = [freeze.get("country_code") or freeze.get("country"), freeze.get("region"), freeze.get("city")]
            frozen_geo = " | ".join(str(part) for part in frozen_parts if part)
            if freeze.get("public_ip"):
                lines.append(f"Frozen public: {freeze.get('public_ip')}{f' | {frozen_geo}' if frozen_geo else ''}")
            frozen_exit = " ".join(str(part) for part in [freeze.get("exit_fingerprint"), freeze.get("exit_nickname")] if part)
            if frozen_exit:
                lines.append(f"Pinned relay: {frozen_exit}")
            if freeze.get("exit_ip"):
                lines.append(f"Relay IP: {freeze.get('exit_ip')}")
        lines.append(
            f"Policy: tcp=tor dns=tor udp={routing.get('udp_policy', 'blocked')} "
            f"ipv6={routing.get('ipv6_policy', 'blocked')} lan-bypass={'yes' if routing.get('lan_bypass') else 'no'}"
        )
        lines.append(
            f"Runtime: rules={'on' if runtime.get('rules_active') else 'off'} "
            f"bootstrap={'yes' if runtime.get('bootstrap_complete') else 'no'}"
        )
        if public_exit.get("available"):
            location_parts = [
                public_exit.get("country_code") or public_exit.get("country"),
                public_exit.get("region"),
                public_exit.get("city"),
            ]
            location_text = " | ".join(str(part) for part in location_parts if part)
            lines.append(f"Status probe: {public_exit.get('ip') or '?'}{f' | {location_text}' if location_text else ''}")
            network = public_exit.get("org") or public_exit.get("isp") or ""
            asn = public_exit.get("asn")
            if network and asn not in (None, ""):
                lines.append(f"Probe network: {network} (AS{asn}) via {public_exit.get('source') or 'lookup'}")
            elif network:
                lines.append(f"Probe network: {network} via {public_exit.get('source') or 'lookup'}")
            elif public_exit.get("source"):
                lines.append(f"Probe source: {public_exit.get('source')}")
        if active_exit.get("available") and public_exit.get("available"):
            active_ip = str(active_exit.get("ip") or "").strip()
            public_ip = str(public_exit.get("ip") or "").strip()
            active_country = str(active_exit.get("country_code") or "").strip().upper()
            public_country = str(public_exit.get("country_code") or "").strip().upper()
            if active_ip and public_ip and not active_exit.get("matched_public_ip"):
                lines.append("Probe compare: live SOCKS probe hit a different exit than Tor control's current exit candidate.")
            elif active_country and public_country and active_country != public_country:
                lines.append(f"Geo note: Tor control says {active_country}; probe GeoIP says {public_country}.")
        elif public_exit.get("error"):
            lines.append(f"Status probe lookup error: {public_exit.get('error')}")
        elif public_exit.get("reason") and daemon.get("state") == "running":
            lines.append(f"Status probe unavailable: {public_exit.get('reason')}")
        lines.append(
            f"Routing backend: "
            f"v4={backend.get('routing_backend_v4', 'none')} "
            f"v6={backend.get('routing_backend_v6', 'none')}"
        )
        if backend.get("routing_backend_v4") == "policy-routing" or backend.get("routing_backend_v6") == "policy-routing":
            lines.append("Host uses policy-routing fallback for blocking.")

        if warnings:
            for warning in warnings[:3]:
                lines.append(f"Warning: {warning}")
        else:
            lines.append("Warnings: none")

        if action == "on":
            run_mode = str(self.form_values.get("run_mode", "default")).strip().lower() or "default"
            lines.append(f"Run mode: {run_mode}")
            lines.append(run_mode_action_line(run_mode, "Start"))
            lines.append(
                "Local/LAN direct access: blocked."
                if self.form_values.get("no_lan_bypass")
                else "Local/LAN direct access: allowed via bypass."
            )
            lines.append("Mounts if needed, installs Tor if missing, then applies routing.")
        elif action in ("off", "stop"):
            lines.append("Stop Tor and remove Aurora routing for this distro.")
        elif action == "restart":
            run_mode = str(self.form_values.get("run_mode", "default")).strip().lower() or "default"
            lines.append(f"Run mode: {run_mode}")
            lines.append(run_mode_action_line(run_mode, "Restart"))
            lines.append(
                "Local/LAN direct access: blocked."
                if self.form_values.get("no_lan_bypass")
                else "Local/LAN direct access: allowed via bypass."
            )
            lines.append("Runs a clean off/on cycle.")
        elif action == "freeze":
            lines.append("Pin the current public exit for this session.")
            lines.append("Clears on newnym, off, or restart.")
            if freeze.get("active"):
                lines.append("Running freeze again repins to the exit in use now.")
        elif action == "logs":
            tail = str(self.form_values.get("tail", "")).strip() or "120"
            lines.append(f"Show the last {tail} Tor log lines.")
        elif action == "newnym":
            lines.append("Ask Tor for a new identity for new connections.")
            lines.append("Clears any active freeze.")
        elif action == "doctor":
            lines.append("Check Tor package, daemon identity, and routing support.")
            if self.form_values.get("json"):
                lines.append("Output: JSON")
        elif action == "apps":
            apps_action = str(self.form_values.get("apps_action", "browse")).strip().lower() or "browse"
            apps_scope = str(self.form_values.get("apps_scope", "all")).strip().lower() or "all"
            apps_payload = self.tor_apps_payload()
            package_count = int(apps_payload.get("package_count", 0) or 0)
            bypass_count = int(apps_payload.get("bypass_package_count", 0) or 0)
            lines.append(f"Apps action: {apps_action}")
            lines.append(f"App scope: {apps_scope}")
            lines.append(f"Known apps: {package_count} | bypassed: {bypass_count}")
            lines.append(
                f"Inventory split: user={int(apps_payload.get('user_package_count', 0) or 0)} "
                f"system={int(apps_payload.get('system_package_count', 0) or 0)} "
                f"unknown={int(apps_payload.get('unknown_package_count', 0) or 0)}"
            )
            lines.append("App scope filters browsing, matching, and bypass-list display in the TUI.")
            if apps_action in ("browse", "bypass-add", "bypass-remove"):
                query = self.read_text("apps_query")
                lines.append(f"Query: {query or '<none>'}")
            if apps_action == "bypass-add":
                lines.append("Add the selected app UID group to saved bypass.")
                lines.append("Used when Tor run mode applies saved app config.")
            elif apps_action == "bypass-remove":
                lines.append("Remove the selected app UID group from saved bypass.")
            elif apps_action == "bypass-show":
                lines.append("Show the saved bypass list.")
            else:
                lines.append("List or search known Android apps.")
                lines.append("Inventory refreshes when this runs.")
        elif action == "exit":
            exit_action = str(self.form_values.get("exit_action", "show")).strip().lower() or "show"
            exit_payload = self.tor_exit_payload()
            countries = exit_payload.get("countries", []) if isinstance(exit_payload.get("countries"), list) else []
            lines.append(f"Exit action: {exit_action}")
            lines.append(f"Saved exit countries: {', '.join(str(x).upper() for x in countries) if countries else 'none'}")
            lines.append(f"Strict mode: {'on' if exit_payload.get('strict') else 'off'}")
            if exit_action in ("list", "add", "remove"):
                query = self.read_text("country_query")
                lines.append(f"Query: {query or '<none>'}")
            if exit_action == "add":
                lines.append("Add a saved exit country.")
                lines.append("Used when Tor run mode applies saved exit config.")
            elif exit_action == "remove":
                lines.append("Remove a saved exit country.")
            elif exit_action == "clear":
                lines.append("Clear saved exit countries and turn strict off.")
            elif exit_action == "strict-on":
                lines.append("Require Tor to use only saved exit countries.")
            elif exit_action == "strict-off":
                lines.append("Use saved exit countries as preference, not requirement.")
            else:
                lines.append("Show saved exit-country prefs.")
        elif action == "remove":
            lines.append("Delete Aurora Tor state and Tor runtime/config/log/cache dirs.")
            lines.append("Installed Tor packages stay in the distro.")
        else:
            lines.append("Read-only snapshot of daemon, routing, public exit, and saved prefs.")

        return lines

    def command_default_summary_lines(self, wrap_width):
        lines = []
        if self.active_command == "backup":
            lines.append(f"Default output when 'out' is empty: {self.backup_default_output_hint()}")
        elif self.active_command == "restore":
            distro = self.read_text("distro")
            default_file = self.default_restore_file_for_distro(distro)
            if default_file:
                lines.append(f"Default restore file when path is empty: {default_file}")
            else:
                lines.append("Default restore file when path is empty: <no backups for selected distro>")
        elif self.active_command == "clear-cache":
            strategy = str(self.form_values.get("strategy", "default")).strip() or "default"
            if strategy == "older":
                days = str(self.form_values.get("days", "")).strip() or "14"
                lines.append(f"Deletes cached downloads older than {days} days.")
            elif strategy == "all":
                lines.append("Deletes cached downloads, tmp leftovers, interrupted install staging dirs, and stale mount/desktop runtime logs.")
                lines.append("Keeps backups, settings, installed distro state, and retained action logs.")
            else:
                lines.append("Deletes cached downloads older than 14 days.")
        elif self.active_command == "tor":
            lines.extend(self.tor_action_summary_lines(wrap_width))
        elif self.active_command == "service":
            lines.extend(self.service_action_summary_lines(wrap_width))

        wrapped = []
        for line in lines:
            chunk = wrap_lines(line, wrap_width)
            if chunk:
                wrapped.extend(chunk)
            else:
                wrapped.append(line)
        return wrapped
