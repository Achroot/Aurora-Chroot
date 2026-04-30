#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_PATH="$BASE_DIR/dist/chroot"

# shellcheck source=/dev/null
source "$BASE_DIR/lib/core.sh"
# shellcheck source=/dev/null
source "$BASE_DIR/lib/log.sh"
# shellcheck source=/dev/null
source "$BASE_DIR/lib/commands.sh"

bash "$BASE_DIR/tools/bundle.sh" >/dev/null

chroot_set_runtime_root "$CHROOT_RUNTIME_ROOT"
chroot_prepend_termux_path
chroot_detect_python
chroot_require_python

REGISTRY_JSON="$(chroot_commands_registry_json)"

export REGISTRY_JSON BUNDLE_PATH BASE_DIR

"$CHROOT_PYTHON_BIN" - "$BASE_DIR" <<'PY'
import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

base_dir = Path(sys.argv[1])
bundle_path = Path(os.environ["BUNDLE_PATH"])
registry = json.loads(os.environ["REGISTRY_JSON"])

errors = []


def read_text(path):
    return path.read_text(encoding="utf-8")


def require(condition, message):
    if not condition:
        errors.append(message)


def heading_block(text, char):
    return f"{text}\n{char * len(text)}"


def raw_help_lines_from_registry(doc):
    groups = doc.get("groups", [])
    commands = doc.get("commands", [])
    raw_lines = []
    for group in sorted(groups, key=lambda row: int(row.get("order", 0) or 0)):
        label = str(group.get("label", "") or "").strip()
        gid = str(group.get("id", "") or "").strip()
        if not label or not gid:
            continue
        raw_lines.append(label)
        raw_lines.append("")
        for row in commands:
            if str(row.get("group", "") or "").strip() != gid:
                continue
            for usage in row.get("raw_usage", []):
                text = str(usage or "").rstrip()
                if text:
                    raw_lines.append(f"  {text}")
        raw_lines.append("")
    return "\n".join(raw_lines).rstrip("\n")


def render_raw_help_from_registry(doc):
    raw_lines = raw_help_lines_from_registry(doc).splitlines()

    rendered = []
    pending_blank = False
    for line in raw_lines:
        if line and not line.startswith(" "):
            if pending_blank:
                rendered.append("")
            rendered.append(heading_block(line, "-"))
            rendered.append("")
            pending_blank = False
            continue
        if line == "":
            if not pending_blank:
                rendered.append("")
                pending_blank = True
            continue
        rendered.append(line)
        pending_blank = False
    return "\n".join(rendered).rstrip("\n")


def expected_tui_commands_from_registry(doc):
    commands = doc.get("commands", [])
    out = [row for row in commands if isinstance(row, dict) and row.get("tui_visible")]
    out.sort(key=lambda row: (int(row.get("menu_order", 0) or 0), str(row.get("id", "") or "")))
    return out


def apply_default_form_values(app, command_id):
    app.form_values = {}
    spec = app.get_spec(command_id)
    for field in spec.get("fields", []):
        if not isinstance(field, dict):
            continue
        key = str(field.get("id", "") or "").strip()
        if not key:
            continue
        app.form_values[key] = field.get("default")


def assert_builder_case(app, command_id, values, expected_args, expected_stdin):
    apply_default_form_values(app, command_id)
    app.form_values.update(values)
    try:
        actual_args, actual_stdin = app.build_command(command_id)
    except Exception as exc:
        require(False, f"registry builder failed for {command_id}: {exc}")
        return

    require(
        actual_args == expected_args and actual_stdin == expected_stdin,
        (
            f"registry builder drift for {command_id}: "
            f"got args={actual_args!r} stdin={actual_stdin!r} "
            f"expected args={expected_args!r} stdin={expected_stdin!r}"
        ),
    )


def bundled_shell(script):
    result = subprocess.run(
        ["bash", "-lc", script],
        cwd=base_dir,
        capture_output=True,
        text=True,
        timeout=30,
    )
    return result


bundle_text = read_text(bundle_path)

commands = registry.get("commands", [])
groups = registry.get("groups", [])
require(isinstance(commands, list), "registry commands payload is not a list")
require(isinstance(groups, list), "registry groups payload is not a list")

command_ids = [str(row.get("id", "")).strip() for row in commands if isinstance(row, dict)]
require(len(command_ids) == len(set(command_ids)), "duplicate command ids detected after registry load")

for command_id in command_ids:
    if command_id == "root":
        continue
    if command_id == "help":
        for handler in ("chroot_cmd_help", "chroot_cmd_help_raw"):
            require(re.search(rf"(?m)^{re.escape(handler)}\(\)", bundle_text) is not None, f"missing bundled handler function: {handler}")
        continue
    handler = "chroot_cmd_" + command_id.replace("-", "_")
    require(re.search(rf"(?m)^{re.escape(handler)}\(\)", bundle_text) is not None, f"missing bundled handler function: {handler}")

bundled_selfcheck = bundled_shell(
    f"source {shlex.quote(str(bundle_path))}; "
    'chroot_set_runtime_root "$CHROOT_RUNTIME_ROOT"; '
    "chroot_prepend_termux_path; "
    "chroot_detect_python; "
    "chroot_require_python; "
    "chroot_commands_registry_selfcheck"
)
require(bundled_selfcheck.returncode == 0, f"bundled registry selfcheck failed: rc={bundled_selfcheck.returncode}")

public_help_raw = subprocess.run(
    ["bash", str(bundle_path), "help", "raw"],
    cwd=base_dir,
    capture_output=True,
    text=True,
    timeout=30,
)
require(public_help_raw.returncode == 0, f"bundled help raw failed: rc={public_help_raw.returncode}")
expected_help_raw_lines = raw_help_lines_from_registry(registry)
expected_help_raw = render_raw_help_from_registry(registry)
require(public_help_raw.stdout.rstrip("\n") == expected_help_raw, "public help raw output drifted from registry command metadata")

public_help = subprocess.run(
    ["bash", str(bundle_path), "help"],
    cwd=base_dir,
    capture_output=True,
    text=True,
    timeout=30,
)
require(public_help.returncode == 0, f"bundled help failed: rc={public_help.returncode}")

source_help = subprocess.run(
    ["bash", str(base_dir / "main.sh"), "help"],
    cwd=base_dir,
    capture_output=True,
    text=True,
    timeout=30,
)
require(source_help.returncode == 0, f"source help failed during audit: rc={source_help.returncode}")
require(public_help.stdout == source_help.stdout, "bundled help output drifted from source help output")

bundled_tui_env = bundled_shell(
    f"source {shlex.quote(str(bundle_path))}; "
    'chroot_set_runtime_root "$CHROOT_RUNTIME_ROOT"; '
    "chroot_prepend_termux_path; "
    "chroot_detect_python; "
    "chroot_require_python; "
    "chroot_tui_prepare_env; "
    '"$CHROOT_PYTHON_BIN" - <<'"'"'P'"'"'\n'
    "import json, os\n"
    "print(json.dumps({k: v for k, v in os.environ.items() if k.startswith('CHROOT_TUI_') or k.startswith('CHROOT_HELP_')}))\n"
    "P"
)
require(bundled_tui_env.returncode == 0, f"bundled tui env prep failed: rc={bundled_tui_env.returncode}")

tui_env = {}
if bundled_tui_env.returncode == 0:
    try:
        tui_env = json.loads(bundled_tui_env.stdout)
    except Exception as exc:
        require(False, f"failed to parse bundled tui env payload: {exc}")

for key in (
    "CHROOT_TUI_COMMANDS_JSON",
    "CHROOT_TUI_SPECS_JSON",
    "CHROOT_TUI_RUNNER",
):
    require(bool(str(tui_env.get(key, "") or "").strip()), f"bundled env missing {key}")

require(
    str(tui_env.get("CHROOT_HELP_RAW_TEXT", "") or "").rstrip("\n") == expected_help_raw_lines,
    "bundled raw help env text drifted from registry command metadata",
)
require(
    str(tui_env.get("CHROOT_HELP_RAW_RENDERED_TEXT", "") or "").rstrip("\n") == expected_help_raw,
    "bundled rendered raw help env text drifted from registry command metadata",
)

bundled_tui_code = bundled_shell(
    f"source {shlex.quote(str(bundle_path))}; "
    "chroot_tui_emit_python"
)
require(bundled_tui_code.returncode == 0, f"bundled TUI python emit failed: rc={bundled_tui_code.returncode}")

tui_commands_doc = json.loads(tui_env.get("CHROOT_TUI_COMMANDS_JSON", "{}"))
tui_specs_doc = json.loads(tui_env.get("CHROOT_TUI_SPECS_JSON", "{}"))
tui_commands = tui_commands_doc.get("commands", [])
tui_specs = tui_specs_doc.get("specs", {})
expected_tui_commands = expected_tui_commands_from_registry(registry)

require(isinstance(tui_commands, list), "tui commands payload is not a list")
require(isinstance(tui_specs, dict), "tui specs payload is not a dict")
require(tui_commands_doc == {"commands": expected_tui_commands}, "tui command projection drifted from registry metadata")

tui_ids = [str(row.get("id", "")).strip() for row in tui_commands if isinstance(row, dict)]
require(all(tui_ids), "blank tui command id in registry tui payload")

code = bundled_tui_code.stdout
require(bool(code.strip()), "bundled TUI python payload missing")
ns = {}
exec(compile(code, "<tui-assembled>", "exec"), ns)
TuiApp = ns["TuiApp"]

try:
    import curses
except Exception as exc:
    raise SystemExit(f"failed to import curses for audit: {exc}")

curses.flushinp = lambda: None


class FakeScreen:
    def getmaxyx(self):
        return (24, 80)

    def refresh(self):
        return None


for key in (
    "CHROOT_HELP_TEXT",
    "CHROOT_HELP_RENDERED_TEXT",
    "CHROOT_HELP_RAW_TEXT",
    "CHROOT_HELP_RAW_RENDERED_TEXT",
    "CHROOT_TUI_COMMANDS_JSON",
    "CHROOT_TUI_SPECS_JSON",
    "CHROOT_TUI_RUNNER",
):
    os.environ[key] = str(tui_env.get(key, "") or "")

app = TuiApp(FakeScreen(), str(base_dir))
expected_tui_ids = [str(row.get("id", "")).strip() for row in expected_tui_commands]
require(app.commands == expected_tui_ids, f"tui command order drift: app={app.commands!r} registry={expected_tui_ids!r}")

for command_id in app.commands:
    require(command_id in app.specs, f"missing TUI spec for command: {command_id}")

builder_cases = [
    ("help", {"view": "raw"}, ["raw"], ""),
    ("init", {}, [], ""),
    ("doctor", {"json": True, "repair": True}, ["--json", "--repair-locks"], ""),
    ("distros", {}, [], ""),
    ("status", {"scope": "distro", "distro": "demo", "json": True, "live": True}, ["--distro", "demo", "--json", "--live"], ""),
    ("logs", {"count": "7"}, ["7"], ""),
    ("info", {}, [], ""),
    ("busybox", {}, [], ""),
    ("install-local", {"distro": "demo", "file": "/tmp/archive.tar", "sha256": "deadbeef", "stdin_reply": "y"}, ["demo", "--file", "/tmp/archive.tar", "--sha256", "deadbeef"], "y\n"),
    ("login", {"distro": "demo"}, ["demo"], ""),
    ("mount", {"distro": "demo"}, ["demo"], ""),
    ("unmount", {"distro": "demo", "kill_sessions": True}, ["demo", "--kill-sessions"], ""),
    ("backup", {"distro": "demo", "mode": "rootfs", "out": "/tmp/backups"}, ["demo", "--mode", "rootfs", "--out", "/tmp/backups"], ""),
    ("remove", {"distro": "demo", "full": True}, ["demo", "--full"], ""),
    ("nuke", {}, [], ""),
    ("settings", {}, [], ""),
    ("clear-cache", {}, [], ""),
]

for command_id, values, expected_args, expected_stdin in builder_cases:
    assert_builder_case(app, command_id, values, expected_args, expected_stdin)

log_cases = [
    (
        "core_help_raw",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_core_action help raw",
        "help.raw",
    ),
    (
        "core_help_alias",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_core_action --help",
        "help",
    ),
    (
        "core_default_empty",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_core_action ''",
        "help",
    ),
    (
        "core_distros_install",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_core_action distros --install archlinux --version rolling",
        "distros.install",
    ),
    (
        "core_distros_download",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_core_action distros --download archlinux --version rolling",
        "distros.download",
    ),
    (
        "core_distros_refresh",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_core_action distros --refresh",
        "distros.refresh",
    ),
    (
        "core_settings_default",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_core_action settings",
        "settings",
    ),
    (
        "core_settings_json",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_core_action settings --json",
        "settings.json",
    ),
    (
        "core_settings_list",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_core_action settings list",
        "settings.show",
    ),
    (
        "core_settings_set",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_core_action settings set x11 true",
        "settings.set",
    ),
    (
        "core_doctor_repair",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_core_action doctor --repair-locks",
        "doctor.repair-locks",
    ),
    (
        "core_doctor_json",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_core_action doctor --json",
        "doctor.json",
    ),
    (
        "core_doctor_json_repair",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_core_action doctor --json --repair-locks",
        "doctor.json.repair-locks",
    ),
    (
        "core_status_default",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_core_action status",
        "status",
    ),
    (
        "core_status_json_live",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_core_action status --json --live",
        "status.json.live",
    ),
    (
        "core_clear_cache",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_core_action clear-cache",
        "clear-cache",
    ),
    (
        "core_info_default",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_core_action info",
        "info",
    ),
    (
        "core_info_json",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_core_action info --json",
        "info.json",
    ),
    (
        "core_info_refresh",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_core_action info refresh",
        "info.refresh",
    ),
    (
        "core_info_section",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_core_action info section storage",
        "info.section",
    ),
    (
        "core_busybox_default",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_core_action busybox",
        "busybox",
    ),
    (
        "core_busybox_fetch",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_core_action busybox fetch",
        "busybox.fetch",
    ),
    (
        "core_busybox_status",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_core_action busybox status",
        "busybox.status",
    ),
    (
        "core_busybox_path",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_core_action busybox /tmp/busybox",
        "busybox.path",
    ),
    (
        "core_unknown_passthrough",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_core_action custom-cmd",
        "custom-cmd",
    ),
    (
        "scoped_service_default_list",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_scoped_action service",
        "service.list",
    ),
    (
        "scoped_service_list_json",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_scoped_action service list --json",
        "service.list.json",
    ),
    (
        "scoped_service_install_json",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_scoped_action service install --json",
        "service.install.catalog-json",
    ),
    (
        "scoped_service_install_list",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_scoped_action service install --list",
        "service.install.list",
    ),
    (
        "scoped_service_install_profiles",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_scoped_action service install desktop --profiles",
        "service.install.desktop.profiles",
    ),
    (
        "scoped_service_start_alias",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_scoped_action service start sshd",
        "service.start",
    ),
    (
        "scoped_service_invalid",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_scoped_action service bogus",
        "service.invalid",
    ),
    (
        "scoped_sessions_default_list",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_scoped_action sessions",
        "sessions.list",
    ),
    (
        "scoped_sessions_status",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_scoped_action sessions status",
        "sessions.status",
    ),
    (
        "scoped_sessions_kill_all",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_scoped_action sessions kill-all",
        "sessions.kill-all",
    ),
    (
        "scoped_sessions_invalid",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_scoped_action sessions bogus",
        "sessions.invalid",
    ),
    (
        "scoped_tor_default_status",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_scoped_action tor",
        "tor.status",
    ),
    (
        "scoped_tor_on_alias",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_scoped_action tor start",
        "tor.on",
    ),
    (
        "scoped_tor_apps_refresh",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_scoped_action tor apps refresh",
        "tor.apps.refresh",
    ),
    (
        "scoped_tor_apps_invalid",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_scoped_action tor apps bogus",
        "tor.apps.invalid",
    ),
    (
        "scoped_tor_exit_list",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_scoped_action tor exit list",
        "tor.exit.list",
    ),
    (
        "scoped_tor_perf_ignore_set",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_scoped_action tor exit performance-ignore set",
        "tor.exit.performance-ignore.set",
    ),
    (
        "scoped_tor_exit_invalid",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_scoped_action tor exit bogus",
        "tor.exit.invalid",
    ),
    (
        "scoped_tor_invalid",
        f"source {shlex.quote(str(bundle_path))}; chroot_log_infer_scoped_action tor bogus",
        "tor.invalid",
    ),
]

for label, script, expected in log_cases:
    result = bundled_shell(script)
    require(result.returncode == 0, f"log audit command failed: {label} rc={result.returncode}")
    require(result.stdout.strip() == expected, f"log audit drift for {label}: got {result.stdout.strip()!r} expected {expected!r}")

print(f"registry_commands={len(command_ids)}")
print(f"tui_commands={len(tui_ids)}")
print("status=ok" if not errors else "status=fail")

if errors:
    for message in errors:
        print(f"error={message}")
    raise SystemExit(1)
PY
