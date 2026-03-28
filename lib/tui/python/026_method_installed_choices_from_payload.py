    def installed_choices_from_payload(self, payload):
        rows = payload.get("distros", []) if isinstance(payload, dict) else []
        if not isinstance(rows, list):
            rows = []

        out = []
        for row in rows:
            distro = str(row.get("distro", "")).strip()
            if not distro:
                continue
            release = str(row.get("release", "")).strip() or "n/a"
            sessions = str(row.get("sessions", 0))
            mounts = str(row.get("mount_entries", 0))
            rootfs_mounts = str(row.get("rootfs_mounts", 0))
            safe_rm = "yes" if bool(row.get("safe_to_remove", False)) else "no"
            label = f"{distro} ({release}) s:{sessions} m:{mounts} r:{rootfs_mounts} rm:{safe_rm}"
            out.append((distro, label))
        out.sort(key=lambda item: item[0])
        return out

