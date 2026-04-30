    def draw_install_local(self, height, width):
        layout = self.install_local_layout(height, width)
        content_top = layout["content_top"]
        content_height = layout["content_height"]
        left_width = layout["left_width"]
        right_left = layout["right_left"]
        right_width = layout["right_width"]
        list_top = layout["list_top"]
        visible_rows = layout["visible_rows"]

        left_active = self.install_local_panel_focus != "right"
        right_active = self.install_local_panel_focus == "right"
        draw_box(
            self.stdscr,
            content_top,
            0,
            content_height,
            left_width,
            f"LOCAL ARCHIVES{' [ACTIVE]' if left_active else ''}",
            self.color(2) if left_active else self.color(4),
            self.color(2, curses.A_BOLD) if left_active else self.color(1, curses.A_BOLD),
        )
        draw_box(
            self.stdscr,
            content_top,
            right_left,
            content_height,
            right_width,
            f"DETAILS{' [ACTIVE]' if right_active else ''}",
            self.color(2) if right_active else self.color(4),
            self.color(2, curses.A_BOLD) if right_active else self.color(1, curses.A_BOLD),
        )

        total_rows = 1 + len(self.install_local_entries)
        start = max(0, self.install_local_index - visible_rows + 1)
        end = min(total_rows, start + visible_rows)

        for idx in range(start, end):
            row_y = list_top + (idx - start)
            marker = "->" if idx == self.install_local_index else "  "
            style = self.color(2, curses.A_BOLD) if idx == self.install_local_index else self.color(0)
            if idx == 0:
                text = f"{marker} Tarball Path: {self.install_local_path or '<empty>'}"
            else:
                entry = self.install_local_entries[idx - 1]
                label = str(entry.get("distro", "") or "<unknown>").strip()
                display_label = str(entry.get("display_label", "") or "").strip()
                if display_label:
                    label = f"{label} {display_label}"
                archive_type = str(entry.get("archive_type", "") or "tar").strip()
                text = f"{marker} {label} [{archive_type}]"
            if self.install_local_left_hscroll > 0:
                text = text[self.install_local_left_hscroll:]
            addstr_clipped(self.stdscr, row_y, 2, text, left_width - 4, style)

        detail_rows = self.install_local_detail_rows_for_width(right_width)
        self.draw_text_panel_rows(
            content_top,
            right_left,
            content_height,
            right_width,
            detail_rows,
            "install_local_detail_scroll",
            "install_local_detail_hscroll",
        )
        return

        y = content_top + 2
        selected = self.current_install_local_entry()
        path = str(self.install_local_path or "").strip()
        path_kind = str(self.install_local_path_kind or "").strip() or "unknown"

        if selected is None:
            addstr_clipped(self.stdscr, y, right_left + 2, "Tarball Path", right_width - 4, self.color(2, curses.A_BOLD))
            y += 2
            addstr_clipped(self.stdscr, y, right_left + 2, f"Current path: {path or '<empty>'}", right_width - 4, self.color(0))
            y += 1
            addstr_clipped(self.stdscr, y, right_left + 2, f"Path type: {path_kind}", right_width - 4, self.color(0))
            y += 1
            addstr_clipped(self.stdscr, y, right_left + 2, f"Archives found: {len(self.install_local_entries)}", right_width - 4, self.color(0))
            y += 2
            addstr_clipped(self.stdscr, y, right_left + 2, "Supported names:", right_width - 4, self.color(6, curses.A_BOLD))
            y += 1
            addstr_clipped(self.stdscr, y, right_left + 2, ".tar, .tar.*, .tgz, .tbz2, .txz, .tzst", right_width - 4, self.color(0))
            y += 2
            if self.install_local_entries:
                addstr_clipped(self.stdscr, y, right_left + 2, "Use arrows to select an archive, then press i to install.", right_width - 4, self.color(3))
            else:
                addstr_clipped(self.stdscr, y, right_left + 2, "Press Enter to change the path and rescan this location.", right_width - 4, self.color(6))
            return

        addstr_clipped(self.stdscr, y, right_left + 2, f"{selected.get('name', '') or selected.get('distro', '')} ({selected.get('distro', '')})", right_width - 4, self.color(2, curses.A_BOLD))
        y += 2
        addstr_clipped(self.stdscr, y, right_left + 2, f"Target: {selected.get('display_label', '') or selected.get('basename', '')}", right_width - 4, self.color(0))
        y += 1
        addstr_clipped(self.stdscr, y, right_left + 2, f"Archive: {selected.get('basename', '')}", right_width - 4, self.color(0))
        y += 1
        addstr_clipped(self.stdscr, y, right_left + 2, f"Size: {selected.get('size_text', 'unknown')}", right_width - 4, self.color(0))
        y += 1
        addstr_clipped(self.stdscr, y, right_left + 2, f"Modified: {selected.get('mtime_text', 'unknown')}", right_width - 4, self.color(0))
        y += 1
        addstr_clipped(self.stdscr, y, right_left + 2, f"Compression: {selected.get('compression', '') or selected.get('archive_type', '')}", right_width - 4, self.color(0))
        y += 1
        checksum_mode = "manifest match" if selected.get("sha256") else "not provided"
        addstr_clipped(self.stdscr, y, right_left + 2, f"Checksum: {checksum_mode}", right_width - 4, self.color(0))
        y += 1
        detection = "catalog-backed" if selected.get("known_distro") else "filename-derived"
        addstr_clipped(self.stdscr, y, right_left + 2, f"Detection: {detection}", right_width - 4, self.color(0))
        y += 1
        if selected.get("channel"):
            addstr_clipped(self.stdscr, y, right_left + 2, f"Channel: {selected.get('channel', '')}", right_width - 4, self.color(0))
            y += 1
        if selected.get("arch"):
            addstr_clipped(self.stdscr, y, right_left + 2, f"Arch: {selected.get('arch', '')}", right_width - 4, self.color(0))
            y += 1
        runtime_root = self.install_local_runtime_root()
        if runtime_root:
            install_path = os.path.join(runtime_root, "rootfs", str(selected.get("distro", "") or ""))
            addstr_clipped(self.stdscr, y, right_left + 2, f"Install path: {install_path}", right_width - 4, self.color(6))
            y += 2
        else:
            y += 1

        addstr_clipped(self.stdscr, y, right_left + 2, "Archive path:", right_width - 4, self.color(6, curses.A_BOLD))
        y += 1
        for line in wrap_lines(str(selected.get("path", "") or ""), right_width - 4):
            if y >= content_top + content_height - 3:
                break
            addstr_clipped(self.stdscr, y, right_left + 2, line, right_width - 4, self.color(0))
            y += 1

        if y < content_top + content_height - 2:
            y += 1
            if selected.get("sha256"):
                note = "Press i to install using the manifest checksum."
            else:
                note = "Press i to install. No manifest checksum is available for this archive."
            addstr_clipped(self.stdscr, y, right_left + 2, note, right_width - 4, self.color(3, curses.A_BOLD))

    def install_local_left_rows(self):
        rows = [(f"Tarball Path: {self.install_local_path or '<empty>'}", self.color(0))]
        for entry in self.install_local_entries:
            label = str(entry.get("distro", "") or "<unknown>").strip()
            display_label = str(entry.get("display_label", "") or "").strip()
            if display_label:
                label = f"{label} {display_label}"
            archive_type = str(entry.get("archive_type", "") or "tar").strip()
            rows.append((f"{label} [{archive_type}]", self.color(0)))
        return rows

    def install_local_detail_rows_for_width(self, right_width):
        selected = self.current_install_local_entry()
        path = str(self.install_local_path or "").strip()
        path_kind = str(self.install_local_path_kind or "").strip() or "unknown"
        if selected is None:
            rows = [
                ("Tarball Path", self.color(2, curses.A_BOLD)),
                ("", self.color(0)),
                (f"Current path: {path or '<empty>'}", self.color(0)),
                (f"Path type: {path_kind}", self.color(0)),
                (f"Archives found: {len(self.install_local_entries)}", self.color(0)),
                ("", self.color(0)),
                ("Supported names:", self.color(6, curses.A_BOLD)),
                (".tar, .tar.*, .tgz, .tbz2, .txz, .tzst", self.color(0)),
                ("", self.color(0)),
            ]
            if self.install_local_entries:
                rows.append(("Use arrows to select an archive, then press i to install.", self.color(3)))
            else:
                rows.append(("Press Enter to change the path and rescan this location.", self.color(6)))
            return rows

        rows = [
            (f"{selected.get('name', '') or selected.get('distro', '')} ({selected.get('distro', '')})", self.color(2, curses.A_BOLD)),
            ("", self.color(0)),
            (f"Target: {selected.get('display_label', '') or selected.get('basename', '')}", self.color(0)),
            (f"Archive: {selected.get('basename', '')}", self.color(0)),
            (f"Size: {selected.get('size_text', 'unknown')}", self.color(0)),
            (f"Modified: {selected.get('mtime_text', 'unknown')}", self.color(0)),
            (f"Compression: {selected.get('compression', '') or selected.get('archive_type', '')}", self.color(0)),
        ]
        checksum_mode = "manifest match" if selected.get("sha256") else "not provided"
        rows.append((f"Checksum: {checksum_mode}", self.color(0)))
        detection = "catalog-backed" if selected.get("known_distro") else "filename-derived"
        rows.append((f"Detection: {detection}", self.color(0)))
        if selected.get("channel"):
            rows.append((f"Channel: {selected.get('channel', '')}", self.color(0)))
        if selected.get("arch"):
            rows.append((f"Arch: {selected.get('arch', '')}", self.color(0)))
        runtime_root = self.install_local_runtime_root()
        if runtime_root:
            install_path = os.path.join(runtime_root, "rootfs", str(selected.get("distro", "") or ""))
            rows.append((f"Install path: {install_path}", self.color(6)))
        rows.append(("", self.color(0)))
        rows.append(("Archive path:", self.color(6, curses.A_BOLD)))
        rows.extend(self.wrapped_panel_rows(str(selected.get("path", "") or ""), right_width - 4, self.color(0)))
        rows.append(("", self.color(0)))
        if selected.get("sha256"):
            note = "Press i to install using the manifest checksum."
        else:
            note = "Press i to install. No manifest checksum is available for this archive."
        rows.append((note, self.color(3, curses.A_BOLD)))
        return rows
