    def install_local_manifest_catalog(self):
        if self.distros_catalog:
            return [row for row in self.distros_catalog if isinstance(row, dict)]

        runtime_root = self.install_local_runtime_root()
        if not runtime_root:
            return []

        manifest_path = os.path.join(runtime_root, "manifests", "index.json")
        try:
            with open(manifest_path, "r", encoding="utf-8") as fh:
                payload = json.load(fh)
        except Exception:
            return []

        distros = payload.get("distros", [])
        if not isinstance(distros, list):
            return []

        out = []
        grouped = {}
        for row in distros:
            if not isinstance(row, dict):
                continue
            distro_id = str(row.get("id", "") or "").strip()
            if not distro_id:
                continue
            normalized = dict(row)
            versions = normalized.get("versions", [])
            if isinstance(versions, list) and versions:
                normalized["versions"] = [dict(item) for item in versions if isinstance(item, dict)]
                out.append(normalized)
                continue
            version = {
                "install_target": str(row.get("install_target", row.get("release", "")) or ""),
                "release": str(row.get("release", "") or ""),
                "channel": str(row.get("channel", "") or ""),
                "arch": str(row.get("arch", "") or ""),
                "rootfs_url": str(row.get("rootfs_url", "") or ""),
                "sha256": str(row.get("sha256", "") or ""),
                "compression": str(row.get("compression", "") or ""),
                "source": str(row.get("source", "") or ""),
            }
            current = grouped.get(distro_id)
            if current is None:
                current = dict(row)
                current["versions"] = []
                grouped[distro_id] = current
            current["versions"].append(version)
        out.extend(grouped.values())
        return out
