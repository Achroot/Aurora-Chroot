    def draw_distros(self, height, width):
        content_top = 2
        content_height = height - content_top - 3
        left_width = max(28, int(width * 0.42))
        right_left = left_width + 2
        right_width = width - right_left - 1

        left_title = "DISTROS" if self.distros_stage == "distros" else "VERSIONS"
        if self.distros_stage == "detail":
            left_title = "SELECTED"

        draw_box(self.stdscr, content_top, 0, content_height, left_width, left_title, self.color(4), self.color(1, curses.A_BOLD))
        draw_box(self.stdscr, content_top, right_left, content_height, right_width, "DETAILS", self.color(4), self.color(1, curses.A_BOLD))

        if not self.distros_catalog:
            addstr_clipped(self.stdscr, content_top + 2, 2, "No distro catalog loaded. Press r to fetch.", left_width - 4, self.color(5))
            return

        distro = self.current_distro()
        version = self.current_version()

        list_top = content_top + 1
        visible_rows = max(1, content_height - 2)

        if self.distros_stage == "distros":
            start = max(0, self.distros_index - visible_rows + 1)
            end = min(len(self.distros_catalog), start + visible_rows)
            for idx in range(start, end):
                row = list_top + (idx - start)
                item = self.distros_catalog[idx]
                marker = "->" if idx == self.distros_index else "  "
                text = f"{marker} {item.get('id','')} ({item.get('latest_release','')})"
                style = self.color(2, curses.A_BOLD) if idx == self.distros_index else self.color(0)
                addstr_clipped(self.stdscr, row, 2, text, left_width - 4, style)
        elif self.distros_stage in ("versions", "detail"):
            versions = distro.get("versions", []) if distro else []
            start = max(0, self.distros_version_index - visible_rows + 1)
            end = min(len(versions), start + visible_rows)
            for idx in range(start, end):
                row = list_top + (idx - start)
                item = versions[idx]
                marker = "->" if idx == self.distros_version_index else "  "
                text = f"{marker} {item.get('release','')} [{item.get('channel','')}]"
                style = self.color(2, curses.A_BOLD) if idx == self.distros_version_index else self.color(0)
                addstr_clipped(self.stdscr, row, 2, text, left_width - 4, style)

        y = content_top + 2
        if not distro:
            addstr_clipped(self.stdscr, y, right_left + 2, "No distro selected", right_width - 4, self.color(5))
            return

        addstr_clipped(self.stdscr, y, right_left + 2, f"{distro.get('name','')} ({distro.get('id','')})", right_width - 4, self.color(2, curses.A_BOLD))
        y += 2
        if self.distros_runtime_root:
            addstr_clipped(self.stdscr, y, right_left + 2, f"Runtime root: {self.distros_runtime_root}", right_width - 4, self.color(0))
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

        if self.distros_stage == "distros":
            addstr_clipped(self.stdscr, y, right_left + 2, "Enter opens versions list.", right_width - 4, self.color(6))
            return

        if not version:
            addstr_clipped(self.stdscr, y, right_left + 2, "No version selected.", right_width - 4, self.color(5))
            return

        addstr_clipped(self.stdscr, y, right_left + 2, f"Release: {version.get('release','')}", right_width - 4, self.color(1, curses.A_BOLD))
        y += 1
        addstr_clipped(self.stdscr, y, right_left + 2, f"Channel: {version.get('channel','')}", right_width - 4, self.color(0))
        y += 1
        addstr_clipped(self.stdscr, y, right_left + 2, f"Arch: {version.get('arch','')}", right_width - 4, self.color(0))
        y += 1
        addstr_clipped(self.stdscr, y, right_left + 2, f"Compression: {version.get('compression','')}", right_width - 4, self.color(0))
        y += 1
        addstr_clipped(self.stdscr, y, right_left + 2, f"Source: {version.get('source','')}", right_width - 4, self.color(0))
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

        if self.distros_stage == "detail" and y < content_top + content_height - 2:
            y += 1
            addstr_clipped(self.stdscr, y, right_left + 2, "Press i to install this version.", right_width - 4, self.color(3, curses.A_BOLD))

