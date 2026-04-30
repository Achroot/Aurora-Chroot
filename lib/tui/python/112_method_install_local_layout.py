    def install_local_layout(self, height, width):
        content_top, content_height, _ = self.screen_content_layout(height, width)
        left_width = max(32, int(width * 0.44))
        right_left = left_width + 2
        right_width = width - right_left - 1
        list_top = content_top + 1
        visible_rows = max(1, content_height - 2)
        return {
            "content_top": content_top,
            "content_height": content_height,
            "left_width": left_width,
            "right_left": right_left,
            "right_width": right_width,
            "list_top": list_top,
            "visible_rows": visible_rows,
        }
