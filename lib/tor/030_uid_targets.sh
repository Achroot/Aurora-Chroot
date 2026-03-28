chroot_tor_root_copy_file() {
  local path="$1"
  local out_file="$2"
  chroot_run_root cat "$path" >"$out_file" 2>/dev/null
}

chroot_tor_apps_refresh() {
  local distro="$1"
  local fatal="${2:-1}"
  local packages_list_file packages_xml_file out_file uid_source

  chroot_tor_ensure_state_layout "$distro"
  chroot_tor_config_ensure_file "$distro"
  chroot_require_python

  packages_list_file="$CHROOT_TMP_DIR/tor-packages-list.$$.bin"
  packages_xml_file="$CHROOT_TMP_DIR/tor-packages-xml.$$.bin"
  out_file="$CHROOT_TMP_DIR/tor-apps.$$.json"

  if ! chroot_tor_root_copy_file /data/system/packages.list "$packages_list_file"; then
    rm -f -- "$packages_list_file" "$packages_xml_file" "$out_file"
    if [[ "$fatal" == "0" ]]; then
      return 1
    fi
    chroot_die "failed to read /data/system/packages.list"
  fi
  : >"$packages_xml_file"
  uid_source="/data/system/packages.list"
  if chroot_tor_root_copy_file /data/system/packages.xml "$packages_xml_file"; then
    uid_source="/data/system/packages.list+/data/system/packages.xml"
  fi

  CHROOT_TOR_UID_SOURCE="$uid_source"
  "$CHROOT_PYTHON_BIN" - "$packages_list_file" "$packages_xml_file" "$(chroot_tor_config_file "$distro")" "$out_file" "$(chroot_now_ts)" "$uid_source" <<'PY'
import hashlib
import json
import struct
import sys
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path


packages_list_path, packages_xml_path, config_path, out_path, generated_at, uid_source = sys.argv[1:7]

RES_STRING_POOL_TYPE = 0x0001
RES_TABLE_TYPE = 0x0002
RES_XML_TYPE = 0x0003
RES_XML_START_ELEMENT_TYPE = 0x0102

TYPE_REFERENCE = 0x01
TYPE_STRING = 0x03
TYPE_DYNAMIC_REFERENCE = 0x07

FLAG_COMPLEX = 0x0001
FLAG_COMPACT = 0x0008
FLAG_SPARSE = 0x01
FLAG_OFFSET16 = 0x02

NO_ENTRY = 0xFFFFFFFF
NO_STRING = 0xFFFFFFFF
ANDROID_NS = "http://schemas.android.com/apk/res/android"
SYSTEM_CODE_PATH_PREFIXES = (
    "/system/",
    "/system_ext/",
    "/product/",
    "/vendor/",
    "/odm/",
    "/oem/",
    "/apex/",
    "/init_boot/",
    "/system_dlkm/",
    "/vendor_dlkm/",
)
USER_CODE_PATH_PREFIXES = (
    "/data/app",
    "/mnt/expand/",
)

TYPE_NULL_ABX = 1 << 4
TYPE_STRING_ABX = 2 << 4
TYPE_STRING_INTERNED_ABX = 3 << 4
TYPE_BYTES_HEX_ABX = 4 << 4
TYPE_BYTES_BASE64_ABX = 5 << 4
TYPE_INT_ABX = 6 << 4
TYPE_INT_HEX_ABX = 7 << 4
TYPE_LONG_ABX = 8 << 4
TYPE_LONG_HEX_ABX = 9 << 4
TYPE_FLOAT_ABX = 10 << 4
TYPE_DOUBLE_ABX = 11 << 4
TYPE_BOOLEAN_TRUE_ABX = 12 << 4
TYPE_BOOLEAN_FALSE_ABX = 13 << 4

ABX_START_DOCUMENT = 0
ABX_END_DOCUMENT = 1
ABX_START_TAG = 2
ABX_END_TAG = 3
ABX_TEXT = 4
ABX_ATTRIBUTE = 15


def u16(data, off):
    return struct.unpack_from("<H", data, off)[0]


def u32(data, off):
    return struct.unpack_from("<I", data, off)[0]


def chunk_header(data, off):
    return struct.unpack_from("<HHI", data, off)


def decode_utf8_length(data, off):
    first = data[off]
    if first & 0x80:
        return ((first & 0x7F) << 8) | data[off + 1], 2
    return first, 1


def decode_utf16_length(data, off):
    first = u16(data, off)
    if first & 0x8000:
        return ((first & 0x7FFF) << 16) | u16(data, off + 2), 4
    return first, 2


class StringPool:
    def __init__(self, data, offset):
        chunk_type, header_size, size = chunk_header(data, offset)
        if chunk_type != RES_STRING_POOL_TYPE:
            raise ValueError("not a string pool")
        self._data = data
        self._base = offset
        self._string_count = u32(data, offset + 8)
        self._flags = u32(data, offset + 16)
        self._strings_start = u32(data, offset + 20)
        self._utf8 = bool(self._flags & 0x100)
        index_off = offset + header_size
        self._offsets = [u32(data, index_off + i * 4) for i in range(self._string_count)]
        self._cache = {}

    def get(self, index):
        if index in (None, NO_STRING):
            return None
        if index < 0 or index >= self._string_count:
            return None
        if index in self._cache:
            return self._cache[index]
        off = self._base + self._strings_start + self._offsets[index]
        if self._utf8:
            _, n1 = decode_utf8_length(self._data, off)
            byte_len, n2 = decode_utf8_length(self._data, off + n1)
            start = off + n1 + n2
            raw = self._data[start : start + byte_len]
            value = raw.decode("utf-8", errors="replace")
        else:
            char_len, n1 = decode_utf16_length(self._data, off)
            start = off + n1
            raw = self._data[start : start + (char_len * 2)]
            value = raw.decode("utf-16le", errors="replace")
        self._cache[index] = value
        return value


class ManifestInfo:
    def __init__(self):
        self.package = None
        self.split = None
        self.label_text = None
        self.label_ref = None


def parse_manifest(manifest_bytes):
    chunk_type, header_size, total_size = chunk_header(manifest_bytes, 0)
    if chunk_type != RES_XML_TYPE:
        raise ValueError("unexpected manifest header")

    pool = None
    info = ManifestInfo()
    off = header_size
    limit = min(total_size, len(manifest_bytes))

    while off + 8 <= limit:
        chunk_type, node_header_size, chunk_size = chunk_header(manifest_bytes, off)
        if chunk_size < 8:
            raise ValueError("bad manifest chunk size")
        if chunk_type == RES_STRING_POOL_TYPE:
            pool = StringPool(manifest_bytes, off)
        elif chunk_type == RES_XML_START_ELEMENT_TYPE and pool is not None:
            ext_off = off + node_header_size
            ns_idx, name_idx, attr_start, attr_size, attr_count, _, _, _ = struct.unpack_from(
                "<IIHHHHHH", manifest_bytes, ext_off
            )
            elem_name = pool.get(name_idx)
            attrs_off = ext_off + attr_start
            for i in range(attr_count):
                attr_off = attrs_off + (i * attr_size)
                ans_idx, aname_idx, raw_idx = struct.unpack_from("<III", manifest_bytes, attr_off)
                _, _, data_type, data_value = struct.unpack_from("<HBBI", manifest_bytes, attr_off + 12)
                attr_name = pool.get(aname_idx)
                attr_ns = pool.get(ans_idx)
                raw_value = pool.get(raw_idx)

                if elem_name == "manifest" and attr_name == "package":
                    info.package = raw_value or (pool.get(data_value) if data_type == TYPE_STRING else None)
                elif elem_name == "manifest" and attr_name == "split":
                    info.split = raw_value or (pool.get(data_value) if data_type == TYPE_STRING else None)
                elif elem_name == "application" and attr_name == "label" and attr_ns in (ANDROID_NS, None):
                    if raw_value and not raw_value.startswith("@"):
                        info.label_text = raw_value
                    elif data_type == TYPE_STRING:
                        info.label_text = pool.get(data_value)
                    elif data_type in (TYPE_REFERENCE, TYPE_DYNAMIC_REFERENCE):
                        info.label_ref = data_value
            if info.package and (info.label_text or info.label_ref is not None):
                break
        off += chunk_size
    return info


def config_is_default(config_blob):
    return not any(config_blob[4:])


def config_tag(config_blob):
    if len(config_blob) < 12:
        return ""
    lang = config_blob[8:10]
    country = config_blob[10:12]
    if lang == b"\x00\x00" and country == b"\x00\x00":
        return ""
    try:
        lang_text = lang.decode("ascii", errors="ignore").strip("\x00")
        country_text = country.decode("ascii", errors="ignore").strip("\x00")
    except Exception:
        return ""
    if lang_text and country_text:
        return f"{lang_text}-r{country_text}"
    return lang_text or country_text


def pick_candidate(candidates):
    if not candidates:
        return None
    candidates.sort(key=lambda item: item["score"])
    return candidates[0]


class ResourceTable:
    def __init__(self, data):
        chunk_type, header_size, total_size = chunk_header(data, 0)
        if chunk_type != RES_TABLE_TYPE:
            raise ValueError("unexpected resources header")
        self._data = data
        self._total_size = min(total_size, len(data))
        self._global_strings = None
        self._packages = []

        off = header_size
        while off + 8 <= self._total_size:
            ctype, _, csize = chunk_header(data, off)
            if csize < 8:
                raise ValueError("bad table chunk size")
            if ctype == RES_STRING_POOL_TYPE and self._global_strings is None:
                self._global_strings = StringPool(data, off)
            elif ctype == 0x0200:
                self._packages.append(self._parse_package(off))
            off += csize

    def _parse_package(self, off):
        header_size = u16(self._data, off + 2)
        pkg_id = u32(self._data, off + 8)
        name_utf16 = self._data[off + 12 : off + 12 + 256]
        pkg_name = name_utf16.decode("utf-16le", errors="ignore").split("\x00", 1)[0]
        type_strings_rel = u32(self._data, off + 268)
        key_strings_rel = u32(self._data, off + 276)
        chunk_size = u32(self._data, off + 4)
        package_end = off + chunk_size

        type_pool = StringPool(self._data, off + type_strings_rel) if type_strings_rel else None
        type_chunks = []
        sub_off = off + header_size
        while sub_off + 8 <= package_end:
          ctype, _, csize = chunk_header(self._data, sub_off)
          if csize < 8:
              raise ValueError("bad package subchunk size")
          if ctype == 0x0201:
              type_chunks.append(sub_off)
          sub_off += csize

        return {"id": pkg_id, "name": pkg_name, "type_pool": type_pool, "types": type_chunks}

    def resolve_string(self, res_id):
        return self._resolve_string(res_id, set())

    def _resolve_string(self, res_id, seen):
        if res_id in seen:
            return None
        seen.add(res_id)

        target_pkg = (res_id >> 24) & 0xFF
        target_type = (res_id >> 16) & 0xFF
        target_entry = res_id & 0xFFFF
        candidates = []

        for pkg in self._packages:
            if pkg["id"] != target_pkg:
                continue
            type_pool = pkg["type_pool"]
            for type_off in pkg["types"]:
                type_id = self._data[type_off + 8]
                flags = self._data[type_off + 9]
                entry_count = u32(self._data, type_off + 12)
                entries_start = u32(self._data, type_off + 16)
                header_size = u16(self._data, type_off + 2)
                config_size = u32(self._data, type_off + 20)
                config_end = min(type_off + 20 + config_size, type_off + header_size)
                config_blob = self._data[type_off + 20 : config_end]
                if type_id != target_type:
                    continue
                type_name = type_pool.get(type_id - 1) if type_pool is not None else None
                if type_name not in (None, "string"):
                    continue
                entry_offset = self._entry_offset(type_off, flags, entry_count, header_size, target_entry)
                if entry_offset is None:
                    continue
                value = self._entry_value(type_off + entries_start + entry_offset)
                if value is None:
                    continue
                data_type, data_value = value
                if data_type == TYPE_STRING and self._global_strings is not None:
                    text = self._global_strings.get(data_value)
                    if text:
                        candidates.append({"score": (0 if config_is_default(config_blob) else 1, config_tag(config_blob)), "text": text})
                elif data_type in (TYPE_REFERENCE, TYPE_DYNAMIC_REFERENCE):
                    text = self._resolve_string(data_value, seen)
                    if text:
                        candidates.append({"score": (0 if config_is_default(config_blob) else 1, config_tag(config_blob)), "text": text})
        picked = pick_candidate(candidates)
        return picked["text"] if picked else None

    def _entry_offset(self, type_off, flags, entry_count, header_size, target_entry):
        indices_off = type_off + header_size
        if flags & FLAG_SPARSE:
            for i in range(entry_count):
                raw = u32(self._data, indices_off + i * 4)
                idx = raw & 0xFFFF
                off16 = (raw >> 16) & 0xFFFF
                if idx == target_entry:
                    return off16 * 4
            return None
        if target_entry >= entry_count:
            return None
        if flags & FLAG_OFFSET16:
            off16 = u16(self._data, indices_off + target_entry * 2)
            if off16 == 0xFFFF:
                return None
            return off16 * 4
        off32 = u32(self._data, indices_off + target_entry * 4)
        if off32 == NO_ENTRY:
            return None
        return off32

    def _entry_value(self, entry_off):
        key = u16(self._data, entry_off)
        flags = u16(self._data, entry_off + 2)
        if flags & FLAG_COMPACT:
            return flags >> 8, u32(self._data, entry_off + 4)
        if flags & FLAG_COMPLEX:
            return None
        value_off = entry_off + key
        _, _, data_type, data_value = struct.unpack_from("<HBBI", self._data, value_off)
        return data_type, data_value


class FastIn:
    def __init__(self, data):
        self.data = data
        self.off = 0
        self.refs = []

    def read(self, n):
        out = self.data[self.off:self.off + n]
        if len(out) != n:
            raise EOFError
        self.off += n
        return out

    def read_u8(self):
        return self.read(1)[0]

    def read_u16(self):
        buf = self.read(2)
        return (buf[0] << 8) | buf[1]

    def read_u32(self):
        buf = self.read(4)
        return (buf[0] << 24) | (buf[1] << 16) | (buf[2] << 8) | buf[3]

    def read_u64(self):
        return (self.read_u32() << 32) | self.read_u32()

    def read_utf(self):
        size = self.read_u16()
        return self.read(size).decode("utf-8", errors="replace")

    def read_interned_utf(self):
        ref = self.read_u16()
        if ref == 0xFFFF:
            value = self.read_utf()
            self.refs.append(value)
            return value
        return self.refs[ref]


def read_abx_value(inp, type_code):
    if type_code == TYPE_NULL_ABX:
        return None
    if type_code == TYPE_STRING_ABX:
        return inp.read_utf()
    if type_code == TYPE_STRING_INTERNED_ABX:
        return inp.read_interned_utf()
    if type_code in (TYPE_BYTES_HEX_ABX, TYPE_BYTES_BASE64_ABX):
        return inp.read(inp.read_u16())
    if type_code in (TYPE_INT_ABX, TYPE_INT_HEX_ABX):
        return inp.read_u32()
    if type_code in (TYPE_LONG_ABX, TYPE_LONG_HEX_ABX):
        return inp.read_u64()
    if type_code == TYPE_FLOAT_ABX:
        return struct.unpack(">f", inp.read(4))[0]
    if type_code == TYPE_DOUBLE_ABX:
        return struct.unpack(">d", inp.read(8))[0]
    if type_code == TYPE_BOOLEAN_TRUE_ABX:
        return True
    if type_code == TYPE_BOOLEAN_FALSE_ABX:
        return False
    raise ValueError("unsupported ABX value type")


def parse_packages_xml(path):
    data = Path(path).read_bytes()
    if data.startswith(b"ABX\x00"):
        inp = FastIn(data)
        inp.read(4)
        packages = {}
        stack = []
        while True:
            try:
                event = inp.read_u8()
            except EOFError:
                break
            token = event & 0x0F
            type_code = event & 0xF0
            if token == ABX_START_DOCUMENT:
                continue
            if token == ABX_END_DOCUMENT:
                break
            if token == ABX_START_TAG:
                stack.append([inp.read_interned_utf(), {}])
                continue
            if token == ABX_END_TAG:
                _ = inp.read_interned_utf()
                start_name, attrs = stack.pop()
                if start_name == "package" and attrs.get("name"):
                    packages[str(attrs["name"]).strip()] = attrs
                continue
            if token == ABX_ATTRIBUTE:
                attr_name = inp.read_interned_utf()
                attr_value = read_abx_value(inp, type_code)
                if stack:
                    stack[-1][1][attr_name] = attr_value
                continue
            if token == ABX_TEXT:
                read_abx_value(inp, type_code)
                continue
        return packages

    text = data.decode("utf-8", errors="replace")
    root = ET.fromstring(text)
    out = {}
    for elem in root.iter("package"):
        name = str(elem.attrib.get("name", "")).strip()
        if name:
            out[name] = dict(elem.attrib)
    return out


def load_package_meta(path):
    metadata_warnings = []
    package_meta = {}
    packages_xml_loaded = False
    path_obj = Path(path)
    try:
        size = path_obj.stat().st_size
    except Exception:
        size = 0
    if size <= 0:
        metadata_warnings.append("packages.xml metadata unavailable")
        return package_meta, packages_xml_loaded, metadata_warnings
    try:
        package_meta = parse_packages_xml(path)
        packages_xml_loaded = True
    except Exception:
        metadata_warnings.append("packages.xml metadata unavailable")
    return package_meta, packages_xml_loaded, metadata_warnings


def resolve_apk_label(apk_path):
    with zipfile.ZipFile(apk_path) as zf:
        info = parse_manifest(zf.read("AndroidManifest.xml"))
        if info.label_text:
            return info, info.label_text, "manifest-string"
        if info.label_ref is not None and "resources.arsc" in zf.namelist():
            table = ResourceTable(zf.read("resources.arsc"))
            label = table.resolve_string(info.label_ref)
            return info, label, "resources.arsc" if label else "missing-label"
        return info, None, "missing-label"


def code_path_to_local_root(code_path):
    if not code_path:
        return None
    path = Path(str(code_path))
    if not path.is_absolute():
        return None
    if str(path).startswith("/data/"):
        return path
    return Path("/proc/1/root") / path.relative_to("/")


def select_apk_for_package(package_name, code_path):
    local_root = code_path_to_local_root(code_path)
    if local_root is None or not local_root.exists():
        return None, None, None, None
    if local_root.is_file() and local_root.suffix.lower() == ".apk":
        candidates = [local_root]
    else:
        candidates = sorted(local_root.rglob("*.apk"))

    fallback = None
    for apk_path in candidates:
        try:
            info, label, label_source = resolve_apk_label(str(apk_path))
        except Exception:
            continue
        if info.split:
            continue
        row = (str(apk_path), info, label, label_source)
        if fallback is None:
            fallback = row
        if str(info.package or "").strip() == package_name:
            return row
    return fallback if fallback is not None else (None, None, None, None)


def load_config(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
            return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def infer_scope(code_path, marker):
    normalized = str(code_path or "").strip().lower()
    if normalized.startswith(USER_CODE_PATH_PREFIXES):
        return "user"
    if normalized.startswith(SYSTEM_CODE_PATH_PREFIXES):
        return "system"
    if str(marker or "").strip() == "@system":
        return "system"
    return "unknown"


config = load_config(config_path)
selected_bypass_packages = set(str(x).strip() for x in config.get("bypass_packages", []) if str(x).strip())
package_meta, packages_xml_loaded, metadata_warnings = load_package_meta(packages_xml_path)

packages = []
with open(packages_list_path, "r", encoding="utf-8", errors="replace") as fh:
    for raw in fh:
        line = raw.strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) < 2:
            continue
        package_name = str(parts[0]).strip()
        try:
            uid = int(parts[1])
        except Exception:
            continue
        if not package_name or uid < 10000:
            continue
        marker = str(parts[-1]).strip() if parts else ""
        packages.append({"package": package_name, "uid": uid, "marker": marker})

uid_counts = {}
package_to_uid = {}
for row in packages:
    uid = int(row["uid"])
    uid_counts[uid] = uid_counts.get(uid, 0) + 1
    package_to_uid[str(row["package"])] = uid

selected_bypass_uids = set()
for package_name in selected_bypass_packages:
    uid = package_to_uid.get(package_name)
    if isinstance(uid, int):
        selected_bypass_uids.add(uid)

rows = []
label_resolved_package_count = 0
label_fallback_package_count = 0
for row in packages:
    package_name = str(row["package"])
    uid = int(row["uid"])
    meta = package_meta.get(package_name, {})
    code_path = str(meta.get("codePath", "") or meta.get("resourcePath", "") or "").strip()
    scope = infer_scope(code_path, row.get("marker"))
    apk_path, manifest_info, label, label_source = select_apk_for_package(package_name, code_path)
    display_name = str(label).strip() if label else package_name
    shared_count = int(uid_counts.get(uid, 1) or 1)
    if label:
        label_resolved_package_count += 1
    else:
        label_fallback_package_count += 1
    rows.append(
        {
            "package": package_name,
            "uid": uid,
            "scope": scope,
            "bypassed": uid in selected_bypass_uids,
            "tunneled": uid not in selected_bypass_uids,
            "shared_uid": shared_count > 1,
            "uid_package_count": shared_count,
            "label": str(label).strip() if label else None,
            "display_name": display_name,
            "label_source": label_source,
            "code_path": code_path,
            "apk_path": apk_path,
            "manifest_package": str(manifest_info.package).strip() if manifest_info and manifest_info.package else None,
        }
    )

rows.sort(key=lambda item: (0 if item.get("bypassed") else 1, str(item.get("display_name") or item.get("package") or "").lower(), str(item.get("package") or "").lower()))

payload = {
    "schema_version": 3,
    "generated_at": generated_at,
    "uid_source": uid_source,
    "package_count": len(rows),
    "packages_digest": hashlib.sha256(
        "\n".join(
            f"{row['package']}\t{row['uid']}\t{row.get('code_path') or ''}"
            for row in sorted(rows, key=lambda item: str(item.get('package') or ''))
        ).encode("utf-8")
    ).hexdigest(),
    "bypass_package_count": len([row for row in rows if row.get("bypassed")]),
    "tunneled_package_count": len([row for row in rows if row.get("tunneled")]),
    "user_package_count": len([row for row in rows if row.get("scope") == "user"]),
    "system_package_count": len([row for row in rows if row.get("scope") == "system"]),
    "unknown_package_count": len([row for row in rows if row.get("scope") == "unknown"]),
    "shared_uid_group_count": len([uid for uid, count in uid_counts.items() if count > 1]),
    "packages_xml_loaded": packages_xml_loaded,
    "metadata_enrichment_ok": packages_xml_loaded,
    "metadata_warnings": metadata_warnings,
    "label_resolved_package_count": label_resolved_package_count,
    "label_fallback_package_count": label_fallback_package_count,
    "packages": rows,
}

with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY
  local rc=$?
  if (( rc != 0 )); then
    rm -f -- "$packages_list_file" "$packages_xml_file" "$out_file"
    if [[ "$fatal" == "0" ]]; then
      return 1
    fi
    chroot_die "failed to build Apps Tunneling inventory"
  fi

  mv -f -- "$out_file" "$(chroot_tor_apps_inventory_file "$distro")"
  rm -f -- "$packages_list_file" "$packages_xml_file"
}

chroot_tor_apps_ensure() {
  local distro="$1"
  local apps_file
  apps_file="$(chroot_tor_apps_inventory_file "$distro")"
  if [[ ! -f "$apps_file" ]]; then
    chroot_tor_apps_refresh "$distro"
  fi
}

chroot_tor_apps_list_json() {
  local distro="$1"
  local scope_filter="${2:-all}"
  local mode_filter="${3:-all}"
  local query="${4:-}"
  local refresh_flag="${5:-0}"

  if [[ "$refresh_flag" == "1" ]]; then
    chroot_tor_apps_refresh "$distro"
  else
    chroot_tor_apps_ensure "$distro"
  fi

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$(chroot_tor_apps_inventory_file "$distro")" "$scope_filter" "$mode_filter" "$query" <<'PY'
import json
import sys

apps_path, scope_filter, mode_filter, query = sys.argv[1:5]
scope_filter = str(scope_filter or "all").strip().lower() or "all"
mode_filter = str(mode_filter or "all").strip().lower() or "all"
query = str(query or "").strip().lower()

try:
    with open(apps_path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
        if not isinstance(data, dict):
            data = {}
except Exception:
    data = {}

rows = []
for row in data.get("packages", []):
    if not isinstance(row, dict):
        continue
    scope = str(row.get("scope", "unknown") or "unknown").strip().lower() or "unknown"
    bypassed = bool(row.get("bypassed"))
    tunneled = not bypassed
    if scope_filter in {"user", "system", "unknown"} and scope != scope_filter:
        continue
    if mode_filter == "bypassed" and not bypassed:
        continue
    if mode_filter == "tunneled" and not tunneled:
        continue
    package = str(row.get("package", "") or "").strip()
    label = str(row.get("label", "") or "").strip()
    display_name = str(row.get("display_name", "") or package).strip() or package
    haystack = " ".join(part for part in [package.lower(), label.lower(), display_name.lower()] if part)
    if query and query not in haystack:
        continue
    row = dict(row)
    row["tunneled"] = tunneled
    rows.append(row)

rows.sort(
    key=lambda item: (
        0 if item.get("bypassed") else 1,
        str(item.get("display_name") or item.get("package") or "").lower(),
        str(item.get("package") or "").lower(),
    )
)

payload = dict(data)
payload["scope_filter"] = scope_filter
payload["mode_filter"] = mode_filter
payload["query"] = query
payload["package_count"] = len(rows)
payload["bypass_package_count"] = len([row for row in rows if bool(row.get("bypassed"))])
payload["tunneled_package_count"] = len([row for row in rows if not bool(row.get("bypassed"))])
payload["user_package_count"] = len([row for row in rows if str(row.get("scope", "")).lower() == "user"])
payload["system_package_count"] = len([row for row in rows if str(row.get("scope", "")).lower() == "system"])
payload["unknown_package_count"] = len([row for row in rows if str(row.get("scope", "")).lower() == "unknown"])
payload["shared_uid_group_count"] = len(
    {
        int(row.get("uid"))
        for row in rows
        if row.get("shared_uid") and str(row.get("uid", "")).strip().isdigit()
    }
)
payload["packages"] = rows
print(json.dumps(payload, indent=2, sort_keys=True))
PY
}

chroot_tor_apps_search_json() {
  local distro="$1"
  local query="${2:-}"
  local mode_filter="${3:-all}"
  local scope_filter="${4:-all}"
  local payload
  payload="$(chroot_tor_apps_list_json "$distro" "$scope_filter" "$mode_filter" "$query" 0)"
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$payload" <<'PY'
import json
import sys

try:
    payload = json.loads(sys.argv[1])
except Exception:
    payload = {}
rows = payload.get("packages", []) if isinstance(payload, dict) else []
print(json.dumps(rows, indent=2, sort_keys=True))
PY
}

chroot_tor_app_select_match() {
  local json_payload="$1"
  local prompt="${2:-Select app}"

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$json_payload" "$prompt" <<'PY'
import json
import sys

rows = json.loads(sys.argv[1])
prompt = sys.argv[2]

if not rows:
    sys.exit(2)

for idx, row in enumerate(rows, start=1):
    display_name = str(row.get("display_name") or row.get("label") or row.get("package") or "")
    package = str(row.get("package", "") or "")
    uid = row.get("uid")
    mode = "bypassed" if row.get("bypassed") else "tunneled"
    print(f"  {idx:2d}) {display_name:<28} pkg={package} uid={uid} mode={mode}", file=sys.stderr)

while True:
    try:
        pick = input(f"{prompt} (1-{len(rows)}, q=cancel): ")
    except EOFError:
        sys.exit(1)
    if pick in {"", "q", "Q"}:
        sys.exit(1)
    if pick.isdigit():
        idx = int(pick)
        if 1 <= idx <= len(rows):
            print(str(rows[idx - 1].get("package", "")))
            sys.exit(0)
    print("Invalid selection.", file=sys.stderr)
PY
}

chroot_tor_apps_describe_packages() {
  local distro="$1"
  shift || true
  (( $# > 0 )) || return 0

  chroot_tor_apps_ensure "$distro"
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$(chroot_tor_apps_inventory_file "$distro")" "$@" <<'PY'
import json
import sys

apps_path, *packages = sys.argv[1:]
try:
    with open(apps_path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {}

rows = data.get("packages", []) if isinstance(data, dict) else []
package_map = {}
for row in rows:
    if not isinstance(row, dict):
        continue
    package = str(row.get("package", "") or "").strip()
    if not package:
        continue
    display_name = str(row.get("display_name", "") or row.get("label", "") or package).strip() or package
    package_map[package] = display_name

seen = set()
descriptions = []
for package in packages:
    package = str(package or "").strip()
    if not package or package in seen:
        continue
    seen.add(package)
    descriptions.append(package_map.get(package, package))

print(", ".join(descriptions))
PY
}

chroot_tor_app_resolve_query() {
  local distro="$1"
  local query="$2"
  local resolution_json package match_count suggestions_text matches_json

  [[ -n "$query" ]] || chroot_die "app query is required"
  chroot_tor_apps_ensure "$distro"
  chroot_require_python
  resolution_json="$("$CHROOT_PYTHON_BIN" - "$(chroot_tor_apps_inventory_file "$distro")" "$query" <<'PY'
import difflib
import json
import sys

apps_path, query_text = sys.argv[1:3]
query_raw = str(query_text or "").strip()
query = query_raw.lower()

def normalize(text):
    return "".join(ch.lower() for ch in str(text or "") if ch.isalnum())

try:
    with open(apps_path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {}

rows = data.get("packages", []) if isinstance(data, dict) else []
query_norm = normalize(query_raw)

catalog = []
for row in rows:
    if not isinstance(row, dict):
        continue
    package = str(row.get("package", "") or "").strip()
    label = str(row.get("label", "") or "").strip()
    display_name = str(row.get("display_name", "") or package).strip() or package
    if not package:
        continue
    catalog.append(
        {
            "package": package,
            "display_name": display_name,
            "uid": row.get("uid"),
            "bypassed": bool(row.get("bypassed")),
            "package_l": package.lower(),
            "label_l": label.lower(),
            "display_l": display_name.lower(),
            "package_n": normalize(package),
            "label_n": normalize(label),
            "display_n": normalize(display_name),
        }
    )

def dedupe(items):
    seen = set()
    out = []
    for item in items:
        package = str(item.get("package", "") or "")
        if not package or package in seen:
            continue
        seen.add(package)
        out.append(
            {
                "package": package,
                "display_name": str(item.get("display_name", "") or package),
                "uid": item.get("uid"),
                "bypassed": bool(item.get("bypassed")),
            }
        )
    return out

exact_package = []
exact_name = []
exact_normalized = []
partial = []

for item in catalog:
    if item["package_l"] == query:
        exact_package.append(item)
        continue
    if query and (item["label_l"] == query or item["display_l"] == query):
        exact_name.append(item)
        continue
    if query_norm and query_norm in {item["package_n"], item["label_n"], item["display_n"]}:
        exact_normalized.append(item)
        continue
    haystack = " ".join(part for part in [item["package_l"], item["label_l"], item["display_l"]] if part)
    haystack_n = " ".join(part for part in [item["package_n"], item["label_n"], item["display_n"]] if part)
    if (query and query in haystack) or (query_norm and query_norm in haystack_n):
        partial.append(item)

exact_package = dedupe(exact_package)
exact_name = dedupe(exact_name)
exact_normalized = dedupe(exact_normalized)
partial = dedupe(partial)

resolved_package = ""
match_rows = []
if len(exact_package) == 1:
    resolved_package = str(exact_package[0].get("package", "") or "")
elif len(exact_name) == 1:
    resolved_package = str(exact_name[0].get("package", "") or "")
elif len(exact_normalized) == 1:
    resolved_package = str(exact_normalized[0].get("package", "") or "")
elif len(partial) == 1:
    resolved_package = str(partial[0].get("package", "") or "")
else:
    merged = []
    for group in [exact_package, exact_name, exact_normalized, partial]:
        merged.extend(group)
    match_rows = dedupe(merged)

scored = {}
for item in catalog:
    best = 0.0
    raw_fields = [item["package_l"], item["label_l"], item["display_l"]]
    norm_fields = [item["package_n"], item["label_n"], item["display_n"]]
    if query and any(field == query for field in raw_fields if field):
        best = max(best, 1.0)
    if query and any(field.startswith(query) for field in raw_fields if field):
        best = max(best, 0.93)
    if query and any(query in field for field in raw_fields if field):
        best = max(best, 0.88)
    if query_norm:
        if any(field == query_norm for field in norm_fields if field):
            best = max(best, 0.98)
        if any(field.startswith(query_norm) for field in norm_fields if field):
            best = max(best, 0.95)
        if any(query_norm in field for field in norm_fields if field):
            best = max(best, 0.90)
        for field in norm_fields:
            if not field:
                continue
            best = max(best, difflib.SequenceMatcher(None, query_norm, field).ratio())
    if best < 0.55:
        continue
    package = str(item.get("package", "") or "")
    current = scored.get(package)
    if current is None or best > current["score"]:
        scored[package] = {
            "score": best,
            "package": package,
            "display_name": str(item.get("display_name", "") or package),
        }

suggestions = [
    {"package": item["package"], "display_name": item["display_name"]}
    for item in sorted(
        scored.values(),
        key=lambda row: (-float(row.get("score", 0.0) or 0.0), str(row.get("display_name", "")).lower(), str(row.get("package", "")).lower()),
    )[:3]
]

print(
    json.dumps(
        {
            "resolved_package": resolved_package,
            "match_count": len(match_rows),
            "matches": match_rows,
            "suggestions": suggestions,
        },
        indent=2,
        sort_keys=True,
    )
)
PY
  )" || true

  package="$("$CHROOT_PYTHON_BIN" - "$resolution_json" <<'PY'
import json
import sys
try:
    data = json.loads(sys.argv[1])
except Exception:
    data = {}
print(str(data.get("resolved_package", "") or ""))
PY
)"
  if [[ -n "$package" ]]; then
    printf '%s\n' "$package"
    return 0
  fi

  match_count="$("$CHROOT_PYTHON_BIN" - "$resolution_json" <<'PY'
import json
import sys
try:
    data = json.loads(sys.argv[1])
except Exception:
    data = {}
print(int(data.get("match_count", 0) or 0))
PY
)"
  [[ "$match_count" =~ ^[0-9]+$ ]] || match_count=0

  suggestions_text="$("$CHROOT_PYTHON_BIN" - "$resolution_json" <<'PY'
import json
import sys
try:
    data = json.loads(sys.argv[1])
except Exception:
    data = {}
items = []
for row in data.get("suggestions", []):
    if not isinstance(row, dict):
        continue
    display_name = str(row.get("display_name", "") or row.get("package", "") or "").strip()
    if display_name:
        items.append(display_name)
print(", ".join(items))
PY
)"

  if (( match_count == 0 )); then
    if [[ -n "$suggestions_text" ]]; then
      chroot_die "no app matches query: $query; did you mean: $suggestions_text"
    fi
    chroot_die "no app matches query: $query"
  fi
  if [[ ! -t 0 ]]; then
    if [[ -n "$suggestions_text" ]]; then
      chroot_die "multiple apps match '$query'; be more specific. did you mean: $suggestions_text"
    fi
    chroot_die "multiple apps match '$query'; use a more specific label or an exact package id"
  fi

  matches_json="$("$CHROOT_PYTHON_BIN" - "$resolution_json" <<'PY'
import json
import sys
try:
    data = json.loads(sys.argv[1])
except Exception:
    data = {}
print(json.dumps(data.get("matches", []), indent=2, sort_keys=True))
PY
)"
  chroot_tor_app_select_match "$matches_json" "Select app"
}

chroot_tor_app_uid_group_packages() {
  local distro="$1"
  local package_name="$2"

  [[ -n "$package_name" ]] || chroot_die "package name is required"
  chroot_tor_apps_ensure "$distro"
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$(chroot_tor_apps_inventory_file "$distro")" "$package_name" <<'PY'
import json
import sys

apps_path, package_name = sys.argv[1:3]

try:
    with open(apps_path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {}

rows = [row for row in data.get("packages", []) if isinstance(row, dict)]
target_uid = None
for row in rows:
    if str(row.get("package", "")).strip() == package_name:
        try:
            target_uid = int(row.get("uid"))
        except Exception:
            target_uid = None
        break

if target_uid is None:
    raise SystemExit(f"failed to resolve app uid group for {package_name}")

packages = sorted(
    str(row.get("package", "")).strip()
    for row in rows
    if str(row.get("package", "")).strip() and str(row.get("uid", "")).strip().isdigit() and int(row.get("uid")) == target_uid
)
for package in packages:
    print(package)
PY
}

chroot_tor_apps_apply_selection_file() {
  local distro="$1"
  local selection_file="$2"
  [[ -f "$selection_file" ]] || chroot_die "selection file not found: $selection_file"

  chroot_tor_apps_ensure "$distro"
  chroot_tor_config_ensure_file "$distro"
  chroot_require_python

  local config_file tmp
  config_file="$(chroot_tor_config_file "$distro")"
  tmp="$config_file.$$.tmp"

  "$CHROOT_PYTHON_BIN" - "$(chroot_tor_apps_inventory_file "$distro")" "$config_file" "$selection_file" "$tmp" <<'PY'
import json
import sys

apps_path, config_path, selection_path, out_path = sys.argv[1:5]

try:
    with open(apps_path, "r", encoding="utf-8") as fh:
        apps = json.load(fh)
except Exception:
    apps = {}
try:
    with open(config_path, "r", encoding="utf-8") as fh:
        config = json.load(fh)
        if not isinstance(config, dict):
            config = {}
except Exception:
    config = {}
try:
    with open(selection_path, "r", encoding="utf-8") as fh:
        raw = json.load(fh)
except Exception:
    raw = []

if isinstance(raw, dict):
    source_rows = raw.get("bypassed_packages", raw.get("packages", []))
else:
    source_rows = raw
if not isinstance(source_rows, list):
    source_rows = []
selected = set(str(x).strip() for x in source_rows if str(x).strip())

package_to_uid = {}
uid_to_packages = {}
for row in apps.get("packages", []):
    if not isinstance(row, dict):
        continue
    package = str(row.get("package", "")).strip()
    if not package:
        continue
    try:
        uid = int(row.get("uid"))
    except Exception:
        continue
    package_to_uid[package] = uid
    uid_to_packages.setdefault(uid, set()).add(package)

expanded = set()
for package in selected:
    uid = package_to_uid.get(package)
    if uid is None:
        continue
    expanded.update(uid_to_packages.get(uid, {package}))

config["bypass_packages"] = sorted(expanded)

with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(config, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY
  mv -f -- "$tmp" "$config_file"
  chroot_tor_apps_refresh "$distro"
  chroot_tor_targets_invalidate "$distro"
}

chroot_tor_apps_set_mode_packages() {
  local distro="$1"
  local mode="$2"
  shift 2 || true
  (( $# > 0 )) || chroot_die "at least one package is required"
  case "$mode" in
    bypassed|tunneled) ;;
    *) chroot_die "invalid app mode: $mode (expected: bypassed|tunneled)" ;;
  esac

  chroot_tor_apps_ensure "$distro"
  chroot_tor_config_ensure_file "$distro"
  chroot_require_python

  local config_file tmp
  config_file="$(chroot_tor_config_file "$distro")"
  tmp="$config_file.$$.tmp"
  "$CHROOT_PYTHON_BIN" - "$(chroot_tor_apps_inventory_file "$distro")" "$config_file" "$tmp" "$mode" "$@" <<'PY'
import json
import sys

apps_path, config_path, out_path, mode, *packages = sys.argv[1:]
try:
    with open(apps_path, "r", encoding="utf-8") as fh:
        apps = json.load(fh)
except Exception:
    apps = {}
try:
    with open(config_path, "r", encoding="utf-8") as fh:
        config = json.load(fh)
        if not isinstance(config, dict):
            config = {}
except Exception:
    config = {}

selected = set(str(x).strip() for x in config.get("bypass_packages", []) if str(x).strip())
uid_to_packages = {}
package_to_uid = {}
for row in apps.get("packages", []):
    if not isinstance(row, dict):
        continue
    package = str(row.get("package", "")).strip()
    if not package:
        continue
    try:
        uid = int(row.get("uid"))
    except Exception:
        continue
    package_to_uid[package] = uid
    uid_to_packages.setdefault(uid, set()).add(package)

expanded = set()
for package in packages:
    package = str(package).strip()
    if not package:
        continue
    uid = package_to_uid.get(package)
    if uid is None:
        continue
    expanded.update(uid_to_packages.get(uid, {package}))

if mode == "bypassed":
    selected.update(expanded)
else:
    selected.difference_update(expanded)

config["bypass_packages"] = sorted(selected)
with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(config, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY
  mv -f -- "$tmp" "$config_file"
  chroot_tor_apps_refresh "$distro"
  chroot_tor_targets_invalidate "$distro"
}

chroot_tor_targets_generate() {
  local distro="$1"
  local include_host_uid="${2:-0}"
  local use_saved_bypass="${3:-0}"
  local out_file host_uid

  chroot_tor_apps_ensure "$distro"
  out_file="$CHROOT_TMP_DIR/tor-targets.$$.json"
  host_uid="$(chroot_host_user_uid 2>/dev/null || true)"

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$(chroot_tor_apps_inventory_file "$distro")" "$(chroot_tor_config_file "$distro")" "$out_file" "$host_uid" "$include_host_uid" "$use_saved_bypass" "$(chroot_now_ts)" <<'PY'
import json
import sys

apps_path, config_path, out_path, host_uid_text, include_host_text, use_saved_bypass_text, generated_at = sys.argv[1:8]
try:
    with open(apps_path, "r", encoding="utf-8") as fh:
        apps = json.load(fh)
except Exception:
    apps = {}
try:
    with open(config_path, "r", encoding="utf-8") as fh:
        config = json.load(fh)
except Exception:
    config = {}

host_uid = None
try:
    host_uid = int(host_uid_text)
except Exception:
    host_uid = None
include_host = include_host_text == "1"
use_saved_bypass = use_saved_bypass_text == "1"

selected_bypass_packages = set(str(x).strip() for x in config.get("bypass_packages", []) if str(x).strip())
rows = []
app_uids = set()
target_uids = set()
bypass_uids = set()
selected_bypass_uids = set()

for row in apps.get("packages", []):
    if not isinstance(row, dict):
        continue
    package = str(row.get("package", "")).strip()
    if package not in selected_bypass_packages:
        continue
    try:
        uid = int(row.get("uid"))
    except Exception:
        continue
    if uid > 0:
        selected_bypass_uids.add(uid)

for row in apps.get("packages", []):
    if not isinstance(row, dict):
        continue
    package = str(row.get("package", "")).strip()
    try:
        uid = int(row.get("uid"))
    except Exception:
        continue
    if uid <= 0:
        continue
    bypassed = uid in selected_bypass_uids
    rows.append({"package": package, "uid": uid, "bypassed": bypassed})
    app_uids.add(uid)
    if bypassed:
        bypass_uids.add(uid)
    if use_saved_bypass and bypassed:
        continue
    target_uids.add(uid)

if include_host and isinstance(host_uid, int) and host_uid > 0:
    target_uids.add(host_uid)

ordered_target_uids = sorted(target_uids)
uid_ranges = []
for uid in ordered_target_uids:
    if not uid_ranges or uid != uid_ranges[-1]["end"] + 1:
        uid_ranges.append({"start": uid, "end": uid})
    else:
        uid_ranges[-1]["end"] = uid

payload = {
    "schema_version": 1,
    "generated_at": generated_at,
    "uid_source": str(apps.get("uid_source", "") or ""),
    "source_apps_generated_at": str(apps.get("generated_at", "") or ""),
    "source_package_count": int(apps.get("package_count", 0) or 0),
    "source_packages_digest": str(apps.get("packages_digest", "") or ""),
    "packages": rows,
    "app_uids": sorted(app_uids),
    "target_uids": ordered_target_uids,
    "uid_ranges": uid_ranges,
    "termux_uid": host_uid,
    "termux_uid_included": bool(include_host and isinstance(host_uid, int) and host_uid in target_uids),
    "root_uid_included": False,
    "app_uid_count": len(app_uids),
    "target_uid_count": len(ordered_target_uids),
    "uid_range_count": len(uid_ranges),
    "bypass_package_count": len([row for row in rows if row["bypassed"]]),
    "bypass_uid_count": len(selected_bypass_uids),
    "configured_bypass_applied": use_saved_bypass,
}

with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY

  mv -f -- "$out_file" "$(chroot_tor_targets_file "$distro")"

  local app_count
  app_count="$(chroot_tor_targets_summary_tsv "$distro" | awk -F'\t' '{print $1}')"
  [[ "$app_count" =~ ^[0-9]+$ ]] || app_count=0
  (( app_count > 0 )) || chroot_die "tor target generation found no Android app UIDs"
}

chroot_tor_targets_summary_tsv() {
  local distro="$1"
  local targets_file
  targets_file="$(chroot_tor_targets_file "$distro")"
  [[ -f "$targets_file" ]] || {
    printf '0\t0\t0\t0\t\t0\n'
    return 0
  }

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$targets_file" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {}

print(
    "\t".join(
        [
            str(int(data.get("app_uid_count", 0) or 0)),
            str(int(data.get("target_uid_count", 0) or 0)),
            str(int(data.get("uid_range_count", 0) or 0)),
            "1" if data.get("termux_uid_included") else "0",
            str(data.get("uid_source", "") or ""),
            str(int(data.get("bypass_package_count", 0) or 0)),
        ]
    )
)
PY
}

chroot_tor_target_uids() {
  local distro="$1"
  local targets_file
  targets_file="$(chroot_tor_targets_file "$distro")"
  [[ -f "$targets_file" ]] || return 0

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$targets_file" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {}

for uid in data.get("target_uids", []):
    try:
        parsed = int(uid)
    except Exception:
        continue
    if parsed > 0:
        print(parsed)
PY
}

chroot_tor_target_uid_specs() {
  local distro="$1"
  local targets_file
  targets_file="$(chroot_tor_targets_file "$distro")"
  [[ -f "$targets_file" ]] || return 0

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$targets_file" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {}

printed = False
for row in data.get("uid_ranges", []):
    if not isinstance(row, dict):
        continue
    try:
        start = int(row.get("start"))
        end = int(row.get("end"))
    except Exception:
        continue
    if start <= 0 or end < start:
        continue
    print(str(start) if start == end else f"{start}-{end}")
    printed = True

if printed:
    sys.exit(0)

for uid in data.get("target_uids", []):
    try:
        parsed = int(uid)
    except Exception:
        continue
    if parsed > 0:
        print(parsed)
PY
}

chroot_tor_targets_invalidate() {
  local distro="$1"
  rm -f -- "$(chroot_tor_targets_file "$distro")"
}
