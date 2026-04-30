chroot_session_list_json() {
  local distro="$1"
  local sf lock_file device_tz
  sf="$(chroot_distro_session_file "$distro")"
  lock_file="$(chroot_session_lock_file "$distro")"
  [[ -f "$sf" ]] || {
    printf '[]\n'
    return 0
  }
  device_tz="$(chroot_device_timezone_name 2>/dev/null || printf 'UTC\n')"

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$sf" "$lock_file" "$device_tz" <<'PY'
import json
import io
import os
import struct
import sys
from datetime import datetime, timezone

try:
    from zoneinfo import ZoneInfo
except Exception:
    ZoneInfo = None

try:
    import fcntl
except Exception:
    fcntl = None

sf, lock_file, device_tz = sys.argv[1:4]

def pid_is_live(pid):
    try:
        os.kill(pid, 0)
        return True
    except PermissionError:
        return True
    except OSError:
        return False

def pid_starttime(pid):
    try:
        with open(f"/proc/{pid}/stat", "r", encoding="utf-8") as fh:
            parts = fh.read().split()
        if len(parts) >= 22:
            return int(parts[21])
    except Exception:
        return None
    return None

def same_process(pid, expected_start):
    if not isinstance(pid, int) or pid <= 0:
        return False
    if not pid_is_live(pid):
        return False
    if not isinstance(expected_start, int):
        return False
    current = pid_starttime(pid)
    if current is None:
        return False
    return current == expected_start

def same_process_group(pgid, expected_start):
    if not isinstance(pgid, int) or pgid <= 0:
        return False
    if not pid_is_live(pgid):
        return False
    if not isinstance(expected_start, int):
        return False
    current = pid_starttime(pgid)
    if current is None:
        return False
    return current == expected_start

def sanitize(text):
    value = str(text or "")
    value = value.replace("\t", " ").replace("\r", " ").replace("\n", " ").strip()
    return value

def resolve_zone_from_android_tzdata(name):
    if ZoneInfo is None:
        return None
    tzdata_path = "/system/usr/share/zoneinfo/tzdata"
    try:
        with open(tzdata_path, "rb") as fh:
            blob = fh.read()
        if len(blob) < 24 or not blob.startswith(b"tzdata"):
            return None
        index_offset, data_offset, _zonetab_offset = struct.unpack(">III", blob[12:24])
        if data_offset <= index_offset or index_offset < 24:
            return None
        entry_size = 52
        for offset in range(index_offset, data_offset, entry_size):
            chunk = blob[offset:offset + entry_size]
            if len(chunk) < entry_size:
                continue
            key = chunk[:40].split(b"\x00", 1)[0].decode("utf-8", "ignore")
            if key != name:
                continue
            rel_offset, length, _raw_utc = struct.unpack(">III", chunk[40:52])
            start = data_offset + rel_offset
            end = start + length
            if length <= 0 or start < data_offset or end > len(blob):
                return None
            return ZoneInfo.from_file(io.BytesIO(blob[start:end]), key=name)
    except Exception:
        return None
    return None

def resolve_zone(name):
    text = sanitize(name)
    if text and ZoneInfo is not None:
        try:
            return ZoneInfo(text), text
        except Exception:
            zone = resolve_zone_from_android_tzdata(text)
            if zone is not None:
                return zone, text
    return timezone.utc, "UTC"

local_zone, local_zone_name = resolve_zone(device_tz)

def format_started_local(value):
    text = sanitize(value)
    if not text or text == "-":
        return "-"
    try:
        normalized = text[:-1] + "+00:00" if text.endswith("Z") else text
        parsed = datetime.fromisoformat(normalized)
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return parsed.astimezone(local_zone).strftime("%Y-%m-%d %H:%M:%S %z")
    except Exception:
        return text

with open(lock_file, "a+", encoding="utf-8") as lock_fh:
    if fcntl is not None:
        fcntl.flock(lock_fh.fileno(), fcntl.LOCK_SH)

    try:
        with open(sf, "r", encoding="utf-8") as fh:
            rows = json.load(fh)
        if not isinstance(rows, list):
            rows = []
    except Exception:
        rows = []

    out = []
    for row in rows:
        sid = str(row.get("session_id", "")).strip()
        if not sid:
            continue
        mode = str(row.get("mode", "")).strip() or "-"
        started = str(row.get("started_at", "")).strip() or "-"
        started_local = format_started_local(started)
        cmd = str(row.get("command", "")).strip() or "-"
        pid = row.get("pid")
        expected_start = row.get("pid_starttime")
        pgid = row.get("pgid")
        expected_group_start = row.get("pgid_starttime")

        pid_out = None
        pgid_out = None
        state = "no-pid"
        if same_process_group(pgid, expected_group_start):
            if isinstance(pid, int) and pid > 0:
                pid_out = pid
            pgid_out = pgid
            state = "live-group"
        elif isinstance(pid, int) and pid > 0:
            pid_out = pid
            if same_process(pid, expected_start):
                state = "live"
            elif pid_is_live(pid):
                state = "live-unknown-start"
            else:
                state = "dead"

        out.append(
            {
                "session_id": sid,
                "pid": pid_out,
                "pgid": pgid_out,
                "mode": mode,
                "started_at": started,
                "started_local": started_local,
                "timezone": local_zone_name,
                "state": state,
                "command": cmd,
            }
        )

print(json.dumps(out))
PY
}
