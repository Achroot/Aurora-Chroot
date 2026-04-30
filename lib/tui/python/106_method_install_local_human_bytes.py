    def install_local_human_bytes(self, num):
        try:
            value = float(num)
        except Exception:
            return "unknown"
        if value <= 0:
            return "0B"
        units = ["B", "K", "M", "G", "T", "P"]
        idx = 0
        while value >= 1024.0 and idx < len(units) - 1:
            value /= 1024.0
            idx += 1
        if idx == 0:
            return f"{int(value)}{units[idx]}"
        if value >= 10:
            return f"{value:.0f}{units[idx]}"
        return f"{value:.1f}{units[idx]}"
