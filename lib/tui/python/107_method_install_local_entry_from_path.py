    def install_local_entry_from_path(self, path, catalog=None):
        file_path = str(path or "").strip()
        if not file_path or not os.path.isfile(file_path):
            return None

        basename = os.path.basename(file_path)
        suffix = self.install_local_archive_suffix(basename)
        if not suffix:
            return None

        stem = basename[: -len(suffix)] if suffix else basename
        catalog_rows = catalog if isinstance(catalog, list) else self.install_local_manifest_catalog()
        known_rows = []
        for row in catalog_rows:
            if not isinstance(row, dict):
                continue
            distro_id = str(row.get("id", "") or "").strip()
            if distro_id:
                known_rows.append((distro_id, row))
        known_rows.sort(key=lambda item: (-len(item[0]), item[0]))

        def split_unknown_stem(stem):
            text = str(stem or "").strip()
            if not text or "-" not in text:
                return text, ""
            prefix, suffix = text.rsplit("-", 1)
            if not prefix:
                return text, ""
            token = suffix.lower()
            looks_like_label = bool(
                re.fullmatch(
                    r"(?:v?\d[\w.-]*|\d+(?:\.\d+){0,3}|rolling|stable|current|latest|release|lts|minimal|nano|full|base|slim|small|default)",
                    token,
                )
            )
            if looks_like_label:
                return prefix, suffix
            return text, ""

        distro_id = ""
        distro_row = None
        for candidate_id, candidate_row in known_rows:
            if stem == candidate_id or stem.startswith(candidate_id + "-"):
                distro_id = candidate_id
                distro_row = candidate_row
                break

        label = ""
        if distro_id:
            prefix = distro_id + "-"
            if stem.startswith(prefix):
                label = stem[len(prefix):]
        else:
            distro_id, label = split_unknown_stem(stem)

        display_name = str(distro_row.get("name", "") or distro_id) if isinstance(distro_row, dict) else distro_id
        version_row = None
        versions = distro_row.get("versions", []) if isinstance(distro_row, dict) else []
        if not isinstance(versions, list):
            versions = []
        for row in versions:
            if not isinstance(row, dict):
                continue
            install_target = str(row.get("install_target", "") or "").strip()
            release = str(row.get("release", "") or "").strip()
            if label and (label == install_target or label == release):
                version_row = row
                break
        if version_row is None and not label and len(versions) == 1:
            version_row = versions[0]

        display_label = label
        if isinstance(version_row, dict):
            display_label = str(version_row.get("install_target", "") or version_row.get("release", "") or label).strip()

        try:
            size_bytes = os.path.getsize(file_path)
        except Exception:
            size_bytes = 0
        try:
            mtime = os.path.getmtime(file_path)
            mtime_text = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(mtime))
        except Exception:
            mtime = 0.0
            mtime_text = "unknown"

        compression = suffix.lstrip(".")
        if isinstance(version_row, dict):
            compression = str(version_row.get("compression", "") or compression).strip()

        return {
            "path": file_path,
            "basename": basename,
            "stem": stem,
            "distro": distro_id,
            "name": display_name or distro_id,
            "display_label": display_label,
            "size_bytes": max(0, int(size_bytes or 0)),
            "size_text": self.install_local_human_bytes(size_bytes),
            "mtime": mtime,
            "mtime_text": mtime_text,
            "compression": compression or suffix.lstrip("."),
            "archive_suffix": suffix,
            "archive_type": suffix.lstrip("."),
            "channel": str(version_row.get("channel", "") or "").strip() if isinstance(version_row, dict) else "",
            "arch": str(version_row.get("arch", "") or "").strip() if isinstance(version_row, dict) else "",
            "sha256": str(version_row.get("sha256", "") or "").strip() if isinstance(version_row, dict) else "",
            "manifest_match": bool(version_row),
            "known_distro": bool(distro_row),
        }
