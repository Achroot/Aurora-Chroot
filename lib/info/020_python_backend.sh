chroot_info_python_emit() {
  cat <<'PY'
import json
import os
import platform
import re
import shutil
import socket
import struct
import subprocess
import sys
import textwrap
import time
from datetime import datetime, timezone
from pathlib import Path


def env_list(name, fallback):
    raw = str(os.environ.get(name, "") or "").strip()
    if not raw:
        return list(fallback)
    rows = [line.strip() for line in raw.splitlines() if line.strip()]
    return rows or list(fallback)


SCHEMA_VERSION = int(os.environ.get("CHROOT_INFO_SCHEMA_VERSION", "1") or "1")
SECTION_ORDER = env_list(
    "CHROOT_INFO_SECTION_IDS",
    ["overview", "device", "resources", "storage", "distro", "network", "aurora", "hint"],
)
SLOW_SECTIONS = set(env_list("CHROOT_INFO_SLOW_SECTION_IDS", ["storage", "distro"]))


def utc_now_iso():
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def utc_from_epoch(epoch):
    try:
        value = float(epoch)
    except Exception:
        return ""
    return datetime.fromtimestamp(value, tz=timezone.utc).strftime("%Y-%m-%d %H:%M UTC")


def load_json(path, default=None):
    if default is None:
        default = {}
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        return data if isinstance(data, type(default)) else default
    except Exception:
        return default


def read_text(path):
    try:
        return Path(path).read_text(encoding="utf-8", errors="replace").strip()
    except Exception:
        return ""


def cmd_exists(name):
    return bool(resolve_cmd(name))


def resolve_cmd(name):
    text = str(name or "").strip()
    if not text:
        return []
    if os.path.isabs(text):
        return [text] if os.access(text, os.X_OK) else []
    found = shutil.which(text)
    if found:
        return [found]

    candidates = {
        "getprop": [("/system/bin/getprop",)],
        "wm": [("/system/bin/wm",)],
        "cmd": [("/system/bin/cmd",)],
        "dumpsys": [("/system/bin/dumpsys",)],
        "getenforce": [("/system/bin/getenforce",)],
        "ip": [
            ("/system/bin/ip",),
            ("/vendor/bin/ip",),
            ("/system/bin/toybox", "ip"),
            ("/system/bin/busybox", "ip"),
        ],
    }
    for entry in candidates.get(text, []):
        path = entry[0]
        if os.access(path, os.X_OK):
            return list(entry)
    return []


def resolve_cmd_argv(cmd):
    if not cmd:
        return []
    head = str(cmd[0] or "").strip()
    if not head:
        return []
    if os.path.isabs(head):
        return [str(item) for item in cmd]
    resolved = resolve_cmd(head)
    if not resolved:
        return []
    return resolved + [str(item) for item in cmd[1:]]


def run_cmd(cmd, timeout=2.5):
    argv = resolve_cmd_argv(cmd)
    if not argv:
        return ""
    try:
        proc = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
    except Exception:
        return ""
    out = (proc.stdout or "").strip()
    if out:
        return out
    return (proc.stderr or "").strip()


def getprop(key):
    return run_cmd(["getprop", key], timeout=1.5).strip()


def first_prop(*keys):
    for key in keys:
        value = getprop(key)
        if value:
            return value
    return ""


def env_bool(name):
    value = str(os.environ.get(name, "") or "").strip().lower()
    return value in {"1", "true", "yes", "on"}


def clean_text(value):
    return " ".join(str(value or "").replace("\t", " ").split())


def first_nonempty(*values):
    for value in values:
        text = str(value or "").strip()
        if text:
            return text
    return ""


def human_bytes(num):
    try:
        value = float(num)
    except Exception:
        return "0B"
    if value < 0:
        value = 0.0
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


def human_duration(seconds):
    try:
        total = int(float(seconds))
    except Exception:
        total = 0
    if total <= 0:
        return "0m"
    days, rem = divmod(total, 86400)
    hours, rem = divmod(rem, 3600)
    minutes, _ = divmod(rem, 60)
    parts = []
    if days:
        parts.append(f"{days}d")
    if hours or days:
        parts.append(f"{hours:02d}h" if days else f"{hours}h")
    parts.append(f"{minutes:02d}m" if days or hours else f"{minutes}m")
    return " ".join(parts[:3])


def normalize_temp(raw):
    try:
        value = float(str(raw).strip())
    except Exception:
        return None
    abs_value = abs(value)
    if abs_value >= 100000:
        value /= 1000.0
    elif abs_value >= 10000:
        value /= 1000.0
    elif abs_value >= 1000:
        value /= 100.0
    elif abs_value >= 200:
        value /= 10.0
    return value


def normalize_freq(raw):
    try:
        value = int(str(raw).strip())
    except Exception:
        return None
    if value <= 0:
        return None
    if value > 100000:
        return value / 1000.0
    return float(value)


def read_kv_file(path):
    out = {}
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if "=" not in line:
                    continue
                key, value = line.rstrip("\n").split("=", 1)
                out[str(key).strip()] = str(value).strip().strip('"')
    except Exception:
        return {}
    return out


def pid_starttime(pid):
    try:
        with open(f"/proc/{int(pid)}/stat", "r", encoding="utf-8") as fh:
            parts = fh.read().split()
        if len(parts) >= 22:
            return int(parts[21])
    except Exception:
        return None
    return None


def pid_is_live(pid):
    try:
        os.kill(int(pid), 0)
        return True
    except PermissionError:
        return True
    except Exception:
        return False


def session_is_live(row):
    try:
        pid = int(row.get("pid"))
    except Exception:
        return False
    if pid <= 0 or not pid_is_live(pid):
        return False
    expected = row.get("pid_starttime")
    if expected in (None, ""):
        return True
    try:
        expected = int(expected)
    except Exception:
        return True
    current = pid_starttime(pid)
    return current is not None and current == expected


def read_mount_points():
    mount_points = set()
    try:
        with open("/proc/self/mountinfo", "r", encoding="utf-8") as fh:
            for line in fh:
                parts = line.split()
                if len(parts) >= 5:
                    mount_points.add(os.path.normpath(parts[4]))
    except Exception:
        pass
    return mount_points


def df_stats(path):
    path = str(path or "").strip()
    if not path:
        return {}
    out = run_cmd(["df", "-kP", path], timeout=2.0)
    lines = [line for line in out.splitlines() if line.strip()]
    if len(lines) < 2:
        return {}
    parts = lines[-1].split()
    if len(parts) < 6:
        return {}
    try:
        total_kb = int(parts[1])
        used_kb = int(parts[2])
        avail_kb = int(parts[3])
        percent = str(parts[4]).strip()
        mountpoint = str(parts[5]).strip()
    except Exception:
        return {}
    return {
        "path": path,
        "mountpoint": mountpoint,
        "total_bytes": total_kb * 1024,
        "used_bytes": used_kb * 1024,
        "free_bytes": avail_kb * 1024,
        "used_percent": percent,
    }


def path_has_nested_mounts(path, mount_points):
    base = os.path.normpath(str(path or "").strip())
    if not base:
        return False
    prefix = base + os.sep
    for mount_point in mount_points or ():
        target = os.path.normpath(str(mount_point or "").strip())
        if not target or target == base:
            continue
        if target.startswith(prefix):
            return True
    return False


def du_bytes_walk(path, mount_points=None):
    root = os.path.normpath(str(path or "").strip())
    if not root or not os.path.exists(root):
        return 0
    try:
        if os.path.isfile(root):
            return max(0, os.path.getsize(root))
    except OSError:
        return 0

    skipped_mounts = {os.path.normpath(str(item or "").strip()) for item in (mount_points or set()) if item}
    skipped_mounts.discard(root)
    visited = set()

    def scan_dir(dir_path):
        total = 0
        try:
            st = os.lstat(dir_path)
        except OSError:
            return 0
        key = (int(st.st_dev), int(st.st_ino))
        if key in visited:
            return 0
        visited.add(key)
        try:
            with os.scandir(dir_path) as it:
                for entry in it:
                    entry_path = os.path.normpath(entry.path)
                    try:
                        if entry.is_symlink():
                            continue
                        if entry.is_dir(follow_symlinks=False):
                            if entry_path in skipped_mounts:
                                continue
                            total += scan_dir(entry.path)
                            continue
                        if entry.is_file(follow_symlinks=False):
                            total += max(0, int(entry.stat(follow_symlinks=False).st_size))
                    except OSError:
                        continue
        except OSError:
            return total
        return total

    return scan_dir(root)


def du_bytes(path, mount_points=None):
    path = str(path or "").strip()
    if not path or not os.path.exists(path):
        return 0
    normalized_mounts = {os.path.normpath(str(item or "").strip()) for item in (mount_points or set()) if item}
    if cmd_exists("du") and not path_has_nested_mounts(path, normalized_mounts):
        out = run_cmd(["du", "-sk", path], timeout=120.0)
        first = str(out).splitlines()[0].split()[0] if out.splitlines() else ""
        if first.isdigit():
            return int(first) * 1024
    return du_bytes_walk(path, normalized_mounts)


def list_installed_distros(rootfs_dir):
    out = []
    try:
        for entry in sorted(os.listdir(rootfs_dir)):
            full = os.path.join(rootfs_dir, entry)
            if os.path.isdir(full):
                out.append(entry)
    except Exception:
        return []
    return out


def service_dir_for(state_root, distro):
    return os.path.join(state_root, distro, "services")


def desktop_config_for(state_root, distro):
    return os.path.join(state_root, distro, "desktop", "config.json")


def tor_status_for(state_root, distro):
    return os.path.join(state_root, distro, "tor", "status.json")


def distro_state_for(state_root, distro):
    return os.path.join(state_root, distro, "state.json")


def distro_sessions_for(state_root, distro):
    return os.path.join(state_root, distro, "sessions", "current.json")


def distro_mounts_for(state_root, distro):
    return os.path.join(state_root, distro, "mounts", "current.log")


def rootfs_dir_for(rootfs_root, distro):
    return os.path.join(rootfs_root, distro)


def distro_state_dir_for(state_root, distro):
    return os.path.join(state_root, distro)


def read_sessions(state_root, distro):
    rows = load_json(distro_sessions_for(state_root, distro), default=[])
    if not isinstance(rows, list):
        return []
    return [row for row in rows if isinstance(row, dict)]


def count_active_mounts(state_root, distro, mount_points):
    log_path = distro_mounts_for(state_root, distro)
    targets = []
    try:
        with open(log_path, "r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                parts = line.rstrip("\n").split("\t")
                if len(parts) >= 2 and parts[1].strip():
                    targets.append(parts[1].strip())
    except Exception:
        return (0, 0)
    active = sum(1 for target in targets if target in mount_points)
    return active, len(targets)


def count_rootfs_mounts(rootfs_root, distro, mount_points):
    base = rootfs_dir_for(rootfs_root, distro)
    count = 0
    for mount_point in mount_points:
        if mount_point == base or mount_point.startswith(base + "/"):
            count += 1
    return count


def read_service_rows(state_root, distro, sessions):
    sdir = service_dir_for(state_root, distro)
    rows = []
    session_by_id = {str(row.get("session_id", "") or ""): row for row in sessions}
    try:
        names = sorted(name for name in os.listdir(sdir) if name.endswith(".json"))
    except Exception:
        names = []
    for filename in names:
        name = filename[:-5]
        data = load_json(os.path.join(sdir, filename), default={})
        row = {
            "name": name,
            "command": str(data.get("command", "") or ""),
            "running": False,
            "pid": "",
        }
        sess = session_by_id.get(f"svc-{name}")
        if isinstance(sess, dict) and session_is_live(sess):
            row["running"] = True
            try:
                row["pid"] = str(int(sess.get("pid")))
            except Exception:
                row["pid"] = ""
        rows.append(row)
    return rows


def collect_rootfs_size_map(rootfs_root, mount_points=None):
    size_map = {}
    total = 0
    normalized_mounts = mount_points if mount_points is not None else read_mount_points()
    for distro in list_installed_distros(rootfs_root):
        rootfs_bytes = du_bytes(rootfs_dir_for(rootfs_root, distro), mount_points=normalized_mounts)
        size_map[distro] = {
            "rootfs_bytes": rootfs_bytes,
            "rootfs_text": human_bytes(rootfs_bytes),
        }
        total += rootfs_bytes
    return size_map, total


def read_distro_rows(rootfs_root, state_root, include_sizes=False, rootfs_size_map=None):
    mount_points = read_mount_points()
    distros = []
    for distro in list_installed_distros(rootfs_root):
        state_doc = load_json(distro_state_for(state_root, distro), default={})
        sessions = read_sessions(state_root, distro)
        active_sessions = sum(1 for row in sessions if session_is_live(row))
        service_rows = read_service_rows(state_root, distro, sessions)
        active_services = sum(1 for row in service_rows if row.get("running"))
        desktop_doc = load_json(desktop_config_for(state_root, distro), default={})
        tor_doc = load_json(tor_status_for(state_root, distro), default={})
        active_mounts, _mount_entries = count_active_mounts(state_root, distro, mount_points)
        rootfs_mounts = count_rootfs_mounts(rootfs_root, distro, mount_points)
        desktop_profile = ""
        if bool(desktop_doc.get("installed")):
            desktop_profile = str(desktop_doc.get("profile_id", "") or "").strip() or "installed"
        row = {
            "distro": distro,
            "release": str(state_doc.get("release", "") or "").strip() or "n/a",
            "mounted": bool(active_mounts > 0 or rootfs_mounts > 0),
            "sessions": active_sessions,
            "services": active_services,
            "desktop": desktop_profile or "no",
            "tor": bool(tor_doc.get("enabled")),
            "rootfs_bytes": None,
            "rootfs_text": "...",
        }
        if include_sizes:
            size_doc = (rootfs_size_map or {}).get(distro, {})
            rootfs_bytes = int(size_doc.get("rootfs_bytes", 0) or 0)
            row["rootfs_bytes"] = rootfs_bytes
            row["rootfs_text"] = str(size_doc.get("rootfs_text", "") or human_bytes(rootfs_bytes))
        distros.append(row)
    return distros


def detect_battery():
    base = Path("/sys/class/power_supply")
    if not base.is_dir():
        return {}
    battery_path = None
    charging = []
    try:
        entries = sorted(base.iterdir())
    except Exception:
        return {}
    for entry in entries:
        capacity = entry / "capacity"
        stype = read_text(entry / "type")
        if battery_path is None and (capacity.exists() or stype.lower() == "battery"):
            battery_path = entry
        online = read_text(entry / "online")
        if online == "1":
            charging.append(entry.name)
    if battery_path is None:
        return {}
    status = clean_text(read_text(battery_path / "status"))
    capacity_text = read_text(battery_path / "capacity")
    level = None
    if capacity_text.isdigit():
        level = int(capacity_text)
    temp = normalize_temp(read_text(battery_path / "temp"))
    health = clean_text(read_text(battery_path / "health"))
    result = {
        "level": level,
        "status": status or ("charging" if charging else ""),
        "health": health,
        "temperature_c": temp,
        "present": True,
    }
    return result


def detect_thermal():
    base = Path("/sys/class/thermal")
    if not base.is_dir():
        return {}
    hottest = None
    hottest_name = ""
    try:
        entries = sorted(base.glob("thermal_zone*"))
    except Exception:
        return {}
    for entry in entries:
        temp = normalize_temp(read_text(entry / "temp"))
        if temp is None:
            continue
        if hottest is None or temp > hottest:
            hottest = temp
            hottest_name = clean_text(read_text(entry / "type")) or entry.name
    if hottest is None:
        return {}
    if hottest < 40.0:
        state = "normal"
    elif hottest < 45.0:
        state = "warm"
    elif hottest < 50.0:
        state = "hot"
    else:
        state = "critical"
    return {
        "max_temp_c": hottest,
        "source": hottest_name,
        "state": state,
    }


def detect_ram():
    out = {"total_bytes": 0, "available_bytes": 0, "swap_total_bytes": 0, "swap_free_bytes": 0}
    try:
        with open("/proc/meminfo", "r", encoding="utf-8") as fh:
            for line in fh:
                if ":" not in line:
                    continue
                key, value = line.split(":", 1)
                value = value.strip().split()[0]
                if not value.isdigit():
                    continue
                kb = int(value)
                if key == "MemTotal":
                    out["total_bytes"] = kb * 1024
                elif key == "MemAvailable":
                    out["available_bytes"] = kb * 1024
                elif key == "SwapTotal":
                    out["swap_total_bytes"] = kb * 1024
                elif key == "SwapFree":
                    out["swap_free_bytes"] = kb * 1024
    except Exception:
        return out
    out["used_bytes"] = max(0, out["total_bytes"] - out["available_bytes"])
    out["swap_used_bytes"] = max(0, out["swap_total_bytes"] - out["swap_free_bytes"])
    return out


def detect_zram():
    base = Path("/sys/block")
    if not base.is_dir():
        return {}
    total = 0
    used = 0
    try:
        entries = sorted(base.glob("zram*"))
    except Exception:
        return {}
    for entry in entries:
        size = read_text(entry / "disksize")
        mm = read_text(entry / "mm_stat")
        try:
            total += int(size or "0")
        except Exception:
            pass
        if mm:
            parts = mm.split()
            if len(parts) >= 1 and parts[0].isdigit():
                try:
                    used += int(parts[0])
                except Exception:
                    pass
    if total <= 0 and used <= 0:
        return {}
    return {"total_bytes": total, "used_bytes": used}


def detect_load():
    try:
        values = os.getloadavg()
        return [round(values[0], 2), round(values[1], 2), round(values[2], 2)]
    except Exception:
        text = read_text("/proc/loadavg")
        parts = text.split()
        out = []
        for idx in range(3):
            try:
                out.append(round(float(parts[idx]), 2))
            except Exception:
                out.append(0.0)
        return out


def detect_cpu():
    cpu_base = Path("/sys/devices/system/cpu")
    try:
        cpu_dirs = sorted(path for path in cpu_base.glob("cpu[0-9]*") if path.is_dir())
    except Exception:
        cpu_dirs = []
    core_count = len(cpu_dirs) or (os.cpu_count() or 0)
    online = 0
    governors = []
    freqs = []
    for entry in cpu_dirs:
        online_text = read_text(entry / "online")
        if online_text in {"", "1"}:
            online += 1
        gov = clean_text(read_text(entry / "cpufreq" / "scaling_governor"))
        if gov:
            governors.append(gov)
        freq = normalize_freq(read_text(entry / "cpufreq" / "scaling_cur_freq"))
        if freq is not None:
            freqs.append(freq)
    if online == 0:
        online = core_count
    governor = ""
    if governors:
        common = {}
        for gov in governors:
            common[gov] = common.get(gov, 0) + 1
        governor = sorted(common.items(), key=lambda item: (-item[1], item[0]))[0][0]
    freq_summary = ""
    if freqs:
        groups = {}
        for freq in freqs:
            rounded = round(freq)
            groups[rounded] = groups.get(rounded, 0) + 1
        parts = []
        for rounded, count in sorted(groups.items()):
            ghz = rounded / 1000.0
            parts.append(f"{count} x {ghz:.2f}GHz")
        freq_summary = ", ".join(parts)
    model = ""
    try:
        with open("/proc/cpuinfo", "r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if ":" not in line:
                    continue
                key, value = line.split(":", 1)
                if key.strip().lower() in {"model name", "hardware", "processor"}:
                    model = clean_text(value)
                    if model:
                        break
    except Exception:
        model = ""
    return {
        "core_count": core_count,
        "online_cores": online,
        "governor": governor,
        "freq_summary": freq_summary,
        "model": model,
    }


def detect_display():
    def parse_resolution(text):
        patterns = [
            r"Physical size:\s*([0-9]+x[0-9]+)",
            r"\bcur=([0-9]+x[0-9]+)\b",
            r"\binit=([0-9]+x[0-9]+)\b",
            r"\b([0-9]{3,5}x[0-9]{3,5})\b",
        ]
        raw = str(text or "")
        for pattern in patterns:
            match = re.search(pattern, raw)
            if match:
                return match.group(1)
        return ""

    resolution = ""
    density = ""
    for cmd in (["wm", "size"], ["cmd", "window", "size"], ["dumpsys", "window", "displays"], ["dumpsys", "display"]):
        if resolution:
            break
        resolution = parse_resolution(run_cmd(cmd, timeout=2.0))
    for path in (
        "/sys/class/graphics/fb0/virtual_size",
        "/sys/class/graphics/fb0/modes",
    ):
        if resolution:
            break
        text = read_text(path)
        if path.endswith("virtual_size"):
            match = re.search(r"([0-9]+),([0-9]+)", text)
            if match:
                resolution = f"{match.group(1)}x{match.group(2)}"
        else:
            resolution = parse_resolution(text.replace("U:", ""))
    for cmd in (["wm", "density"], ["cmd", "window", "density"]):
        if density:
            break
        density_out = run_cmd(cmd, timeout=1.5)
        match = re.search(r"Physical density:\s*([0-9]+)", density_out)
        if match:
            density = match.group(1)
    if not density:
        density = first_nonempty(
            getprop("ro.sf.lcd_density"),
            getprop("qemu.sf.lcd_density"),
        )
    return {"resolution": resolution, "density": density}


def detect_network():
    def is_ip_literal(value):
        text = str(value or "").strip()
        if not text:
            return False
        for family in (socket.AF_INET, socket.AF_INET6):
            try:
                socket.inet_pton(family, text)
                return True
            except OSError:
                continue
        return False

    def append_dns_values(values, raw):
        text = str(raw or "").strip()
        if not text:
            return
        parts = re.split(r"[,\s]+", text)
        for item in parts:
            value = item.strip()
            if not is_ip_literal(value):
                continue
            if value not in values:
                values.append(value)

    def append_dns_from_file(values, path):
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    match = re.match(r"^\s*nameserver\s+(\S+)", line)
                    if match:
                        append_dns_values(values, match.group(1))
        except Exception:
            return

    def append_dns_from_connectivity_dump(values):
        dump = run_cmd(["dumpsys", "connectivity"], timeout=3.5)
        if not dump:
            return
        patterns = [
            r"\bDnsAddresses:\s*\[([^\]]+)\]",
            r"\bdnsServers=\[([^\]]+)\]",
            r"\bDNS servers:\s*\[([^\]]+)\]",
        ]
        for pattern in patterns:
            for match in re.finditer(pattern, dump, flags=re.IGNORECASE):
                append_dns_values(values, match.group(1).replace("/", " "))

    def active_interface_fallback():
        base = Path("/sys/class/net")
        if not base.is_dir():
            return ""
        preferred = []
        others = []
        try:
            entries = sorted(base.iterdir())
        except Exception:
            return ""
        for entry in entries:
            name = entry.name
            if name == "lo":
                continue
            operstate = read_text(entry / "operstate").lower()
            carrier = read_text(entry / "carrier")
            if operstate not in {"up", "unknown"} and carrier not in {"1", ""}:
                continue
            if name.startswith(("wlan", "eth", "rmnet", "ccmni", "usb")):
                preferred.append(name)
            else:
                others.append(name)
        rows = preferred or others
        return rows[0] if rows else ""

    def detect_local_ipv4():
        for host in ("1.1.1.1", "8.8.8.8", "9.9.9.9"):
            try:
                sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                try:
                    sock.connect((host, 53))
                    value = sock.getsockname()[0]
                    if value:
                        return value
                finally:
                    sock.close()
            except Exception:
                continue
        return ""

    def read_default_route_v4():
        best = None
        try:
            with open("/proc/net/route", "r", encoding="utf-8", errors="replace") as fh:
                next(fh, None)
                for line in fh:
                    parts = line.split()
                    if len(parts) < 8:
                        continue
                    iface, destination, gateway, flags = parts[0], parts[1], parts[2], parts[3]
                    if destination != "00000000":
                        continue
                    try:
                        flags_value = int(flags, 16)
                    except Exception:
                        continue
                    if (flags_value & 0x1) == 0:
                        continue
                    try:
                        metric = int(parts[6])
                    except Exception:
                        metric = 0
                    gateway_ip = ""
                    try:
                        gateway_ip = socket.inet_ntoa(struct.pack("<L", int(gateway, 16)))
                    except Exception:
                        gateway_ip = ""
                    row = {"iface": iface, "gateway": gateway_ip, "metric": metric}
                    if best is None or row["metric"] < best["metric"]:
                        best = row
        except Exception:
            return {}
        return best or {}

    def read_global_ipv6_for_iface(iface):
        iface = str(iface or "").strip()
        if not iface:
            return ""
        try:
            with open("/proc/net/if_inet6", "r", encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    parts = line.split()
                    if len(parts) < 6:
                        continue
                    addr_hex, _idx, _plen, scope_hex, _flags, name = parts[:6]
                    if name != iface:
                        continue
                    if scope_hex.lower() != "00":
                        continue
                    try:
                        return socket.inet_ntop(socket.AF_INET6, bytes.fromhex(addr_hex))
                    except Exception:
                        continue
        except Exception:
            return ""
        return ""

    default_iface = ""
    lan_v4 = ""
    route_v4 = ""
    lan_v6 = ""
    route_v6 = ""
    if cmd_exists("ip"):
        out = run_cmd(["ip", "-4", "route", "get", "1.1.1.1"], timeout=1.5)
        match = re.search(r"\bsrc\s+([0-9.]+)", out)
        if match:
            lan_v4 = match.group(1)
        match = re.search(r"\bdev\s+([A-Za-z0-9._:-]+)", out)
        if match:
            default_iface = match.group(1)
        route_v4 = clean_text(out.splitlines()[0]) if out else ""
        if not route_v4:
            route_v4 = clean_text(run_cmd(["ip", "-4", "route", "show", "default"], timeout=1.5).splitlines()[0] if run_cmd(["ip", "-4", "route", "show", "default"], timeout=1.5) else "")
        out6 = run_cmd(["ip", "-6", "route", "show", "default"], timeout=1.5)
        route_v6 = clean_text(out6.splitlines()[0]) if out6 else ""
        if default_iface:
            addr6 = run_cmd(["ip", "-6", "addr", "show", "dev", default_iface, "scope", "global"], timeout=1.5)
            match = re.search(r"inet6\s+([0-9a-fA-F:]+)/", addr6)
            if match:
                lan_v6 = match.group(1)
    proc_route = read_default_route_v4()
    if not default_iface:
        default_iface = str(proc_route.get("iface", "") or "").strip()
    if not lan_v4:
        lan_v4 = detect_local_ipv4()
    if not route_v4 and default_iface:
        route_v4 = "default"
        if proc_route.get("gateway"):
            route_v4 += f" via {proc_route.get('gateway')}"
        route_v4 += f" dev {default_iface}"
        if lan_v4:
            route_v4 += f" src {lan_v4}"
    if not lan_v6:
        lan_v6 = read_global_ipv6_for_iface(default_iface)
    if not lan_v4:
        for iface_name, key in (
            ("wlan0", "dhcp.wlan0.ipaddress"),
            ("wlan1", "dhcp.wlan1.ipaddress"),
            ("eth0", "dhcp.eth0.ipaddress"),
            ("ap.br0", "dhcp.ap.br0.ipaddress"),
            ("rmnet_data0", "dhcp.rmnet_data0.ipaddress"),
            ("ccmni0", "dhcp.ccmni0.ipaddress"),
            ("wlan0", "wlan0.ipaddress"),
        ):
            value = getprop(key)
            if re.match(r"^([0-9]{1,3}\.){3}[0-9]{1,3}$", value):
                lan_v4 = value
                if not default_iface:
                    default_iface = iface_name
                break
    if not default_iface:
        default_iface = first_nonempty(
            getprop("wifi.interface"),
            getprop("persist.vendor.data.iwlan.ifname"),
            active_interface_fallback(),
        )
    if not route_v4 and default_iface:
        gateway = first_nonempty(
            getprop(f"dhcp.{default_iface}.gateway"),
            getprop(f"{default_iface}.gateway"),
        )
        route_v4 = "default"
        if gateway:
            route_v4 += f" via {gateway}"
        route_v4 += f" dev {default_iface}"
        if lan_v4:
            route_v4 += f" src {lan_v4}"
    dns_list = []
    iface_dns_keys = []
    if default_iface:
        iface_dns_keys.extend(
            [
                f"dhcp.{default_iface}.dns1",
                f"dhcp.{default_iface}.dns2",
                f"dhcp.{default_iface}.dns3",
                f"dhcp.{default_iface}.dns4",
                f"dhcp.{default_iface}.dns",
                f"dhcp.{default_iface}.dnses",
                f"{default_iface}.dns1",
                f"{default_iface}.dns2",
                f"{default_iface}.dns",
            ]
        )
    for key in iface_dns_keys:
        append_dns_values(dns_list, getprop(key))
    for key in (
        "net.dns1",
        "net.dns2",
        "net.dns3",
        "net.dns4",
        "persist.net.dns1",
        "persist.net.dns2",
        "persist.net.dns3",
        "persist.net.dns4",
    ):
        append_dns_values(dns_list, getprop(key))
    if not dns_list and cmd_exists("getprop"):
        all_props = run_cmd(["getprop"], timeout=2.5)
        for line in all_props.splitlines():
            match = re.match(r"^\[([^\]]+)\]:\s*\[(.*)\]$", line.strip())
            if not match:
                continue
            key = match.group(1).strip().lower()
            value = match.group(2).strip()
            if "dns" not in key:
                continue
            if default_iface and default_iface.lower() in key:
                append_dns_values(dns_list, value)
        for line in all_props.splitlines():
            match = re.match(r"^\[([^\]]+)\]:\s*\[(.*)\]$", line.strip())
            if not match:
                continue
            key = match.group(1).strip().lower()
            value = match.group(2).strip()
            if "dns" not in key:
                continue
            append_dns_values(dns_list, value)
    if not dns_list:
        for path in (
            "/etc/resolv.conf",
            str(Path(os.environ.get("CHROOT_INFO_TERMUX_PREFIX", "") or "") / "etc" / "resolv.conf") if os.environ.get("CHROOT_INFO_TERMUX_PREFIX", "") else "",
            "/system/etc/resolv.conf",
            "/vendor/etc/resolv.conf",
        ):
            if path:
                append_dns_from_file(dns_list, path)
    if not dns_list:
        append_dns_from_connectivity_dump(dns_list)
    transport = ""
    iface = default_iface.lower()
    if iface.startswith("wlan"):
        transport = "wifi"
    elif iface.startswith("rmnet") or iface.startswith("ccmni"):
        transport = "cellular"
    elif iface.startswith("eth") or iface.startswith("usb"):
        transport = "ethernet"
    return {
        "interface": default_iface,
        "transport": transport,
        "lan_ipv4": lan_v4,
        "lan_ipv6": lan_v6,
        "route_ipv4": route_v4,
        "route_ipv6": route_v6,
        "dns_servers": dns_list,
    }


def detect_selinux_mode():
    if cmd_exists("getenforce"):
        out = clean_text(run_cmd(["getenforce"], timeout=1.5))
        if out:
            return out.lower()
    text = read_text("/sys/fs/selinux/enforce")
    if text == "1":
        return "enforcing"
    if text == "0":
        return "permissive"
    return ""


def detect_uptime():
    text = read_text("/proc/uptime")
    try:
        return float(text.split()[0])
    except Exception:
        return 0.0


def collect_static_data():
    display = detect_display()
    abi_list = first_nonempty(
        first_prop("ro.product.cpu.abilist", "ro.system.product.cpu.abilist"),
        first_prop("ro.product.cpu.abi", "ro.system.product.cpu.abi"),
    )
    abi_items = [item.strip() for item in abi_list.split(",") if item.strip()]
    primary_abi = abi_items[0] if abi_items else first_nonempty(
        first_prop("ro.product.cpu.abi", "ro.system.product.cpu.abi"),
        platform.machine(),
    )
    kernel_release = first_nonempty(
        read_text("/proc/sys/kernel/osrelease"),
        clean_text(re.sub(r"^Linux version\s+(\S+).*$", r"\1", read_text("/proc/version"))),
        clean_text(platform.uname().release),
        clean_text(platform.release()),
    )
    kernel_arch = first_nonempty(clean_text(platform.machine()), clean_text(os.uname().machine) if hasattr(os, "uname") else "")
    return {
        "device": {
            "manufacturer": first_nonempty(first_prop("ro.product.manufacturer", "ro.product.vendor.manufacturer", "ro.product.system.manufacturer"), platform.node()),
            "brand": first_prop("ro.product.brand", "ro.product.vendor.brand", "ro.product.system.brand"),
            "model": first_nonempty(first_prop("ro.product.model", "ro.product.vendor.model", "ro.product.system.model"), platform.machine()),
            "codename": first_nonempty(first_prop("ro.product.device", "ro.product.vendor.device", "ro.product.system.device"), getprop("ro.build.product")),
            "product": first_nonempty(first_prop("ro.product.name", "ro.product.vendor.name", "ro.product.system.name"), getprop("ro.build.product")),
            "android_release": first_prop("ro.build.version.release", "ro.build.version.release_or_codename"),
            "api_level": first_prop("ro.build.version.sdk"),
            "build_id": first_nonempty(first_prop("ro.build.id"), platform.version()),
            "build_fingerprint": first_nonempty(first_prop("ro.build.fingerprint"), platform.platform()),
            "kernel_release": kernel_release,
            "kernel_arch": kernel_arch,
            "primary_abi": primary_abi,
            "abi_list": abi_items,
        },
        "display": display,
    }


def aurora_settings_summary():
    snapshot_text = os.environ.get("CHROOT_INFO_SETTINGS_JSON", "").strip()
    try:
        snapshot = json.loads(snapshot_text) if snapshot_text else {}
    except Exception:
        snapshot = {}
    rows = snapshot.get("settings", []) if isinstance(snapshot, dict) else []
    current = {}
    for row in rows:
        if not isinstance(row, dict):
            continue
        key = str(row.get("key", "") or "").strip()
        if key:
            current[key] = row.get("current")
    return {
        "x11": bool(current.get("x11", False)),
        "x11_dpi": current.get("x11_dpi", 160),
        "termux_home_bind": bool(current.get("termux_home_bind", False)),
        "android_storage_bind": bool(current.get("android_storage_bind", False)),
        "data_bind": bool(current.get("data_bind", False)),
        "android_full_bind": bool(current.get("android_full_bind", False)),
    }


def root_summary():
    available = env_bool("CHROOT_INFO_ROOT_AVAILABLE")
    kind = clean_text(os.environ.get("CHROOT_INFO_ROOT_KIND", ""))
    launcher = clean_text(os.environ.get("CHROOT_INFO_ROOT_BIN", ""))
    subcmd = clean_text(os.environ.get("CHROOT_INFO_ROOT_SUBCMD", ""))
    detail = clean_text(os.environ.get("CHROOT_INFO_ROOT_DIAG", ""))
    provider = ""
    merged = " ".join(part for part in [kind, launcher, subcmd, detail] if part).lower()
    if "magisk" in merged:
        provider = "magisk"
    elif "kernelsu" in merged:
        provider = "kernelsu"
    elif "apatch" in merged:
        provider = "apatch"
    elif "direct-root" in merged:
        provider = "direct-root"
    elif "su" in merged:
        provider = "su"
    if available and not kind:
        kind = "direct-root"
    label = kind or ("available" if available else "unavailable")
    return {
        "available": available,
        "kind": kind,
        "launcher": launcher,
        "subcmd": subcmd,
        "detail": detail,
        "provider": provider or label,
    }


def backend_summary():
    return {
        "chroot": clean_text(os.environ.get("CHROOT_INFO_CHROOT_BACKEND", "")),
        "mount": clean_text(os.environ.get("CHROOT_INFO_MOUNT_BACKEND", "")),
        "umount": clean_text(os.environ.get("CHROOT_INFO_UMOUNT_BACKEND", "")),
    }


def aurora_runtime_summary(runtime_root):
    return {
        "runtime_root": runtime_root,
        "runtime_writable": env_bool("CHROOT_INFO_RUNTIME_WRITABLE"),
        "settings": aurora_settings_summary(),
        "root": root_summary(),
        "backends": backend_summary(),
        "busybox": clean_text(os.environ.get("CHROOT_INFO_BUSYBOX_SUMMARY", "")),
    }


def active_tor_distro(state_root, distros):
    global_active = load_json(os.path.join(state_root, "_global", "tor", "active.json"), default={})
    active = str(global_active.get("active_distro", "") or "").strip()
    names = {row.get("distro") for row in distros if row.get("tor")}
    if active and active in names:
        return active
    for row in distros:
        if row.get("tor"):
            return row.get("distro")
    return ""


def render_bool(value, on_text="yes", off_text="no"):
    return on_text if bool(value) else off_text


def build_overview_section(static_doc, ram, battery, data_df, distros, aurora_doc):
    brand = str(static_doc["device"].get("brand", "") or "").strip()
    model = str(static_doc["device"].get("model", "") or "").strip()
    manufacturer = str(static_doc["device"].get("manufacturer", "") or "").strip()
    if brand.lower() == "unknown":
        brand = ""
    if model.lower() == "unknown":
        model = ""
    if manufacturer.lower() == "unknown":
        manufacturer = ""
    device_label = first_nonempty(
        " / ".join(part for part in [brand, model] if part),
        model,
        manufacturer,
        static_doc["device"].get("primary_abi"),
        "unknown device",
    )
    android_parts = []
    android_release = str(static_doc["device"].get("android_release", "") or "").strip()
    api_level = str(static_doc["device"].get("api_level", "") or "").strip()
    primary_abi = str(static_doc["device"].get("primary_abi", "") or "").strip()
    if android_release and android_release.lower() != "unknown":
        android_parts.append(f"Android {android_release}")
    if api_level and api_level.lower() != "unknown":
        android_parts.append(f"API {api_level}")
    if primary_abi:
        android_parts.append(primary_abi)
    android_label = " / ".join(android_parts)
    root_doc = aurora_doc["root"]
    security_value = f"root={'yes' if root_doc.get('available') else 'no'}"
    if root_doc.get("provider"):
        security_value += f" ({root_doc.get('provider')})"
    selinux = detect_selinux_mode()
    if selinux:
        security_value += f"  selinux={selinux}"
    resource_value = " ".join(
        part
        for part in [
            f"ram {human_bytes(ram.get('available_bytes', 0))} free / {human_bytes(ram.get('total_bytes', 0))} total" if ram.get("total_bytes") else "",
            f"battery {battery.get('level')}% {battery.get('status')}".strip() if battery.get("level") is not None else "",
        ]
        if part
    ).strip() or "unavailable"
    storage_value = f"/data free {human_bytes(data_df.get('free_bytes', 0))}" if data_df else "unavailable"
    mounted = sum(1 for row in distros if row.get("mounted"))
    service_count = sum(int(row.get("services") or 0) for row in distros)
    active_tor = active_tor_distro(str(Path(os.environ.get("CHROOT_INFO_STATE_DIR", ""))), distros)
    aurora_value = f"distros={len(distros)} mounted={mounted} services={service_count} tor={active_tor or 'off'}"
    rows = [
        {"label": "Device", "value": " / ".join(part for part in [device_label, android_label] if part)},
        {"label": "Security", "value": security_value},
        {"label": "Resources", "value": resource_value},
        {"label": "Storage", "value": storage_value},
        {"label": "Aurora", "value": aurora_value},
    ]
    return {"id": "overview", "title": "Overview", "status": "ready", "rows": rows}


def build_device_section(static_doc, uptime_seconds):
    boot_epoch = max(0.0, time.time() - max(0.0, uptime_seconds))
    device = static_doc["device"]
    display = static_doc.get("display", {})
    rows = [
        {"label": "Manufacturer", "value": first_nonempty(device.get("manufacturer"), "unknown")},
        {"label": "Brand", "value": first_nonempty(device.get("brand"), "unknown")},
        {"label": "Model", "value": first_nonempty(device.get("model"), "unknown")},
        {"label": "Codename", "value": first_nonempty(device.get("codename"), "unknown")},
        {"label": "Product", "value": first_nonempty(device.get("product"), "unknown")},
        {"label": "Android", "value": first_nonempty(device.get("android_release"), "unknown")},
        {"label": "API", "value": first_nonempty(device.get("api_level"), "unknown")},
        {"label": "Build", "value": first_nonempty(device.get("build_id"), "unknown")},
        {"label": "Fingerprint", "value": first_nonempty(device.get("build_fingerprint"), "unknown")},
        {"label": "Kernel", "value": first_nonempty(device.get("kernel_release"), "unknown")},
        {"label": "Arch", "value": first_nonempty(device.get("kernel_arch"), "unknown")},
        {"label": "ABI", "value": ", ".join(device.get("abi_list", [])) or first_nonempty(device.get("primary_abi"), "unknown")},
        {"label": "Display", "value": " @ ".join(
            part
            for part in [
                display.get("resolution", ""),
                f"{display.get('density')} dpi" if display.get("density") else "",
            ]
            if part
        ) or "unknown"},
        {"label": "Boot time", "value": utc_from_epoch(boot_epoch)},
        {"label": "Uptime", "value": human_duration(uptime_seconds)},
    ]
    return {"id": "device", "title": "Device", "status": "ready", "rows": rows}


def build_resources_section(cpu, ram, zram, battery, thermal):
    load_avg = detect_load()
    battery_parts = []
    if battery.get("level") is not None:
        battery_parts.append(f"{battery.get('level')}%")
    if battery.get("status"):
        battery_parts.append(str(battery.get("status")))
    if battery.get("temperature_c") is not None:
        battery_parts.append(f"{battery.get('temperature_c'):.1f}C")
    if battery.get("health"):
        battery_parts.append(f"health={battery.get('health')}")
    swap_text = ""
    if ram.get("swap_total_bytes"):
        swap_text = f"{human_bytes(ram.get('swap_total_bytes', 0))} total  {human_bytes(ram.get('swap_used_bytes', 0))} used"
    zram_text = ""
    if zram.get("total_bytes"):
        zram_text = f"{human_bytes(zram.get('total_bytes', 0))} total  {human_bytes(zram.get('used_bytes', 0))} used"
    show_zram = bool(zram_text) and zram_text != swap_text
    rows = [
        {"label": "CPU", "value": f"{cpu.get('online_cores', 0)} cores online, load {load_avg[0]:.2f} {load_avg[1]:.2f} {load_avg[2]:.2f}"},
        {"label": "CPU freq", "value": cpu.get("freq_summary") or "unavailable"},
        {"label": "Governor", "value": cpu.get("governor") or "unavailable"},
        {"label": "RAM", "value": f"{human_bytes(ram.get('total_bytes', 0))} total  {human_bytes(ram.get('used_bytes', 0))} used  {human_bytes(ram.get('available_bytes', 0))} avail"},
        {"label": "Swap", "value": swap_text or "unavailable"},
        {"label": "Battery", "value": " ".join(battery_parts) or "unavailable"},
        {"label": "Thermal", "value": (
            f"{thermal.get('state')}  {thermal.get('max_temp_c'):.1f}C"
            + (f" ({thermal.get('source')})" if thermal.get("source") else "")
            if thermal.get("max_temp_c") is not None
            else "unavailable"
        )},
    ]
    if show_zram:
        rows.insert(6, {"label": "ZRAM", "value": zram_text})
    return {"id": "resources", "title": "Resources", "status": "ready", "rows": rows}


def build_storage_section(runtime_root, rootfs_root, include_sizes=False, rootfs_size_map=None, rootfs_total=None):
    data_df = df_stats("/data")
    sd_df = df_stats("/sdcard")
    runtime_df = df_stats(runtime_root)
    rows = []
    if data_df:
        rows.append({"label": "/data", "value": f"{human_bytes(data_df['total_bytes'])} total  {human_bytes(data_df['used_bytes'])} used  {human_bytes(data_df['free_bytes'])} free"})
    if sd_df:
        rows.append({"label": "/sdcard", "value": f"{human_bytes(sd_df['total_bytes'])} total  {human_bytes(sd_df['used_bytes'])} used  {human_bytes(sd_df['free_bytes'])} free"})
    rows.append({"label": "runtime_root", "value": runtime_root})
    if runtime_df:
        rows.append({"label": "runtime fs", "value": f"{human_bytes(runtime_df['total_bytes'])} total  {human_bytes(runtime_df['used_bytes'])} used  {human_bytes(runtime_df['free_bytes'])} free"})
    distro_sizes = []
    status = "ready"
    if include_sizes:
        for distro in list_installed_distros(rootfs_root):
            size_doc = (rootfs_size_map or {}).get(distro, {})
            rootfs_bytes = int(size_doc.get("rootfs_bytes", 0) or 0)
            distro_sizes.append({
                "distro": distro,
                "rootfs_bytes": rootfs_bytes,
                "rootfs_text": str(size_doc.get("rootfs_text", "") or human_bytes(rootfs_bytes)),
            })
        rows.append({"label": "rootfs total", "value": human_bytes(rootfs_total or 0)})
    else:
        status = "loading"
        rows.append({"label": "rootfs total", "value": "..."})
    return {
        "id": "storage",
        "title": "Storage",
        "status": status,
        "rows": rows,
        "distro_sizes": distro_sizes,
    }


def build_network_section(network_doc):
    route = network_doc.get("route_ipv4") or network_doc.get("route_ipv6") or "unavailable"
    rows = [
        {"label": "Interface", "value": first_nonempty(network_doc.get("interface"), "unknown")},
        {"label": "Transport", "value": first_nonempty(network_doc.get("transport"), "unknown")},
        {"label": "LAN IPv4", "value": first_nonempty(network_doc.get("lan_ipv4"), "unavailable")},
        {"label": "LAN IPv6", "value": first_nonempty(network_doc.get("lan_ipv6"), "unavailable")},
        {"label": "Route", "value": route},
        {"label": "DNS", "value": ", ".join(network_doc.get("dns_servers", [])) or "unavailable"},
    ]
    return {"id": "network", "title": "Network", "status": "ready", "rows": rows}


def aurora_health_status(aurora_doc):
    failures = []
    warnings = []
    if not aurora_doc["root"].get("available"):
        failures.append("root backend unavailable")
    if not aurora_doc["runtime_writable"] and not aurora_doc["root"].get("available"):
        failures.append("runtime root not writable")
    if not aurora_doc["backends"].get("chroot"):
        failures.append("chroot backend missing")
    if not aurora_doc["backends"].get("mount") or not aurora_doc["backends"].get("umount"):
        failures.append("mount backend missing")
    if failures:
        return "fail", ", ".join(failures)
    if warnings:
        return "warn", ", ".join(warnings)
    return "ok", "runtime writable, required backends present"


def build_aurora_section(aurora_doc):
    settings = aurora_doc["settings"]
    health_state, health_text = aurora_health_status(aurora_doc)
    root_text = "unavailable"
    if aurora_doc["root"].get("available"):
        parts = [aurora_doc["root"].get("provider") or aurora_doc["root"].get("kind")]
        if aurora_doc["root"].get("launcher"):
            parts.append(aurora_doc["root"].get("launcher"))
        if aurora_doc["root"].get("subcmd"):
            parts.append(aurora_doc["root"].get("subcmd"))
        root_text = " ".join(part for part in parts if part).strip() or "available"
    backends = aurora_doc["backends"]
    rows = [
        {"label": "Runtime root", "value": aurora_doc["runtime_root"]},
        {"label": "Root backend", "value": root_text},
        {"label": "Backends", "value": "  ".join(
            part
            for part in [
                f"chroot={backends.get('chroot')}" if backends.get("chroot") else "",
                f"mount={backends.get('mount')}" if backends.get("mount") else "",
                f"umount={backends.get('umount')}" if backends.get("umount") else "",
            ]
            if part
        ) or "unavailable"},
        {"label": "BusyBox", "value": aurora_doc.get("busybox") or "unavailable"},
        {"label": "Settings", "value": " ".join(
            [
                f"x11={'on' if settings.get('x11') else 'off'}",
                f"dpi={settings.get('x11_dpi')}",
                f"home_bind={'on' if settings.get('termux_home_bind') else 'off'}",
                f"storage_bind={'on' if settings.get('android_storage_bind') else 'off'}",
                f"data_bind={'on' if settings.get('data_bind') else 'off'}",
                f"full_bind={'on' if settings.get('android_full_bind') else 'off'}",
            ]
        )},
        {"label": "Health", "value": f"[{health_state}] {health_text}"},
    ]
    return {"id": "aurora", "title": "Aurora", "status": health_state, "rows": rows}


def build_distros_section(rootfs_root, state_root, include_sizes=False, rootfs_size_map=None):
    distros = read_distro_rows(rootfs_root, state_root, include_sizes=include_sizes, rootfs_size_map=rootfs_size_map)
    mounted = sum(1 for row in distros if row.get("mounted"))
    sessions = sum(int(row.get("sessions") or 0) for row in distros)
    services = sum(int(row.get("services") or 0) for row in distros)
    tor_active = active_tor_distro(state_root, distros)
    summary_rows = [
        {"label": "Installed", "value": str(len(distros))},
        {"label": "Mounted", "value": str(mounted)},
        {"label": "Sessions", "value": str(sessions)},
        {"label": "Services", "value": str(services)},
        {"label": "Tor active", "value": tor_active or "off"},
    ]
    return {
        "id": "distro",
        "title": "Distro",
        "status": "ready" if include_sizes else "loading",
        "summary_rows": summary_rows,
        "distros": distros,
    }


def build_hints_section():
    rows = [
        {"label": "doctor", "value": "Backend diagnostics and root/runtime checks."},
        {"label": "status", "value": "Mount and session detail for installed distros."},
        {"label": "service", "value": "Service inventory and daemon state."},
        {"label": "tor", "value": "Tor detail and runtime state."},
    ]
    return {"id": "hint", "title": "Hint", "status": "ready", "rows": rows}


def build_payload(mode, section, runtime_root, rootfs_root, state_root):
    static_doc = collect_static_data()
    ram = detect_ram()
    zram = detect_zram()
    battery = detect_battery()
    thermal = detect_thermal()
    cpu = detect_cpu()
    network_doc = detect_network()
    uptime_seconds = detect_uptime()
    aurora_doc = aurora_runtime_summary(runtime_root)
    size_map = {}
    rootfs_total = 0
    mount_points = read_mount_points()
    need_rootfs_sizes = bool(mode == "full" or section in {"storage", "distro"})
    if need_rootfs_sizes:
        size_map, rootfs_total = collect_rootfs_size_map(rootfs_root, mount_points=mount_points)
    fast_distros = read_distro_rows(rootfs_root, state_root, include_sizes=False)
    data_df = df_stats("/data")

    section_payloads = {}
    overview_section = build_overview_section(static_doc, ram, battery, data_df, fast_distros, aurora_doc)
    device_section = build_device_section(static_doc, uptime_seconds)
    resources_section = build_resources_section(cpu, ram, zram, battery, thermal)
    storage_section = build_storage_section(
        runtime_root,
        rootfs_root,
        include_sizes=(mode == "full" or section == "storage"),
        rootfs_size_map=size_map,
        rootfs_total=rootfs_total,
    )
    network_section = build_network_section(network_doc)
    aurora_section = build_aurora_section(aurora_doc)
    distros_section = build_distros_section(
        rootfs_root,
        state_root,
        include_sizes=(mode == "full" or section == "distro"),
        rootfs_size_map=size_map,
    )
    hints_section = build_hints_section()
    section_payloads = {
        "overview": overview_section,
        "device": device_section,
        "resources": resources_section,
        "storage": storage_section,
        "distro": distros_section,
        "network": network_section,
        "aurora": aurora_section,
        "hint": hints_section,
    }

    if mode == "section" and section:
        selected = {}
        if section in section_payloads:
            selected[section] = section_payloads[section]
        section_payloads = selected

    payload = {
        "schema_version": SCHEMA_VERSION,
        "generated_at": utc_now_iso(),
        "mode": mode,
        "requested_section": section,
        "section_order": SECTION_ORDER,
        "slow_sections": sorted(SLOW_SECTIONS),
        "sections": section_payloads,
    }
    return payload


def width_from_argv(arg_value):
    try:
        width = int(arg_value)
    except Exception:
        width = 96
    width = max(54, min(96, width))
    return width


def wrap_words(text, width):
    text = str(text or "").strip()
    if not text:
        return [""]
    try:
        wrapped = textwrap.wrap(text, width=width, break_long_words=True, replace_whitespace=False)
    except Exception:
        wrapped = []
    return wrapped or [text[:width]]


def wrap_field(label, value, width):
    prefix = f"{str(label or ''):<8}: "
    text = str(value or "").strip() or "-"
    available = max(12, width - len(prefix))
    chunks = textwrap.wrap(
        text,
        width=available,
        break_long_words=False,
        replace_whitespace=False,
    ) or [text]
    lines = [prefix + chunks[0]]
    indent = " " * len(prefix)
    for chunk in chunks[1:]:
        lines.append(indent + chunk)
    return lines


def render_card(lines, width):
    normalized = []
    max_width = max(20, width - 4)
    for line in (lines or [""]):
        text = str(line or "")
        if not text:
            normalized.append("")
            continue
        if len(text) <= max_width:
            normalized.append(text)
            continue
        normalized.extend(wrap_words(text, max_width))
    clipped_lines = normalized or [""]
    inner_width = max(20, min(max(len(line) for line in clipped_lines), max_width))
    border = "+" + ("-" * (inner_width + 2)) + "+"
    rendered = [border]
    for line in clipped_lines:
        rendered.append(f"| {line.ljust(inner_width)} |")
    rendered.append(border)
    return rendered


def render_label_rows(rows, width, indent=""):
    label_width = 0
    for row in rows:
        label_width = max(label_width, len(str(row.get("label", "") or "")))
    label_width = max(8, min(14, label_width))
    out = []
    value_width = max(20, width - label_width - 2)
    compact = width < 72
    for row in rows:
        label = str(row.get("label", "") or "")
        value = str(row.get("value", "") or "")
        if compact and (len(value) > value_width or len(label) + 2 + len(value) > width):
            out.append(f"{indent}{label}")
            for line in wrap_words(value, max(20, width - 2)):
                out.append(f"{indent}  {line}")
            continue
        lines = wrap_words(value, value_width)
        out.append(f"{indent}{label.ljust(label_width)}  {lines[0]}")
        pad = " " * (label_width + 2)
        for line in lines[1:]:
            out.append(f"{indent}{pad}{line}")
    return out


def render_wrapped_fields(rows, width):
    out = []
    for row in rows or []:
        if not isinstance(row, dict):
            continue
        out.extend(wrap_field(row.get("label", ""), row.get("value", ""), width))
    return out


def render_section_heading(title):
    return [title, "-" * len(title)]


def render_storage_section(section, width):
    out = render_label_rows(section.get("rows", []), width)
    distro_sizes = section.get("distro_sizes", [])
    if distro_sizes:
        out.append("")
        out.append("Per-Distro Sizes")
        out.append("~" * len("Per-Distro Sizes"))
        for row in distro_sizes:
            out.extend(
                render_label_rows(
                    [
                        {"label": row.get("distro", ""), "value": f"rootfs {row.get('rootfs_text')}"},
                    ],
                    width,
                )
            )
    return out


def render_distros_table(rows, width):
    cols = [
        ("NAME", 10, "distro"),
        ("RELEASE", 10, "release"),
        ("MNT", 5, lambda row: "yes" if row.get("mounted") else "no"),
        ("SES", 4, lambda row: str(row.get("sessions", 0))),
        ("SVC", 4, lambda row: str(row.get("services", 0))),
        ("DESKTOP", 8, "desktop"),
        ("TOR", 4, lambda row: "on" if row.get("tor") else "off"),
        ("ROOTFS", 8, "rootfs_text"),
    ]
    total = sum(width for _, width, _ in cols) + len(cols) - 1
    if width < total:
        return []
    header = " ".join(name.ljust(col_width) for name, col_width, _getter in cols)
    sep = " ".join("-" * col_width for _name, col_width, _getter in cols)
    out = [header, sep]
    for row in rows:
        parts = []
        for _name, col_width, getter in cols:
            if callable(getter):
                value = getter(row)
            else:
                value = row.get(getter, "")
            parts.append(str(value or "")[:col_width].ljust(col_width))
        out.append(" ".join(parts))
    return out


def render_distros_stacked(rows, width):
    out = []
    for idx, row in enumerate(rows):
        if idx:
            out.append("")
        title = str(row.get("distro", "") or "<distro>")
        out.append(title)
        out.append("~" * len(title))
        out.extend(
            render_label_rows(
                [
                    {"label": "Release", "value": row.get("release", "")},
                    {"label": "Mounted", "value": "yes" if row.get("mounted") else "no"},
                    {"label": "Sessions", "value": str(row.get("sessions", 0))},
                    {"label": "Services", "value": str(row.get("services", 0))},
                    {"label": "Desktop", "value": row.get("desktop", "no")},
                    {"label": "Tor", "value": "on" if row.get("tor") else "off"},
                    {"label": "Rootfs", "value": row.get("rootfs_text", "...")},
                ],
                width,
            )
        )
    return out or ["No installed distros."]


def render_distros_section(section, width):
    out = []
    if section.get("summary_rows"):
        out.extend(render_label_rows(section.get("summary_rows", []), width))
    rows = section.get("distros", [])
    if not rows:
        out.append("")
        out.append("No installed distros.")
        return out
    out.append("")
    table = render_distros_table(rows, width)
    if table:
        out.extend(table)
    else:
        out.extend(render_distros_stacked(rows, width))
    return out


def render_section_body(section, width):
    section_id = str(section.get("id", "") or "")
    if section_id == "storage":
        return render_storage_section(section, width)
    if section_id == "distro":
        return render_distros_section(section, width)
    if section_id in {"device", "network", "aurora"}:
        return render_wrapped_fields(section.get("rows", []), width)
    return render_label_rows(section.get("rows", []), width)


def render_section_card(section, width):
    title = str(section.get("title", section.get("id", "Section")) or "Section")
    status = str(section.get("status", "") or "").strip()
    card_lines = [title.upper()]
    if status and status not in {"ready", "ok"}:
        card_lines.extend(wrap_field("status", status, width - 4))
    body_lines = render_section_body(section, max(24, width - 4))
    if body_lines:
        card_lines.append("")
        card_lines.extend(body_lines)
    return render_card(card_lines, width)


def render_human(payload, width):
    out = ["AURORA INFO-HUB", ""]
    sections = payload.get("sections", {})
    order = payload.get("section_order", SECTION_ORDER)
    for section_id in order:
        section = sections.get(section_id)
        if not isinstance(section, dict):
            continue
        out.extend(render_section_card(section, width))
        out.append("")
    return "\n".join(out).rstrip("\n") + "\n"


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "collect"
    runtime_root = sys.argv[2] if len(sys.argv) > 2 else ""
    rootfs_root = sys.argv[3] if len(sys.argv) > 3 else ""
    state_root = sys.argv[4] if len(sys.argv) > 4 else ""
    mode = sys.argv[5] if len(sys.argv) > 5 else "full"
    section = sys.argv[6] if len(sys.argv) > 6 else ""
    width = width_from_argv(sys.argv[7] if len(sys.argv) > 7 else "96")

    os.environ["CHROOT_INFO_STATE_DIR"] = state_root

    if action == "collect":
        payload = build_payload(mode, section, runtime_root, rootfs_root, state_root)
        print(json.dumps(payload, indent=2, sort_keys=True))
        return

    if action == "render":
        try:
            raw = os.environ.get("CHROOT_INFO_RENDER_PAYLOAD", "")
            if not raw:
                raw = sys.stdin.read() or "{}"
            payload = json.loads(raw)
        except Exception as exc:
            raise SystemExit(f"failed to parse info payload: {exc}")
        sys.stdout.write(render_human(payload, width))
        return

    raise SystemExit(f"unknown action: {action}")


if __name__ == "__main__":
    main()
PY
}
