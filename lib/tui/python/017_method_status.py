    def status(self, message, kind="info"):
        self.status_message = str(message)
        self.status_kind = kind
        self.status_time = time.time()

    def clear_status(self):
        self.status_message = ""
        self.status_kind = "info"
        self.status_time = 0.0

    def status_persistent(self):
        return self.status_kind == "error"

    def status_visible(self):
        if not self.status_message:
            return False
        if self.status_persistent():
            return True
        return (time.time() - self.status_time) < 3.0

    def status_poll_timeout_ms(self):
        if not self.status_visible():
            return -1
        if self.status_persistent():
            return -1
        remaining = max(0.0, 3.0 - (time.time() - self.status_time))
        return max(25, min(100, int(remaining * 1000)))

    def status_overlay_geometry(self, height, width):
        if not self.status_visible():
            return None

        message = self.status_message
        y = max(2, min(height - 3, int(round(height * 0.25))))
        x = max(1, (width - len(message)) // 2)
        render_width = min(len(message), max(1, width - x - 1))
        return {
            "message": message,
            "x": x,
            "y": y,
            "width": render_width,
        }

    def status_overlay_hitbox(self, height, width):
        geometry = self.status_overlay_geometry(height, width)
        if not geometry:
            return None

        pad_x = 2
        pad_y = 1
        left = max(0, geometry["x"] - pad_x)
        right = min(width - 1, geometry["x"] + geometry["width"] - 1 + pad_x)
        top = max(0, geometry["y"] - pad_y)
        bottom = min(height - 1, geometry["y"] + pad_y)
        return (left, top, right, bottom)

    def status_overlay_contains(self, y, x, height, width):
        hitbox = self.status_overlay_hitbox(height, width)
        if not hitbox:
            return False
        left, top, right, bottom = hitbox
        return left <= x <= right and top <= y <= bottom

    def dismiss_status_for_key(self, key):
        if not self.status_visible():
            return
        if key in (-1, curses.KEY_RESIZE, curses.KEY_MOUSE):
            return
        self.clear_status()

    def draw_status_overlay(self, height, width):
        geometry = self.status_overlay_geometry(height, width)
        if not geometry:
            return

        attr = self.color(7, curses.A_BOLD)
        if self.status_kind == "error":
            attr = self.color(5, curses.A_BOLD)
        elif self.status_kind == "ok":
            attr = self.color(3, curses.A_BOLD)

        addstr_clipped(self.stdscr, geometry["y"], geometry["x"], geometry["message"], geometry["width"], attr)
