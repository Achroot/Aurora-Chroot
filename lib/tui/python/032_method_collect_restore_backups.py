    def collect_restore_backups(self, payload):
        out = {}
        if not isinstance(payload, dict):
            return out
        raw = payload.get("backup_index", {})
        if not isinstance(raw, dict):
            return out

        for distro in sorted(raw.keys()):
            files = raw.get(distro)
            if not isinstance(files, list):
                continue
            norm = []
            for path in files:
                text = str(path).strip()
                if not text:
                    continue
                norm.append(text)
            if norm:
                norm = sorted(set(norm))
                out[str(distro)] = norm
        return out

