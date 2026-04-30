    def handle_mouse(self):
        try:
            _, x, y, _, bstate = curses.getmouse()
        except Exception:
            return False

        button4 = getattr(curses, "BUTTON4_PRESSED", 0x80000)
        button5 = getattr(curses, "BUTTON5_PRESSED", 0x200000)
        height, width = self.stdscr.getmaxyx()
        content_top = 2
        list_top = content_top + 1
        pointer_mask = curses.BUTTON1_CLICKED | curses.BUTTON1_PRESSED | curses.BUTTON1_RELEASED

        if self.status_visible():
            if bstate & (button4 | button5):
                pass
            elif self.status_persistent() and self.status_overlay_contains(y, x, height, width):
                return True
            elif bstate & pointer_mask:
                self.clear_status()

        form_left = False
        form_right = False
        if self.state == "form" and height >= 14 and width >= 54:
            panel_top, panel_height, left_width, right_left, right_width = self.form_panel_layout(height, width)
            panel_bottom = panel_top + panel_height - 1
            form_left = (0 <= x < left_width) and (panel_top < y < panel_bottom)
            form_right = (right_left <= x < (right_left + right_width)) and (panel_top < y < panel_bottom)

        def content_panel_hits(left_width, right_left, right_width):
            panel_top, panel_height, _ = self.screen_content_layout(height, width)
            panel_bottom = panel_top + panel_height - 1
            body_hit = panel_top < y < panel_bottom
            left_hit = (0 <= x < left_width) and body_hit
            right_hit = (right_left <= x < (right_left + right_width)) and body_hit
            return left_hit, right_hit, panel_height

        def menu_detail_rows(right_width):
            selected = self.commands[self.menu_index] if self.commands else ""
            section = self.get_section(selected) if selected else {}
            rows = [
                (section.get("usage", selected), self.color(2, curses.A_BOLD)),
                ("", self.color(0)),
            ]
            rows.extend(self.wrapped_panel_rows(section.get("summary", ""), right_width - 4, self.color(0)))
            if selected == "distros":
                rows.append(("", self.color(0)))
                rows.append(("Flow: distro -> version -> details -> install", self.color(6)))
            if selected == "settings":
                rows.append(("", self.color(0)))
                rows.append(("Shows current value + allowed values per key.", self.color(6)))
            return rows

        def wheel_menu(detail_delta, list_delta):
            left_width = max(24, int(width * 0.33))
            right_left = left_width + 2
            right_width = width - right_left - 1
            left_hit, right_hit, content_height = content_panel_hits(left_width, right_left, right_width)
            if right_hit or (self.menu_panel_focus == "right" and not left_hit):
                self.menu_panel_focus = "right"
                rows = menu_detail_rows(right_width)
                self.scroll_text_panel_vertical(
                    "menu_detail_scroll",
                    "menu_detail_hscroll",
                    rows,
                    max(1, content_height - 2),
                    max(1, right_width - 4),
                    detail_delta,
                )
            else:
                self.menu_panel_focus = "left"
                self.move_menu(list_delta)

        def wheel_distros(detail_delta, list_delta):
            left_width = max(28, int(width * 0.42))
            right_left = left_width + 2
            right_width = width - right_left - 1
            left_hit, right_hit, content_height = content_panel_hits(left_width, right_left, right_width)
            if right_hit or (self.distros_panel_focus == "right" and not left_hit):
                self.distros_panel_focus = "right"
                rows = self.distros_detail_rows_for_width(right_width)
                self.scroll_text_panel_vertical(
                    "distros_detail_scroll",
                    "distros_detail_hscroll",
                    rows,
                    max(1, content_height - 2),
                    max(1, right_width - 4),
                    detail_delta,
                )
            else:
                self.distros_panel_focus = "left"
                self.move_distros(list_delta)

        def wheel_install_local(detail_delta, list_delta):
            layout = self.install_local_layout(height, width)
            panel_bottom = layout["content_top"] + layout["content_height"] - 1
            body_hit = layout["content_top"] < y < panel_bottom
            left_hit = (0 <= x < layout["left_width"]) and body_hit
            right_hit = (
                layout["right_left"] <= x < (layout["right_left"] + layout["right_width"])
                and body_hit
            )
            if right_hit or (self.install_local_panel_focus == "right" and not left_hit):
                self.install_local_panel_focus = "right"
                rows = self.install_local_detail_rows_for_width(layout["right_width"])
                self.scroll_text_panel_vertical(
                    "install_local_detail_scroll",
                    "install_local_detail_hscroll",
                    rows,
                    max(1, layout["content_height"] - 2),
                    max(1, layout["right_width"] - 4),
                    detail_delta,
                )
            else:
                self.install_local_panel_focus = "left"
                self.move_install_local(list_delta)

        def wheel_settings(detail_delta, list_delta):
            left_width = max(32, int(width * 0.46))
            right_left = left_width + 2
            right_width = width - right_left - 1
            left_hit, right_hit, content_height = content_panel_hits(left_width, right_left, right_width)
            if right_hit or (self.settings_panel_focus == "right" and not left_hit):
                self.settings_panel_focus = "right"
                rows = self.settings_detail_rows_for_width(right_width)
                self.scroll_text_panel_vertical(
                    "settings_detail_scroll",
                    "settings_detail_hscroll",
                    rows,
                    max(1, content_height - 2),
                    max(1, right_width - 4),
                    detail_delta,
                )
            else:
                self.settings_panel_focus = "left"
                if self.settings_rows:
                    self.settings_index = (self.settings_index + list_delta) % len(self.settings_rows)
                    self.reset_panel_scroll("settings_detail_scroll", "settings_detail_hscroll")

        def busybox_action_row_at():
            content_top, content_height, _ = self.screen_content_layout(height, width)
            panel_bottom = content_top + content_height - 1
            if not (content_top < y < panel_bottom):
                return None
            row_idx = self.busybox_scroll + (y - (content_top + 1))
            action_idx = row_idx - 1
            if 0 <= action_idx < len(self.busybox_actions()):
                return action_idx
            return None

        if bstate & button4:
            if self.state == "menu":
                self.menu_panel_focus = "left"
                self.move_menu(1)
            elif self.state == "form":
                if form_right or (self.form_panel_focus == "right" and not form_left):
                    self.form_panel_focus = "right"
                    self.scroll_preview(-1)
                else:
                    self.form_panel_focus = "left"
                    self.move_form(1)
            elif self.state == "distros":
                wheel_distros(-1, 1)
            elif self.state == "install_local":
                wheel_install_local(-1, 1)
            elif self.state == "settings":
                wheel_settings(-1, 1)
            elif self.state == "busybox":
                self.move_busybox_action(1)
            elif self.state == "tor_apps_tunneling":
                self.move_tor_apps_tunneling(1)
            elif self.state == "tor_exit_mode":
                self.move_tor_exit_mode(1)
            elif self.state == "info":
                layout = self.info_layout(height, width)
                left_hit = (
                    layout["left_left"] <= x < (layout["left_left"] + layout["left_width"])
                    and layout["left_top"] <= y < (layout["left_top"] + layout["left_height"])
                )
                if left_hit:
                    self.info_panel_focus = "left"
                    self.move_info_section(1)
                else:
                    self.info_panel_focus = "right"
                    self.scroll_info_content(-1)
            else:
                self.result_scroll = max(0, self.result_scroll - 1)
            return True

        if bstate & button5:
            if self.state == "menu":
                self.menu_panel_focus = "left"
                self.move_menu(-1)
            elif self.state == "form":
                if form_right or (self.form_panel_focus == "right" and not form_left):
                    self.form_panel_focus = "right"
                    self.scroll_preview(1)
                else:
                    self.form_panel_focus = "left"
                    self.move_form(-1)
            elif self.state == "distros":
                wheel_distros(1, -1)
            elif self.state == "install_local":
                wheel_install_local(1, -1)
            elif self.state == "settings":
                wheel_settings(1, -1)
            elif self.state == "busybox":
                self.move_busybox_action(-1)
            elif self.state == "tor_apps_tunneling":
                self.move_tor_apps_tunneling(-1)
            elif self.state == "tor_exit_mode":
                self.move_tor_exit_mode(-1)
            elif self.state == "info":
                layout = self.info_layout(height, width)
                left_hit = (
                    layout["left_left"] <= x < (layout["left_left"] + layout["left_width"])
                    and layout["left_top"] <= y < (layout["left_top"] + layout["left_height"])
                )
                if left_hit:
                    self.info_panel_focus = "left"
                    self.move_info_section(-1)
                else:
                    self.info_panel_focus = "right"
                    self.scroll_info_content(1)
            else:
                _content_top, content_height, _ = self.screen_content_layout(height, width)
                view_height = max(1, content_height - 4)
                max_scroll = max(0, len(self.result_lines) - view_height)
                self.result_scroll = min(max_scroll, self.result_scroll + 1)
            return True

        if self.state == "tor_apps_tunneling":
            click_mask = curses.BUTTON1_CLICKED | curses.BUTTON1_RELEASED
            if bstate & click_mask:
                layout = self.tor_apps_tunneling_layout(height, width)
                filter_y = layout["top"] + 2
                if y == filter_y:
                    choice = self.tor_apps_tunneling_scope_from_x(x, layout)
                    if choice:
                        self.tor_apps_tunneling_scope = choice
                        self.tor_apps_tunneling_index = 0
                        self.tor_apps_tunneling_scroll = 0
                        return True
                row = self.tor_apps_tunneling_row_at(y, layout)
                if row is not None:
                    self.tor_apps_tunneling_index = row
                    self.toggle_current_tor_apps_tunneling()
                    return True
            elif bstate & curses.BUTTON1_PRESSED:
                layout = self.tor_apps_tunneling_layout(height, width)
                row = self.tor_apps_tunneling_row_at(y, layout)
                if row is not None:
                    self.tor_apps_tunneling_index = row
                    self.normalize_tor_apps_tunneling_view()
                    return True

        if self.state == "tor_exit_mode":
            click_mask = curses.BUTTON1_CLICKED | curses.BUTTON1_RELEASED
            if bstate & click_mask:
                layout = self.tor_exit_mode_layout(height, width)
                filter_y = layout["top"] + 2
                if y == filter_y:
                    choice = self.tor_exit_mode_filter_from_x(x, layout)
                    if choice:
                        self.set_tor_exit_mode_header_focus(choice, focus_area="header")
                        if choice == "performance":
                            self.toggle_tor_exit_mode_performance()
                        elif choice == "strict":
                            self.toggle_tor_exit_mode_strict()
                        return True
                row = self.tor_exit_mode_row_at(y, layout)
                if row is not None:
                    self.tor_exit_mode_index = row
                    self.tor_exit_mode_focus_area = "list"
                    self.toggle_current_tor_exit_mode()
                    return True
            elif bstate & curses.BUTTON1_PRESSED:
                layout = self.tor_exit_mode_layout(height, width)
                filter_y = layout["top"] + 2
                if y == filter_y:
                    choice = self.tor_exit_mode_filter_from_x(x, layout)
                    if choice:
                        self.set_tor_exit_mode_header_focus(choice, focus_area="header")
                        return True
                row = self.tor_exit_mode_row_at(y, layout)
                if row is not None:
                    self.tor_exit_mode_index = row
                    self.tor_exit_mode_focus_area = "list"
                    self.normalize_tor_exit_mode_view()
                    return True

        if self.state == "info":
            layout = self.info_layout(height, width)
            left_hit = (
                layout["left_left"] <= x < (layout["left_left"] + layout["left_width"])
                and layout["left_top"] <= y < (layout["left_top"] + layout["left_height"])
            )
            detail_hit = (
                layout["detail_left"] <= x < (layout["detail_left"] + layout["detail_width"])
                and layout["detail_top"] <= y < (layout["detail_top"] + layout["detail_height"])
            )
            click_mask = curses.BUTTON1_CLICKED | curses.BUTTON1_RELEASED | curses.BUTTON1_PRESSED
            if bstate & click_mask:
                if left_hit:
                    self.info_panel_focus = "left"
                    idx = self.info_section_row_at(y, layout)
                    if idx is not None:
                        self.info_section_index = idx
                        self.info_scroll = 0
                    self.normalize_info_view()
                    return True
                if detail_hit:
                    self.info_panel_focus = "right"
                    self.normalize_info_view()
                    return True

        if bstate & pointer_mask:
            if self.state == "menu":
                left_width = max(24, int(width * 0.33))
                self.menu_panel_focus = "left"
                if x < left_width and y >= list_top:
                    idx = self.menu_scroll + (y - list_top)
                    if 0 <= idx < len(self.commands):
                        self.menu_index = idx
                        self.open_selected_menu_command()
                        return True
                else:
                    return True
            elif self.state == "form":
                if form_right:
                    self.form_panel_focus = "right"
                    return True
                if form_left and y >= list_top:
                    self.form_panel_focus = "left"
                    idx = (y - list_top)
                    fields = self.visible_fields()
                    if 0 <= idx < len(fields):
                        self.form_index = idx
                        self.edit_current_field()
                        return True
                    return True
            elif self.state == "distros":
                left_width = max(28, int(width * 0.42))
                content_top, content_height, _ = self.screen_content_layout(height, width)
                panel_bottom = content_top + content_height - 1
                list_top = content_top + 1
                footer_rows = self.distros_footer_rows_for_width(left_width) if self.distros_stage == "distros" else []
                visible_rows = max(1, content_height - 2 - len(footer_rows)) if self.distros_stage == "distros" else max(1, content_height - 2)
                left_hit = x < left_width and content_top < y < panel_bottom
                if left_hit:
                    self.distros_panel_focus = "left"
                    if self.distros_stage == "distros":
                        if y < list_top + visible_rows:
                            start = self.distros_left_scroll_start(visible_rows)
                            idx = start + (y - list_top)
                            if 0 <= idx < len(self.distros_catalog):
                                self.distros_index = idx
                                self.distros_stage = "versions"
                                self.distros_version_index = 0
                                return True
                        return True
                    elif self.distros_stage in ("versions", "detail"):
                        if y < list_top + visible_rows:
                            distro = self.current_distro()
                            versions = distro.get("versions", []) if distro else []
                            start = max(0, self.distros_version_index - visible_rows + 1)
                            idx = start + (y - list_top)
                            if 0 <= idx < len(versions):
                                self.distros_version_index = idx
                                self.distros_stage = "detail"
                                return True
                        return True
                self.distros_panel_focus = "right"
                return True
            elif self.state == "install_local":
                layout = self.install_local_layout(height, width)
                if x < layout["left_width"] and y >= layout["list_top"]:
                    self.install_local_panel_focus = "left"
                    start = max(0, self.install_local_index - layout["visible_rows"] + 1)
                    idx = start + (y - layout["list_top"])
                    total_rows = 1 + len(self.install_local_entries)
                    if 0 <= idx < total_rows:
                        self.install_local_index = idx
                        if idx == 0:
                            current = self.install_local_path
                            new_value = self.prompt_input("Tarball Path", current)
                            self.install_local_path = str(new_value or "").strip()
                            self.form_values["file"] = self.install_local_path
                            self.load_install_local_entries(show_loading=True, select_first_entry=True)
                        return True
                else:
                    self.install_local_panel_focus = "right"
                    return True
            elif self.state == "settings":
                left_width = max(32, int(width * 0.46))
                if x < left_width and y >= list_top:
                    self.settings_panel_focus = "left"
                    content_top, content_height, _ = self.screen_content_layout(height, width)
                    list_top = content_top + 1
                    visible_rows = max(1, content_height - 2)
                    start = max(0, self.settings_index - visible_rows + 1)
                    idx = start + (y - list_top)
                    if 0 <= idx < len(self.settings_rows):
                        self.settings_index = idx
                        self.reset_panel_scroll("settings_detail_scroll", "settings_detail_hscroll")
                        return True
                else:
                    self.settings_panel_focus = "right"
                    return True
            elif self.state == "busybox":
                action_idx = busybox_action_row_at()
                if action_idx is not None:
                    self.busybox_action_index = action_idx
                    self.busybox_scroll = 0
                    self.busybox_hscroll = 0
                    self.run_busybox_action()
                    return True
                return True
        return False
