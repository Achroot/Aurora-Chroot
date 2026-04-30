#!/usr/bin/env bash

chroot_commands_info_section_usage_ids() {
  if declare -F chroot_info_section_usage_ids >/dev/null 2>&1; then
    chroot_info_section_usage_ids
    return 0
  fi

  local base_dir preamble
  base_dir="${CHROOT_BASE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
  preamble="$base_dir/lib/info/001_preamble.sh"
  if [[ -r "$preamble" ]]; then
    # shellcheck source=/dev/null
    source "$preamble"
  fi

  if declare -F chroot_info_section_usage_ids >/dev/null 2>&1; then
    chroot_info_section_usage_ids
    return 0
  fi

  printf 'overview|device|resources|storage|distro|network|aurora|hint\n'
}

chroot_commands_registry_core_log_actions_tsv() {
  cat <<'EOF_TSV'
info	default		info
info	first-arg	refresh	info.refresh
info	first-arg	section	info.section
info	first-arg	--json	info.json
EOF_TSV
}

chroot_commands_registry_core_log_action_resolve() {
  local cmd="${1:-}"
  shift || true
  local first="${1:-}"
  local default_action=""
  local matched_action=""
  local row_cmd row_kind row_value row_action

  while IFS=$'\t' read -r row_cmd row_kind row_value row_action; do
    [[ "$row_cmd" == "$cmd" ]] || continue
    case "$row_kind" in
      default)
        default_action="$row_action"
        ;;
      first-arg)
        if [[ "$first" == "$row_value" ]]; then
          matched_action="$row_action"
          break
        fi
        ;;
    esac
  done < <(chroot_commands_registry_core_log_actions_tsv)

  if [[ -n "$matched_action" ]]; then
    printf '%s\n' "$matched_action"
    return 0
  fi
  if [[ -n "$default_action" ]]; then
    printf '%s\n' "$default_action"
    return 0
  fi
  return 1
}

chroot_commands_registry_json() {
  local info_section_usage
  local json
  info_section_usage="$(chroot_commands_info_section_usage_ids)"
  json="$(cat <<'JSON'
{
  "groups": [
    {"id": "core", "label": "Core", "order": 10},
    {"id": "settings", "label": "Settings", "order": 20},
    {"id": "service", "label": "Service", "order": 30},
    {"id": "sessions", "label": "Sessions", "order": 40},
    {"id": "tor", "label": "Tor", "order": 50}
  ],
  "commands": [
    {
      "id": "root",
      "group": "core",
      "scope": "core",
      "tui_visible": false,
      "menu_order": 0,
      "summary": "Run the default Aurora entry flow.",
      "raw_usage": ["chroot"]
    },
    {
      "id": "help",
      "group": "core",
      "scope": "core",
      "tui_visible": true,
      "menu_order": 10,
      "summary": "Show Aurora help text.",
      "aliases": ["-h", "--help"],
      "raw_usage": [
        "chroot help|-h|--help",
        "chroot help raw"
      ]
    },
    {
      "id": "init",
      "group": "core",
      "scope": "core",
      "tui_visible": true,
      "menu_order": 20,
      "summary": "Show first-run setup guidance and dependency status.",
      "raw_usage": ["chroot init"]
    },
    {
      "id": "doctor",
      "group": "core",
      "scope": "core",
      "tui_visible": true,
      "menu_order": 30,
      "summary": "Run system diagnostics and lock repair checks.",
      "raw_usage": ["chroot doctor [--json] [--repair-locks]"]
    },
    {
      "id": "distros",
      "group": "core",
      "scope": "core",
      "tui_visible": true,
      "menu_order": 35,
      "summary": "Browse, refresh, download, and install dynamic distro catalog entries.",
      "raw_usage": [
        "chroot distros [--refresh]",
        "chroot distros [--json] [--refresh]",
        "chroot distros --download <id> --version <target> [--refresh]",
        "chroot distros --install <id> --version <target> [--refresh]"
      ]
    },
    {
      "id": "install-local",
      "group": "core",
      "scope": "core",
      "tui_visible": true,
      "menu_order": 40,
      "summary": "Install a distro from a local archive or scan a path for local archives.",
      "raw_usage": [
        "chroot install-local <distro> --file <path> [--sha256 <hex>]",
        "chroot install-local --file <path> --json"
      ]
    },
    {
      "id": "status",
      "group": "core",
      "scope": "core",
      "tui_visible": true,
      "menu_order": 50,
      "summary": "Show installed distros, sessions, and mount status.",
      "raw_usage": ["chroot status [--all|--distro <id>] [--json] [--live]"]
    },
    {
      "id": "login",
      "group": "core",
      "scope": "core",
      "tui_visible": true,
      "menu_order": 90,
      "summary": "Open an interactive login shell inside a distro.",
      "raw_usage": ["chroot login <distro>"]
    },
    {
      "id": "exec",
      "group": "core",
      "scope": "core",
      "tui_visible": true,
      "menu_order": 100,
      "summary": "Run one command inside a distro.",
      "raw_usage": ["chroot exec <distro> -- <cmd...>"]
    },
    {
      "id": "mount",
      "group": "core",
      "scope": "core",
      "tui_visible": true,
      "menu_order": 110,
      "summary": "Mount a distro runtime.",
      "raw_usage": ["chroot mount [<distro>]"]
    },
    {
      "id": "unmount",
      "group": "core",
      "scope": "core",
      "tui_visible": true,
      "menu_order": 120,
      "summary": "Unmount a distro runtime.",
      "raw_usage": ["chroot unmount [<distro>] [--kill-sessions|--no-kill-sessions]"]
    },
    {
      "id": "backup",
      "group": "core",
      "scope": "core",
      "tui_visible": true,
      "menu_order": 140,
      "summary": "Create a distro backup archive.",
      "raw_usage": ["chroot backup [<distro>] [--out <dir>] [--mode full|rootfs|state]"]
    },
    {
      "id": "restore",
      "group": "core",
      "scope": "core",
      "tui_visible": true,
      "menu_order": 150,
      "summary": "Restore a distro from a backup archive.",
      "raw_usage": ["chroot restore [<distro>] [--file <backup.tar|backup.tar.zst|backup.tar.xz>]"]
    },
    {
      "id": "busybox",
      "group": "core",
      "scope": "core",
      "tui_visible": true,
      "menu_order": 157,
      "summary": "Manage Aurora's BusyBox fallback for required host backend tools.",
      "raw_usage": [
        "chroot busybox",
        "chroot busybox fetch",
        "chroot busybox <path>",
        "chroot busybox status"
      ]
    },
    {
      "id": "logs",
      "group": "core",
      "scope": "core",
      "tui_visible": true,
      "menu_order": 160,
      "summary": "Show grouped Aurora invocation logs.",
      "raw_usage": ["chroot logs [<count>]"]
    },
    {
      "id": "info",
      "group": "core",
      "scope": "core",
      "tui_visible": true,
      "menu_order": 165,
      "summary": "Open the live info-hub for the current device, Aurora runtime, and distro state.",
      "raw_usage": [
        "chroot info",
        "chroot info refresh",
        "chroot info --json",
        "chroot info section <__INFO_SECTION_USAGE__>"
      ]
    },
    {
      "id": "clear-cache",
      "group": "core",
      "scope": "core",
      "tui_visible": true,
      "menu_order": 170,
      "summary": "Remove cached downloads and disposable runtime files.",
      "raw_usage": ["chroot clear-cache [--yes|-y]"]
    },
    {
      "id": "remove",
      "group": "core",
      "scope": "core",
      "tui_visible": true,
      "menu_order": 180,
      "summary": "Remove one installed distro.",
      "raw_usage": ["chroot remove [<distro>] [--full]"]
    },
    {
      "id": "nuke",
      "group": "core",
      "scope": "core",
      "tui_visible": true,
      "menu_order": 190,
      "summary": "Remove all Aurora runtime data.",
      "raw_usage": ["chroot nuke [--yes|-y]"]
    },
    {
      "id": "settings",
      "group": "settings",
      "scope": "core",
      "tui_visible": true,
      "menu_order": 155,
      "summary": "Show and edit Aurora settings.",
      "raw_usage": [
        "chroot settings",
        "chroot settings show|list",
        "chroot settings --json",
        "chroot settings set termux_home_bind <true|false>",
        "chroot settings set android_storage_bind <true|false>",
        "chroot settings set data_bind <true|false>",
        "chroot settings set android_full_bind <true|false>",
        "chroot settings set x11 <true|false>",
        "chroot settings set x11_dpi <96..480>",
        "chroot settings set download_retries <1..10>",
        "chroot settings set download_timeout_sec <5..300>",
        "chroot settings set log_retention_days <1..365>",
        "chroot settings set tor_rotation_min <1..120>",
        "chroot settings set tor_bootstrap_timeout_sec <10..600>"
      ]
    },
    {
      "id": "service",
      "group": "service",
      "scope": "distro",
      "scope_token": "service",
      "tui_visible": true,
      "menu_order": 70,
      "summary": "Manage Aurora services inside a distro.",
      "raw_usage": [
        "chroot <distro> service list|status [--json]",
        "chroot <distro> service add <name> <command>",
        "chroot <distro> service install",
        "chroot <distro> service install --json",
        "chroot <distro> service install --list",
        "chroot <distro> service install pcbridge",
        "chroot <distro> service install sshd",
        "chroot <distro> service install zsh",
        "chroot <distro> service install desktop --profiles --json",
        "chroot <distro> service install desktop [--profile <xfce|lxqt>] [--reinstall]",
        "chroot <distro> service on|start <name>",
        "chroot <distro> service off|stop <name>",
        "chroot <distro> service restart <name>",
        "chroot <distro> service remove|rm [<name>]"
      ]
    },
    {
      "id": "sessions",
      "group": "sessions",
      "scope": "distro",
      "scope_token": "sessions",
      "tui_visible": true,
      "menu_order": 80,
      "summary": "Inspect and manage tracked distro sessions.",
      "raw_usage": [
        "chroot <distro> sessions list|status [--json]",
        "chroot <distro> sessions kill [<session_id>]",
        "chroot <distro> sessions kill-all [--grace <sec>]"
      ]
    },
    {
      "id": "tor",
      "group": "tor",
      "scope": "distro",
      "scope_token": "tor",
      "tui_visible": true,
      "menu_order": 60,
      "summary": "Manage distro-backed Tor mode.",
      "raw_usage": [
        "chroot <distro> tor status [--json]",
        "chroot <distro> tor on|start [--configured [apps|exit]] [--no-lan-bypass]",
        "chroot <distro> tor off|stop",
        "chroot <distro> tor restart [--configured [apps|exit]] [--no-lan-bypass]",
        "chroot <distro> tor freeze",
        "chroot <distro> tor newnym",
        "chroot <distro> tor doctor [--json]",
        "chroot <distro> tor apps list [--json] [--user|--system|--unknown]",
        "chroot <distro> tor apps refresh [--json]",
        "chroot <distro> tor apps set \"<query[,query...]>\" <bypassed|tunneled>",
        "chroot <distro> tor exit list [--json]",
        "chroot <distro> tor exit performance-ignore list [--json]",
        "chroot <distro> tor exit performance-ignore set \"<query[,query...]>\" <ignored|allowed>",
        "chroot <distro> tor exit refresh [--json]",
        "chroot <distro> tor exit set \"<query[,query...]>\" <selected|unselected>",
        "chroot <distro> tor exit set strict <on|off>",
        "chroot <distro> tor exit set performance <on|off>",
        "chroot <distro> tor remove|rm [--yes]"
      ]
    }
  ]
}
JSON
)"
  json="${json//__INFO_SECTION_USAGE__/$info_section_usage}"
  printf '%s\n' "$json"
}

chroot_commands_registry_python_query() {
  local mode="${1:-json}"
  shift || true
  chroot_require_python
  CHROOT_COMMANDS_REGISTRY_JSON="$(chroot_commands_registry_json)" \
  "$CHROOT_PYTHON_BIN" - "$mode" "$@" <<'PY'
import json
import os
import sys

mode = sys.argv[1]
args = sys.argv[2:]
doc = json.loads(os.environ.get("CHROOT_COMMANDS_REGISTRY_JSON", "{}"))
commands = doc.get("commands", [])
groups = doc.get("groups", [])

if mode == "json":
    print(json.dumps(doc, indent=2, sort_keys=True))
    raise SystemExit(0)

if mode == "tui":
    out = []
    for row in commands:
        if not row.get("tui_visible"):
            continue
        out.append(row)
    out.sort(key=lambda row: (int(row.get("menu_order", 0) or 0), str(row.get("id", "") or "")))
    print(json.dumps({"commands": out}, indent=2, sort_keys=True))
    raise SystemExit(0)

raise SystemExit(f"unknown registry query mode: {mode}")
PY
}

chroot_commands_registry_raw_usage_lines() {
  chroot_commands_registry_json | awk '
    function append_usage(text,   value) {
      value = text
      gsub(/\\"/, "\"", value)
      gsub(/\\\\/, "\\", value)
      if (value != "") {
        raw[++raw_count] = value
      }
    }

    function parse_usage_text(text,   value) {
      while (match(text, /"(([^"\\]|\\.)*)"/)) {
        value = substr(text, RSTART + 1, RLENGTH - 2)
        append_usage(value)
        text = substr(text, RSTART + RLENGTH)
      }
    }

    BEGIN {
      in_groups = 0
      in_commands = 0
      in_raw_usage = 0
      group_count = 0
      command_total = 0
      current_group = ""
      raw_count = 0
    }

    /^[[:space:]]*"groups":[[:space:]]*\[/ {
      in_groups = 1
      next
    }

    in_groups && /^[[:space:]]*\][[:space:]]*,?[[:space:]]*$/ {
      in_groups = 0
      next
    }

    in_groups {
      if (match($0, /"id":[[:space:]]*"([^"]+)"[[:space:]]*,[[:space:]]*"label":[[:space:]]*"([^"]+)"/)) {
        group_id = substr($0, RSTART, RLENGTH)
        sub(/^.*"id":[[:space:]]*"/, "", group_id)
        sub(/".*$/, "", group_id)

        group_label_value = substr($0, RSTART, RLENGTH)
        sub(/^.*"label":[[:space:]]*"/, "", group_label_value)
        sub(/".*$/, "", group_label_value)

        group_order_value = $0
        sub(/^.*"order":[[:space:]]*/, "", group_order_value)
        sub(/[^0-9].*$/, "", group_order_value)
        if (group_order_value == "") {
          group_order_value = group_count + 1
        }

        group_order[++group_count] = group_id
        group_rank[group_id] = group_order_value + 0
        group_label[group_id] = group_label_value
      }
      next
    }

    /^[[:space:]]*"commands":[[:space:]]*\[/ {
      in_commands = 1
      next
    }

    in_commands && !in_raw_usage && /^[[:space:]]*\][[:space:]]*[}]?[[:space:]]*$/ {
      in_commands = 0
      next
    }

    in_commands {
      if ($0 ~ /^[[:space:]]*{[[:space:]]*$/) {
        current_group = ""
        in_raw_usage = 0
        raw_count = 0
        next
      }

      if (match($0, /"group":[[:space:]]*"([^"]+)"/)) {
        current_group = substr($0, RSTART, RLENGTH)
        sub(/^.*"group":[[:space:]]*"/, "", current_group)
        sub(/".*$/, "", current_group)
        next
      }

      if ($0 ~ /"raw_usage":[[:space:]]*\[/) {
        in_raw_usage = 1
        raw_count = 0
        usage_line = $0
        sub(/^.*"raw_usage":[[:space:]]*\[/, "", usage_line)
        parse_usage_text(usage_line)
        if ($0 ~ /\][[:space:]]*,?[[:space:]]*$/) {
          in_raw_usage = 0
        }
        next
      }

      if (in_raw_usage) {
        parse_usage_text($0)
        if ($0 ~ /\][[:space:]]*,?[[:space:]]*$/) {
          in_raw_usage = 0
        }
        next
      }

      if ($0 ~ /^[[:space:]]*}[[:space:]]*,?[[:space:]]*$/) {
        if (current_group != "") {
          command_index = ++command_total
          command_group[command_index] = current_group
          command_usage_count[command_index] = raw_count
          for (idx = 1; idx <= raw_count; idx++) {
            command_usage[command_index, idx] = raw[idx]
          }
        }
        current_group = ""
        raw_count = 0
      }
      next
    }

    END {
      for (left = 1; left < group_count; left++) {
        best = left
        for (right = left + 1; right <= group_count; right++) {
          best_id = group_order[best]
          right_id = group_order[right]
          if (group_rank[right_id] < group_rank[best_id]) {
            best = right
          }
        }
        if (best != left) {
          tmp = group_order[left]
          group_order[left] = group_order[best]
          group_order[best] = tmp
        }
      }

      for (g = 1; g <= group_count; g++) {
        group_id = group_order[g]
        label = group_label[group_id]
        if (label == "") {
          continue
        }
        print label
        print ""
        for (command_index = 1; command_index <= command_total; command_index++) {
          if (command_group[command_index] != group_id) {
            continue
          }
          for (idx = 1; idx <= command_usage_count[command_index]; idx++) {
            usage = command_usage[command_index, idx]
            if (usage != "") {
              print "  " usage
            }
          }
        }
        print ""
      }
    }
  '
}

chroot_commands_usage_service() {
  printf '%s\n' "bash path/to/chroot <distro> service [list|status|on|start|off|stop|restart|add|install|remove|rm] [args...]"
}

chroot_commands_usage_sessions() {
  printf '%s\n' "bash path/to/chroot <distro> sessions [list|status|kill|kill-all] [args...]"
}

chroot_commands_usage_tor() {
  printf '%s\n' "bash path/to/chroot <distro> tor [status|on|start|off|stop|restart|freeze|newnym|doctor|apps|exit|remove|rm] [args...]"
}

chroot_commands_usage_for_scoped_feature() {
  local feature="${1:-}"
  case "$feature" in
    service) chroot_commands_usage_service ;;
    sessions) chroot_commands_usage_sessions ;;
    tor) chroot_commands_usage_tor ;;
    *) return 1 ;;
  esac
}

chroot_commands_registry_tui_json() {
  chroot_commands_registry_python_query tui
}

chroot_commands_registry_tui_specs_json() {
  cat <<'JSON'
{
  "specs": {
    "help": {
      "about": "Open the same full help text shown by `chroot help`. Switch View to Raw command list for the compact command-only reference.",
      "builder": {"kind": "help"},
      "fields": [
        {
          "choices": [
            ["guide", "Guide + docs"],
            ["raw", "Raw command list"]
          ],
          "default": "guide",
          "id": "view",
          "label": "View",
          "type": "choice"
        }
      ]
    },
    "init": {
      "about": "Show first-run setup guidance and dependency status.",
      "builder": {"kind": "none"},
      "fields": []
    },
    "doctor": {
      "builder": {"kind": "doctor"},
      "fields": [
        {"default": false, "id": "json", "label": "JSON output", "type": "bool"},
        {"default": false, "id": "repair", "label": "Repair stale lockdirs", "type": "bool"}
      ]
    },
    "distros": {
      "about": "Browse the dynamic distro catalog and download or install from Aurora's current entries.",
      "builder": {"kind": "none"},
      "fields": []
    },
    "status": {
      "builder": {"kind": "status"},
      "fields": [
        {
          "choices": [
            ["all", "All distros"],
            ["distro", "Single distro"]
          ],
          "default": "all",
          "id": "scope",
          "label": "Scope",
          "type": "choice"
        },
        {
          "default": "",
          "id": "distro",
          "label": "Distro id",
          "show_if": {"equals": "distro", "id": "scope"},
          "type": "text"
        },
        {"default": false, "id": "json", "label": "JSON output", "type": "bool"},
        {
          "default": false,
          "id": "live",
          "label": "Include live fields (--live)",
          "show_if": {"equals": true, "id": "json"},
          "type": "bool"
        }
      ]
    },
    "logs": {
      "builder": {"kind": "logs"},
      "fields": [
        {
          "default": "",
          "id": "count",
          "label": "Group count (1-50, blank = 10)",
          "type": "text"
        }
      ]
    },
    "info": {
      "about": "Open the live info-hub for the current device, Aurora runtime health, and distro state.",
      "builder": {"kind": "none"},
      "fields": []
    },
    "install-local": {
      "builder": {"kind": "install-local"},
      "fields": [
        {"default": "", "id": "distro", "label": "Distro id", "type": "text"},
        {"default": "", "id": "file", "label": "Tarball path or cache dir", "type": "text"},
        {"default": "", "id": "sha256", "label": "SHA256 (optional)", "type": "text"},
        {"default": "", "id": "stdin_reply", "label": "Prompt reply (optional)", "type": "text"}
      ]
    },
    "login": {
      "builder": {"kind": "single-distro"},
      "fields": [
        {
          "choices": [["", "<loading installed distros>"]],
          "default": "",
          "id": "distro",
          "label": "Installed distro",
          "type": "choice"
        }
      ]
    },
    "mount": {
      "builder": {"kind": "single-distro"},
      "fields": [
        {
          "choices": [["", "<loading installed distros>"]],
          "default": "",
          "id": "distro",
          "label": "Installed distro",
          "type": "choice"
        }
      ]
    },
    "unmount": {
      "builder": {"kind": "unmount"},
      "fields": [
        {
          "choices": [["", "<loading installed distros>"]],
          "default": "",
          "id": "distro",
          "label": "Installed distro",
          "type": "choice"
        },
        {"default": false, "id": "kill_sessions", "label": "Kill sessions before unmount", "type": "bool"}
      ]
    },
    "backup": {
      "builder": {"kind": "backup"},
      "fields": [
        {
          "choices": [["", "<loading installed distros>"]],
          "default": "",
          "id": "distro",
          "label": "Installed distro",
          "type": "choice"
        },
        {
          "choices": [
            ["full", "Full"],
            ["rootfs", "Rootfs"],
            ["state", "State"]
          ],
          "default": "full",
          "id": "mode",
          "label": "Backup mode",
          "type": "choice"
        },
        {"default": "", "id": "out", "label": "Output directory (optional)", "type": "text"}
      ]
    },
    "remove": {
      "builder": {"kind": "remove"},
      "fields": [
        {
          "choices": [["", "<loading installed distros>"]],
          "default": "",
          "id": "distro",
          "label": "Installed distro",
          "type": "choice"
        },
        {"default": false, "id": "full", "label": "Delete related cache files", "type": "bool"}
      ]
    },
    "nuke": {
      "about": "Danger: remove all Aurora runtime data (distros/backups/cache/state).",
      "builder": {"kind": "none"},
      "fields": []
    },
    "settings": {
      "about": "Open the integrated settings editor.",
      "builder": {"kind": "none"},
      "fields": []
    },
    "busybox": {
      "about": "Open the BusyBox fallback manager.",
      "builder": {"kind": "none"},
      "fields": []
    },
    "clear-cache": {
      "about": "Delete cached downloads, tmp leftovers, interrupted install staging dirs, and stale runtime logs. Keeps backups, settings, installed distro state, and retained unified Aurora logs.",
      "builder": {"kind": "clear-cache"},
      "fields": []
    }
  }
}
JSON
}

chroot_commands_log_infer_core_action() {
  local cmd="${1:-help}"
  shift || true
  local arg="" has_json=0 has_live=0 has_repair=0 has_install=0 has_download=0 has_refresh=0

  case "$cmd" in
    help|-h|--help)
      if [[ "${1:-}" == "raw" ]]; then
        printf 'help.raw\n'
      else
        printf 'help\n'
      fi
      ;;
    distros)
      for arg in "$@"; do
        case "$arg" in
          --install) has_install=1 ;;
          --download) has_download=1 ;;
          --refresh) has_refresh=1 ;;
        esac
      done
      if [[ "$has_install" == "1" ]]; then
        printf 'distros.install\n'
      elif [[ "$has_download" == "1" ]]; then
        printf 'distros.download\n'
      elif [[ "$has_refresh" == "1" ]]; then
        printf 'distros.refresh\n'
      else
        printf 'distros\n'
      fi
      ;;
    settings)
      case "${1:-}" in
        set|show)
          printf 'settings.%s\n' "$(chroot_log_normalize_action_name "$1")"
          ;;
        --json)
          printf 'settings.json\n'
          ;;
        list)
          printf 'settings.show\n'
          ;;
        *)
          printf 'settings\n'
          ;;
      esac
      ;;
    busybox)
      case "${1:-}" in
        fetch) printf 'busybox.fetch\n' ;;
        status) printf 'busybox.status\n' ;;
        "") printf 'busybox\n' ;;
        *) printf 'busybox.path\n' ;;
      esac
      ;;
    doctor)
      for arg in "$@"; do
        case "$arg" in
          --json) has_json=1 ;;
          --repair-locks) has_repair=1 ;;
        esac
      done
      if [[ "$has_json" == "1" && "$has_repair" == "1" ]]; then
        printf 'doctor.json.repair-locks\n'
      elif [[ "$has_json" == "1" ]]; then
        printf 'doctor.json\n'
      elif [[ "$has_repair" == "1" ]]; then
        printf 'doctor.repair-locks\n'
      else
        printf 'doctor\n'
      fi
      ;;
    status)
      for arg in "$@"; do
        case "$arg" in
          --json) has_json=1 ;;
          --live) has_live=1 ;;
        esac
      done
      if [[ "$has_json" == "1" ]]; then
        if [[ "$has_live" == "1" ]]; then
          printf 'status.json.live\n'
        else
          printf 'status.json\n'
        fi
      else
        printf 'status\n'
      fi
      ;;
    info)
      chroot_commands_registry_core_log_action_resolve info "$@" || printf 'info\n'
      ;;
    init|logs|install-local|login|exec|mount|unmount|backup|restore|remove|nuke|clear-cache)
      printf '%s\n' "$(chroot_log_normalize_action_name "$cmd")"
      ;;
    "")
      printf 'help\n'
      ;;
    *)
      printf '%s\n' "$(chroot_log_normalize_action_name "$cmd")"
      ;;
  esac
}

chroot_commands_log_infer_scoped_action() {
  local family="$1"
  local sub1="${2:-}"
  local sub2="${3:-}"
  local sub3="${4:-}"

  case "$family" in
    tor)
      case "$sub1" in
        ""|status) printf 'tor.status\n' ;;
        on|start) printf 'tor.on\n' ;;
        off|stop) printf 'tor.off\n' ;;
        restart|freeze|newnym|doctor)
          printf 'tor.%s\n' "$(chroot_log_normalize_action_name "$sub1")"
          ;;
        remove|rm)
          printf 'tor.remove\n'
          ;;
        apps)
          case "$sub2" in
            ""|list) printf 'tor.apps.list\n' ;;
            refresh|set|apply)
              printf 'tor.apps.%s\n' "$(chroot_log_normalize_action_name "$sub2")"
              ;;
            *)
              printf 'tor.apps.invalid\n'
              ;;
          esac
          ;;
        exit)
          case "$sub2" in
            ""|list) printf 'tor.exit.list\n' ;;
            refresh|set|apply)
              printf 'tor.exit.%s\n' "$(chroot_log_normalize_action_name "$sub2")"
              ;;
            performance-ignore)
              case "$sub3" in
                ""|list) printf 'tor.exit.performance-ignore.list\n' ;;
                set) printf 'tor.exit.performance-ignore.set\n' ;;
                *) printf 'tor.exit.performance-ignore.invalid\n' ;;
              esac
              ;;
            *)
              printf 'tor.exit.invalid\n'
              ;;
          esac
          ;;
        *)
          printf 'tor.invalid\n'
          ;;
      esac
      ;;
    service)
      case "$sub1" in
        ""|list)
          if [[ "$sub2" == "--json" ]]; then
            printf 'service.list.json\n'
          else
            printf 'service.list\n'
          fi
          ;;
        status|restart|add|install)
          case "$sub1" in
            status)
              if [[ "$sub2" == "--json" ]]; then
                printf 'service.status.json\n'
              else
                printf 'service.status\n'
              fi
              ;;
            install)
              case "$sub2" in
                --json) printf 'service.install.catalog-json\n' ;;
                --list) printf 'service.install.list\n' ;;
                desktop)
                  if [[ "$sub3" == "--profiles" ]]; then
                    printf 'service.install.desktop.profiles\n'
                  else
                    printf 'service.install\n'
                  fi
                  ;;
                *)
                  printf 'service.install\n'
                  ;;
              esac
              ;;
            *)
              printf 'service.%s\n' "$(chroot_log_normalize_action_name "$sub1")"
              ;;
          esac
          ;;
        on|start) printf 'service.start\n' ;;
        off|stop) printf 'service.stop\n' ;;
        remove|rm) printf 'service.remove\n' ;;
        *) printf 'service.invalid\n' ;;
      esac
      ;;
    sessions)
      case "$sub1" in
        ""|list|status)
          printf 'sessions.%s\n' "$(chroot_log_normalize_action_name "${sub1:-list}")"
          ;;
        kill|kill-all)
          printf 'sessions.%s\n' "$(chroot_log_normalize_action_name "$sub1")"
          ;;
        *)
          printf 'sessions.invalid\n'
          ;;
      esac
      ;;
    *)
      printf '%s\n' "$(chroot_log_normalize_action_name "$family")"
      ;;
  esac
}

chroot_commands_registry_selfcheck() {
  chroot_require_python
  CHROOT_COMMANDS_REGISTRY_JSON="$(chroot_commands_registry_json)" \
  "$CHROOT_PYTHON_BIN" - <<'PY'
import json
import os
import sys

doc = json.loads(os.environ.get("CHROOT_COMMANDS_REGISTRY_JSON", "{}"))
groups = doc.get("groups", [])
commands = doc.get("commands", [])

group_ids = set()
for row in groups:
    gid = str(row.get("id", "") or "").strip()
    if not gid:
        raise SystemExit("registry selfcheck failed: group without id")
    if gid in group_ids:
        raise SystemExit(f"registry selfcheck failed: duplicate group id {gid}")
    group_ids.add(gid)

command_ids = set()
scope_tokens = set()
for row in commands:
    cid = str(row.get("id", "") or "").strip()
    if not cid:
        raise SystemExit("registry selfcheck failed: command without id")
    if cid in command_ids:
        raise SystemExit(f"registry selfcheck failed: duplicate command id {cid}")
    command_ids.add(cid)

    group = str(row.get("group", "") or "").strip()
    if group not in group_ids:
        raise SystemExit(f"registry selfcheck failed: command {cid} references unknown group {group}")

    for usage in row.get("raw_usage", []):
        if not str(usage or "").strip():
            raise SystemExit(f"registry selfcheck failed: command {cid} has blank raw usage")

    scope_token = str(row.get("scope_token", "") or "").strip()
    if scope_token:
        if scope_token in scope_tokens:
            raise SystemExit(f"registry selfcheck failed: duplicate scope_token {scope_token}")
        scope_tokens.add(scope_token)

print("ok")
PY
}
