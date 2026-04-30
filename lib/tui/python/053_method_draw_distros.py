    def distro_menu_name(self, item):
        name = str(item.get("name", "") or item.get("id", "")).strip()
        fallback = str(item.get("id", "") or "").strip()
        name = re.sub(r"\s*\([^)]*\)", "", name)
        name = re.sub(r"\bGNU/Linux\b", "", name, flags=re.IGNORECASE)
        name = re.sub(r"\bBase\b", "", name, flags=re.IGNORECASE)
        name = re.sub(r"\bLinux\b", "", name, flags=re.IGNORECASE)
        name = re.sub(r"Linux$", "", name, flags=re.IGNORECASE)
        name = re.sub(r"\s+", " ", name).strip(" -_/")
        return name or fallback

    def distros_footer_text(self):
        return "! Want a different distro or version? Download your own tarball, then use the install-local command."

    def distros_footer_rows_for_width(self, left_width):
        rows = [("", self.color(0))]
        rows.extend(self.wrapped_panel_rows(self.distros_footer_text(), left_width - 4, self.color(6, curses.A_BOLD)))
        return rows

    def distros_left_scroll_start(self, visible_rows):
        visible_rows = max(1, visible_rows)
        if self.distros_stage == "distros":
            if not self.distros_catalog:
                return 0
            rows = self.distros_left_rows()
            total_rows = len(rows)
            max_start = max(0, total_rows - visible_rows)
            return min(max(0, self.distros_index - visible_rows + 1), max_start)

        distro = self.current_distro()
        versions = distro.get("versions", []) if distro else []
        total_rows = len(versions)
        if total_rows <= 0:
            return 0
        max_start = max(0, total_rows - visible_rows)
        standard_start = max(0, self.distros_version_index - visible_rows + 1)
        return min(standard_start, max_start)

    def draw_distros(self, height, width):
        content_top, content_height, _ = self.screen_content_layout(height, width)
        left_width = max(28, int(width * 0.42))
        right_left = left_width + 2
        right_width = width - right_left - 1

        left_title = "DISTROS" if self.distros_stage == "distros" else "VERSIONS"
        if self.distros_stage == "detail":
            left_title = "SELECTED"

        left_active = self.distros_panel_focus != "right"
        right_active = self.distros_panel_focus == "right"
        draw_box(
            self.stdscr,
            content_top,
            0,
            content_height,
            left_width,
            f"{left_title}{' [ACTIVE]' if left_active else ''}",
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

        if not self.distros_catalog:
            addstr_clipped(self.stdscr, content_top + 2, 2, "No distro catalog loaded. Press r to refresh.", left_width - 4, self.color(5))
            return

        distro = self.current_distro()
        version = self.current_version()

        list_top = content_top + 1
        rows = self.distros_left_rows()

        if self.distros_stage == "distros":
            footer_rows = self.distros_footer_rows_for_width(left_width)
            footer_height = len(footer_rows)
            visible_rows = max(1, content_height - 2 - footer_height)
            start = self.distros_left_scroll_start(visible_rows)
            end = min(len(rows), start + visible_rows)
            for idx in range(start, end):
                row = list_top + (idx - start)
                text, style = rows[idx]
                marker = "->" if idx == self.distros_index else "  "
                text = f"{marker} {text}"
                if idx == self.distros_index:
                    style = self.color(2, curses.A_BOLD)
                if self.distros_left_hscroll > 0:
                    text = text[self.distros_left_hscroll:]
                addstr_clipped(self.stdscr, row, 2, text, left_width - 4, style)
            footer_top = list_top + (end - start)
            for offset, (text, style) in enumerate(footer_rows):
                row = footer_top + offset
                if row >= content_top + content_height - 1:
                    break
                addstr_clipped(self.stdscr, row, 2, text, left_width - 4, style)
        elif self.distros_stage in ("versions", "detail"):
            visible_rows = max(1, content_height - 2)
            start = self.distros_left_scroll_start(visible_rows)
            end = min(len(rows), start + visible_rows)
            for idx in range(start, end):
                row = list_top + (idx - start)
                text, style = rows[idx]
                marker = "->" if idx == self.distros_version_index else "  "
                text = f"{marker} {text}"
                if idx == self.distros_version_index:
                    style = self.color(2, curses.A_BOLD)
                if self.distros_left_hscroll > 0:
                    text = text[self.distros_left_hscroll:]
                addstr_clipped(self.stdscr, row, 2, text, left_width - 4, style)

        detail_rows = self.distros_detail_rows_for_width(right_width)
        self.draw_text_panel_rows(
            content_top,
            right_left,
            content_height,
            right_width,
            detail_rows,
            "distros_detail_scroll",
            "distros_detail_hscroll",
        )
        return

        y = content_top + 2
        if not distro:
            addstr_clipped(self.stdscr, y, right_left + 2, "No distro selected", right_width - 4, self.color(5))
            return

        addstr_clipped(self.stdscr, y, right_left + 2, f"{distro.get('name','')} ({distro.get('id','')})", right_width - 4, self.color(2, curses.A_BOLD))
        y += 2
        if self.distros_runtime_root:
            addstr_clipped(self.stdscr, y, right_left + 2, f"Runtime root: {self.distros_runtime_root}", right_width - 4, self.color(0))
            y += 1
        addstr_clipped(self.stdscr, y, right_left + 2, f"Tier: {distro.get('tier','')} | Visibility: {distro.get('visibility','')}", right_width - 4, self.color(0))
        y += 1
        preferred_release = str(distro.get("preferred_release", "") or "")
        preferred_target = str(distro.get("preferred_install_target", "") or preferred_release)
        if preferred_target and preferred_target != preferred_release:
            default_text = f"Default: {preferred_target} ({distro.get('preferred_channel','')})"
        else:
            default_text = f"Default: {preferred_release} ({distro.get('preferred_channel','')})"
        addstr_clipped(self.stdscr, y, right_left + 2, default_text, right_width - 4, self.color(0))
        y += 1
        addstr_clipped(self.stdscr, y, right_left + 2, f"Default size: {distro.get('preferred_size_text','unknown')}", right_width - 4, self.color(0))
        y += 1
        addstr_clipped(self.stdscr, y, right_left + 2, f"Latest: {distro.get('latest_release','')} ({distro.get('latest_channel','')})", right_width - 4, self.color(0))
        y += 1
        installed_release = distro.get("installed_release", "")
        installed_text = "yes"
        if installed_release:
            installed_text = f"yes ({installed_release})"
        elif not distro.get("installed"):
            installed_text = "no"
        addstr_clipped(self.stdscr, y, right_left + 2, f"Installed: {installed_text}", right_width - 4, self.color(0))
        y += 2

        notes = distro.get("notes", [])
        if not isinstance(notes, list) or not notes:
            notes = distro.get("warnings", [])
        if isinstance(notes, list) and notes:
            addstr_clipped(self.stdscr, y, right_left + 2, "Notes:", right_width - 4, self.color(6, curses.A_BOLD))
            y += 1
            for note in notes[:3]:
                for line in wrap_lines(str(note), right_width - 4):
                    if y >= content_top + content_height - 3:
                        break
                    addstr_clipped(self.stdscr, y, right_left + 2, line, right_width - 4, self.color(0))
                    y += 1
                if y >= content_top + content_height - 3:
                    break
            if y < content_top + content_height - 3:
                y += 1

        if self.distros_stage == "distros":
            addstr_clipped(self.stdscr, y, right_left + 2, "Press Enter to open install choices.", right_width - 4, self.color(6))
            return

        if not version:
            addstr_clipped(self.stdscr, y, right_left + 2, "No version selected.", right_width - 4, self.color(5))
            return

        addstr_clipped(self.stdscr, y, right_left + 2, f"Target: {version.get('install_target', version.get('release',''))}", right_width - 4, self.color(1, curses.A_BOLD))
        y += 1
        addstr_clipped(self.stdscr, y, right_left + 2, f"Release: {version.get('release','')}", right_width - 4, self.color(0))
        y += 1
        addstr_clipped(self.stdscr, y, right_left + 2, f"Channel: {version.get('channel','')}", right_width - 4, self.color(0))
        y += 1
        addstr_clipped(self.stdscr, y, right_left + 2, f"Tier: {version.get('tier','')} | Stale manifest: {'yes' if version.get('stale') else 'no'}", right_width - 4, self.color(0))
        y += 1
        addstr_clipped(self.stdscr, y, right_left + 2, f"Arch: {version.get('arch','')}", right_width - 4, self.color(0))
        y += 1
        addstr_clipped(self.stdscr, y, right_left + 2, f"Size: {version.get('size_text','unknown')}", right_width - 4, self.color(0))
        y += 1
        addstr_clipped(self.stdscr, y, right_left + 2, f"Compression: {version.get('compression','')}", right_width - 4, self.color(0))
        y += 1
        addstr_clipped(self.stdscr, y, right_left + 2, f"Source: {version.get('source','')}", right_width - 4, self.color(0))
        y += 1
        if version.get("download_cached"):
            downloaded_text = f"yes ({version.get('download_cache_size_text','unknown')})"
        else:
            downloaded_text = "no"
        addstr_clipped(self.stdscr, y, right_left + 2, f"Downloaded: {downloaded_text}", right_width - 4, self.color(0))
        y += 1
        if self.distros_runtime_root:
            install_path = os.path.join(self.distros_runtime_root, "rootfs", str(distro.get("id", "")))
            addstr_clipped(self.stdscr, y, right_left + 2, f"Install path: {install_path}", right_width - 4, self.color(6))
        y += 2
        addstr_clipped(self.stdscr, y, right_left + 2, "URL:", right_width - 4, self.color(6, curses.A_BOLD))
        y += 1
        for line in wrap_lines(version.get("rootfs_url", ""), right_width - 4):
            if y >= content_top + content_height - 3:
                break
            addstr_clipped(self.stdscr, y, right_left + 2, line, right_width - 4, self.color(0))
            y += 1

        version_notes = version.get("notes", [])
        if not isinstance(version_notes, list) or not version_notes:
            note = str(version.get("provider_comment", "") or "")
            version_notes = [note] if note else []
        if version_notes and y < content_top + content_height - 3:
            y += 1
            addstr_clipped(self.stdscr, y, right_left + 2, "Note:", right_width - 4, self.color(6, curses.A_BOLD))
            y += 1
            for note in version_notes[:3]:
                for line in wrap_lines(str(note), right_width - 4):
                    if y >= content_top + content_height - 3:
                        break
                    addstr_clipped(self.stdscr, y, right_left + 2, line, right_width - 4, self.color(0))
                    y += 1
                if y >= content_top + content_height - 3:
                    break

        if self.distros_stage == "detail" and y < content_top + content_height - 2:
            y += 1
            addstr_clipped(self.stdscr, y, right_left + 2, "Press i to download and install, or d to download only.", right_width - 4, self.color(3, curses.A_BOLD))

    def distros_left_rows(self):
        rows = []
        if self.distros_stage == "distros":
            for item in self.distros_catalog:
                rows.append((self.distro_menu_name(item), self.color(0)))
            return rows
        distro = self.current_distro()
        versions = distro.get("versions", []) if distro else []
        for item in versions:
            release = str(item.get("release", "") or "")
            target = str(item.get("install_target", "") or release)
            label = target if target and target != release else release
            status = " stale-provider" if item.get("stale") else ""
            if item.get("download_cached"):
                status += " downloaded"
            rows.append((f"{label} [{item.get('channel','')}] {item.get('tier','')}{status}", self.color(0)))
        return rows

    def distros_detail_rows_for_width(self, right_width):
        distro = self.current_distro()
        version = self.current_version()
        if not distro:
            return [("No distro selected", self.color(5))]
        stale_note_text = "This entry is from stale manifest fallback because a live provider refresh was unavailable."
        rows = [
            (f"{distro.get('name','')} ({distro.get('id','')})", self.color(2, curses.A_BOLD)),
            ("", self.color(0)),
        ]
        if self.distros_runtime_root:
            rows.append((f"Runtime root: {self.distros_runtime_root}", self.color(0)))
        rows.append((f"Tier: {distro.get('tier','')} | Visibility: {distro.get('visibility','')}", self.color(0)))
        preferred_release = str(distro.get("preferred_release", "") or "")
        preferred_target = str(distro.get("preferred_install_target", "") or preferred_release)
        if preferred_target and preferred_target != preferred_release:
            rows.append((f"Default: {preferred_target} ({distro.get('preferred_channel','')})", self.color(0)))
        else:
            rows.append((f"Default: {preferred_release} ({distro.get('preferred_channel','')})", self.color(0)))
        rows.append((f"Default size: {distro.get('preferred_size_text','unknown')}", self.color(0)))
        rows.append((f"Latest: {distro.get('latest_release','')} ({distro.get('latest_channel','')})", self.color(0)))
        if distro.get("stale") or (version and version.get("stale")):
            rows.append((stale_note_text, self.color(5, curses.A_BOLD)))
            rows.append(("", self.color(0)))
        installed_release = distro.get("installed_release", "")
        installed_text = "yes"
        if installed_release:
            installed_text = f"yes ({installed_release})"
        elif not distro.get("installed"):
            installed_text = "no"
        rows.append((f"Installed: {installed_text}", self.color(0)))
        rows.append(("", self.color(0)))

        notes = distro.get("notes", [])
        if not isinstance(notes, list) or not notes:
            notes = distro.get("warnings", [])
        distro_notes = []
        if isinstance(notes, list):
            seen_notes = set()
            for note in notes[:3]:
                text = str(note)
                note_key = text.strip()
                if not note_key or note_key in seen_notes or note_key == stale_note_text:
                    continue
                seen_notes.add(note_key)
                distro_notes.append(text)
        if distro_notes:
            rows.append(("Notes:", self.color(6, curses.A_BOLD)))
            for note in distro_notes:
                rows.extend(self.wrapped_panel_rows(str(note), right_width - 4, self.color(0)))
            rows.append(("", self.color(0)))

        if self.distros_stage == "distros":
            rows.append(("Press Enter to open install choices.", self.color(6)))
            return rows
        if not version:
            rows.append(("No version selected.", self.color(5)))
            return rows

        rows.extend(
            [
                (f"Target: {version.get('install_target', version.get('release',''))}", self.color(1, curses.A_BOLD)),
                (f"Release: {version.get('release','')}", self.color(0)),
                (f"Channel: {version.get('channel','')}", self.color(0)),
                (f"Tier: {version.get('tier','')} | Stale manifest: {'yes' if version.get('stale') else 'no'}", self.color(0)),
                (f"Arch: {version.get('arch','')}", self.color(0)),
                (f"Size: {version.get('size_text','unknown')}", self.color(0)),
                (f"Compression: {version.get('compression','')}", self.color(0)),
                (f"Source: {version.get('source','')}", self.color(0)),
            ]
        )
        downloaded_text = f"yes ({version.get('download_cache_size_text','unknown')})" if version.get("download_cached") else "no"
        rows.append((f"Downloaded: {downloaded_text}", self.color(0)))
        if self.distros_runtime_root:
            install_path = os.path.join(self.distros_runtime_root, "rootfs", str(distro.get("id", "")))
            rows.append((f"Install path: {install_path}", self.color(6)))
        rows.append(("", self.color(0)))
        rows.append(("URL:", self.color(6, curses.A_BOLD)))
        rows.extend(self.wrapped_panel_rows(version.get("rootfs_url", ""), right_width - 4, self.color(0)))

        version_notes = version.get("notes", [])
        if not isinstance(version_notes, list) or not version_notes:
            note = str(version.get("provider_comment", "") or "")
            version_notes = [note] if note else []
        filtered_version_notes = []
        seen_version_notes = {note.strip() for note in distro_notes if note.strip()}
        for note in version_notes[:3]:
            text = str(note)
            note_key = text.strip()
            if not note_key or note_key in seen_version_notes or note_key == stale_note_text:
                continue
            seen_version_notes.add(note_key)
            filtered_version_notes.append(text)
        if filtered_version_notes:
            rows.append(("", self.color(0)))
            rows.append(("Note:", self.color(6, curses.A_BOLD)))
            for note in filtered_version_notes:
                rows.extend(self.wrapped_panel_rows(str(note), right_width - 4, self.color(0)))
        if self.distros_stage == "detail":
            rows.append(("", self.color(0)))
            rows.append(("Press i to download and install, or d to download only.", self.color(3, curses.A_BOLD)))
        return rows
