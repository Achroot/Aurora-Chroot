#!/usr/bin/env bash

chroot_busybox_pre_managed_tool_provider_parts_tsv() {
  local tool="$1"
  local system_bin=""

  system_bin="$(chroot_system_tool_backend_bin "$tool" 2>/dev/null || true)"
  if chroot_system_tool_backend_override_selected "$tool" && chroot_system_tool_backend_supports "$tool"; then
    printf '%s\t%s\n' "$system_bin" ""
    return 0
  fi

  if chroot_system_tool_backend_supports "$tool"; then
    printf '%s\t%s\n' "$system_bin" ""
    return 0
  fi

  if chroot_toybox_supports_applet "$tool"; then
    printf '%s\t%s\n' "$CHROOT_TOYBOX_BIN" "$tool"
    return 0
  fi

  if chroot_busybox_supports_applet "$tool"; then
    printf '%s\t%s\n' "$CHROOT_BUSYBOX_BIN" "$tool"
    return 0
  fi

  return 1
}

chroot_busybox_provider_kind() {
  local tool="$1"
  local bin="$2"
  local subcmd="${3:-}"
  local system_bin source_type managed_binary managed_applets tool_path
  system_bin="$(chroot_system_tool_backend_bin "$tool" 2>/dev/null || true)"

  if [[ -n "$bin" ]] && chroot_system_tool_backend_override_selected "$tool" && [[ "$bin" == "$system_bin" ]]; then
    printf 'override\n'
    return 0
  fi
  if [[ -n "$bin" && "$bin" == "$system_bin" && -z "$subcmd" ]]; then
    printf 'native\n'
    return 0
  fi
  if [[ -n "${CHROOT_TOYBOX_BIN:-}" && "$bin" == "$CHROOT_TOYBOX_BIN" && -n "$subcmd" ]]; then
    printf 'toybox\n'
    return 0
  fi
  if [[ -n "${CHROOT_BUSYBOX_BIN:-}" && "$bin" == "$CHROOT_BUSYBOX_BIN" && -n "$subcmd" ]]; then
    printf 'built-in BusyBox\n'
    return 0
  fi

  source_type="$(chroot_managed_busybox_source_type 2>/dev/null || true)"
  managed_binary="$(chroot_busybox_metadata_field active_binary_path 2>/dev/null || true)"
  managed_applets="$(chroot_busybox_metadata_field active_applets_dir 2>/dev/null || true)"
  tool_path="$(chroot_busybox_metadata_tool_path "$tool" 2>/dev/null || true)"
  if [[ "$source_type" == "path_dir" && -n "$tool_path" && "$bin" == "$tool_path" ]]; then
    printf 'managed BusyBox applet\n'
    return 0
  fi
  if [[ "$source_type" == "path_dir" && -n "$managed_applets" && "$bin" == "$managed_applets/$tool" ]]; then
    printf 'managed BusyBox applet\n'
    return 0
  fi
  if [[ -n "$managed_binary" && "$bin" == "$managed_binary" && -n "$subcmd" ]]; then
    printf 'managed BusyBox\n'
    return 0
  fi

  printf 'unknown\n'
}

chroot_busybox_provider_label_from_parts() {
  local bin="$1"
  local subcmd="${2:-}"
  if [[ -z "$bin" ]]; then
    printf 'none\n'
  elif [[ -n "$subcmd" ]]; then
    printf '%s %s\n' "$bin" "$subcmd"
  else
    printf '%s\n' "$bin"
  fi
}

chroot_busybox_native_missing_tools() {
  local tool bin subcmd
  while IFS= read -r tool; do
    [[ -n "$tool" ]] || continue
    IFS=$'\t' read -r bin subcmd <<<"$(chroot_busybox_pre_managed_tool_provider_parts_tsv "$tool" 2>/dev/null || true)"
    [[ -n "$bin" ]] || printf '%s\n' "$tool"
  done < <(chroot_busybox_required_tool_ids)
}

chroot_busybox_native_coverage_complete() {
  [[ -z "$(chroot_busybox_native_missing_tools)" ]]
}

chroot_busybox_managed_covers_tools() {
  local missing="$1"
  local tool
  [[ -n "$missing" ]] || return 0
  while IFS= read -r tool; do
    [[ -n "$tool" ]] || continue
    chroot_managed_busybox_supports_tool "$tool" || return 1
  done <<<"$missing"
  return 0
}

chroot_busybox_join_lines_comma() {
  local out="" value
  while IFS= read -r value; do
    [[ -n "$value" ]] || continue
    if [[ -n "$out" ]]; then
      out+=", "
    fi
    out+="$value"
  done
  printf '%s\n' "$out"
}

chroot_busybox_pre_managed_provider_summary_inline() {
  local out="" tool bin subcmd label kind
  while IFS= read -r tool; do
    [[ -n "$tool" ]] || continue
    IFS=$'\t' read -r bin subcmd <<<"$(chroot_busybox_pre_managed_tool_provider_parts_tsv "$tool" 2>/dev/null || true)"
    label="$(chroot_busybox_provider_label_from_parts "$bin" "$subcmd")"
    kind="$(chroot_busybox_provider_kind "$tool" "$bin" "$subcmd")"
    if [[ -n "$out" ]]; then
      out+=", "
    fi
    out+="$tool=$label ($kind)"
  done < <(chroot_busybox_required_tool_ids)
  printf '%s\n' "$out"
}

chroot_busybox_managed_state_text() {
  local missing="$1"
  local source_type
  source_type="$(chroot_managed_busybox_source_type 2>/dev/null || true)"
  if [[ -z "$source_type" ]]; then
    printf 'not configured\n'
    return 0
  fi
  if chroot_busybox_managed_covers_tools "$missing"; then
    printf 'available\n'
  else
    printf 'configured but invalid for the missing tools\n'
  fi
}

chroot_busybox_render_detection_banner() {
  local missing missing_csv managed_state provider_summary
  missing="$(chroot_busybox_native_missing_tools)"
  if [[ -z "$missing" ]]; then
    provider_summary="$(chroot_busybox_pre_managed_provider_summary_inline)"
    printf 'BusyBox check: BusyBox is not needed for Aurora; required backend tools are already covered by %s.\n' "$provider_summary"
    return 0
  fi

  missing_csv="$(printf '%s\n' "$missing" | chroot_busybox_join_lines_comma)"
  managed_state="$(chroot_busybox_managed_state_text "$missing")"
  printf 'BusyBox check: Aurora is missing required backend tools: %s. Managed BusyBox fallback is %s.\n' "$missing_csv" "$managed_state"
}

chroot_busybox_selected_tools_tsv() {
  local tool bin subcmd label kind
  while IFS= read -r tool; do
    [[ -n "$tool" ]] || continue
    IFS=$'\t' read -r bin subcmd <<<"$(chroot_tool_backend_parts_tsv "$tool" 2>/dev/null || true)"
    label="$(chroot_busybox_provider_label_from_parts "$bin" "$subcmd")"
    kind="$(chroot_busybox_provider_kind "$tool" "$bin" "$subcmd")"
    printf '%s\t%s\t%s\t%s\t%s\n' "$tool" "$kind" "$label" "$bin" "$subcmd"
  done < <(chroot_busybox_required_tool_ids)
}

chroot_busybox_active_fallback_tools() {
  local tool kind _label _bin _subcmd
  while IFS=$'\t' read -r tool kind _label _bin _subcmd; do
    case "$kind" in
      managed\ BusyBox*) printf '%s\n' "$tool" ;;
    esac
  done < <(chroot_busybox_selected_tools_tsv)
}

chroot_busybox_configured_valid() {
  local source_type
  source_type="$(chroot_managed_busybox_source_type 2>/dev/null || true)"
  [[ -n "$source_type" ]] || return 1
  chroot_busybox_active_validation_tsv >/dev/null 2>&1
}

chroot_busybox_requirement_summary() {
  local missing active source_type active_csv
  missing="$(chroot_busybox_native_missing_tools)"
  active="$(chroot_busybox_active_fallback_tools)"
  source_type="$(chroot_managed_busybox_source_type 2>/dev/null || true)"
  if [[ -z "$missing" ]]; then
    if [[ -n "$source_type" ]]; then
      printf 'BusyBox is configured but inactive because native/built-in providers already satisfy Aurora.\n'
    else
      printf 'BusyBox is not required because native/built-in providers already satisfy Aurora.\n'
    fi
    return 0
  fi
  if [[ -n "$active" ]]; then
    active_csv="$(printf '%s\n' "$active" | chroot_busybox_join_lines_comma)"
    printf 'BusyBox is currently used as fallback for: %s.\n' "$active_csv"
    return 0
  fi
  printf 'BusyBox fallback is missing or invalid for the current required tools.\n'
}

chroot_busybox_info_summary_line() {
  local missing active source_type source_label active_csv missing_csv
  missing="$(chroot_busybox_native_missing_tools)"
  active="$(chroot_busybox_active_fallback_tools)"
  source_type="$(chroot_managed_busybox_source_type 2>/dev/null || true)"
  source_label="$(chroot_busybox_source_label "$source_type")"

  if [[ -z "$missing" ]]; then
    if [[ -n "$source_type" ]]; then
      printf 'standby (%s); native tools cover required backends\n' "$source_label"
    else
      printf 'not required; native tools cover required backends\n'
    fi
    return 0
  fi

  if [[ -n "$active" ]]; then
    active_csv="$(printf '%s\n' "$active" | chroot_busybox_join_lines_comma)"
    printf 'active for %s (%s)\n' "$active_csv" "$source_label"
    return 0
  fi

  missing_csv="$(printf '%s\n' "$missing" | chroot_busybox_join_lines_comma)"
  if [[ -n "$source_type" ]]; then
    printf 'configured but invalid; missing %s\n' "$missing_csv"
  else
    printf 'required; missing %s\n' "$missing_csv"
  fi
}

chroot_busybox_source_label() {
  local source_type="$1"
  case "$source_type" in
    fetch) printf 'fetched\n' ;;
    path_file) printf 'user path binary\n' ;;
    path_dir) printf 'user path applet directory\n' ;;
    "") printf 'none\n' ;;
    *) printf '%s\n' "$source_type" ;;
  esac
}

chroot_busybox_render_status() {
  local source_type original_path active_binary active_applets fetch_url repo arch version_line file_size sha validation_status validation_time
  local missing missing_csv validation tool status detail selected kind label bin subcmd

  printf '\nBusyBox status\n'
  printf 'Required backend tools: %s\n' "$(chroot_busybox_required_tool_csv)"
  chroot_busybox_requirement_summary

  missing="$(chroot_busybox_native_missing_tools)"
  if [[ -z "$missing" ]]; then
    printf 'Native/built-in coverage: complete\n'
    printf 'BusyBox required: no\n'
  else
    missing_csv="$(printf '%s\n' "$missing" | chroot_busybox_join_lines_comma)"
    printf 'Native/built-in coverage: incomplete (missing: %s)\n' "$missing_csv"
    printf 'BusyBox required: yes\n'
  fi

  if IFS='|' read -r source_type original_path active_binary active_applets fetch_url repo arch version_line file_size sha validation_status validation_time <<<"$(chroot_busybox_metadata_summary_tsv 2>/dev/null || true)" && [[ -n "$source_type" ]]; then
    printf 'Active managed BusyBox source: %s\n' "$(chroot_busybox_source_label "$source_type")"
    [[ -n "$original_path" ]] && printf 'Original source path: %s\n' "$original_path"
    [[ -n "$active_binary" ]] && printf 'Managed binary: %s\n' "$active_binary"
    [[ -n "$active_applets" ]] && printf 'Managed applets directory: %s\n' "$active_applets"
    [[ -n "$fetch_url" ]] && printf 'Fetch URL: %s\n' "$fetch_url"
    [[ -n "$repo" ]] && printf 'Repository binary: %s\n' "$repo"
    [[ -n "$arch" ]] && printf 'Detected architecture: %s\n' "$arch"
    [[ -n "$version_line" ]] && printf 'BusyBox version/help: %s\n' "$version_line"
    [[ -n "$file_size" && "$file_size" != "0" ]] && printf 'File size: %s bytes\n' "$file_size"
    [[ -n "$sha" ]] && printf 'SHA256: %s\n' "$sha"
    [[ -n "$validation_status" ]] && printf 'Cached validation status: %s\n' "$validation_status"
    [[ -n "$validation_time" ]] && printf 'Cached validation time: %s\n' "$validation_time"
  else
    printf 'Active managed BusyBox source: none\n'
  fi

  printf '\nSelected backend per required tool:\n'
  while IFS=$'\t' read -r tool kind label bin subcmd; do
    printf '  %-8s %s (%s)\n' "$tool" "$label" "$kind"
  done < <(chroot_busybox_selected_tools_tsv)

  printf '\nBusyBox validation matrix:\n'
  validation="$(chroot_busybox_active_validation_tsv 2>/dev/null || true)"
  if [[ -z "$validation" ]]; then
    printf '  none: no managed BusyBox configured\n'
  else
    while IFS=$'\t' read -r tool status detail; do
      [[ -n "$tool" ]] || continue
      printf '  %-12s %-5s %s\n' "$tool" "$status" "$detail"
    done <<<"$validation"
  fi

  if [[ -z "$missing" ]]; then
    printf '\nBusyBox fetch/path is not required; Aurora will keep any managed BusyBox as standby fallback.\n'
  elif ! chroot_busybox_managed_covers_tools "$missing"; then
    printf '\nAction: run busybox status, then run busybox fetch or busybox <path-to-busybox-or-applet-directory>.\n'
  fi
}

chroot_busybox_diagnostics_json() {
  local selected_file validation_file metadata_file missing active
  selected_file="$CHROOT_TMP_DIR/busybox-selected.$$.tsv"
  validation_file="$CHROOT_TMP_DIR/busybox-validation.$$.tsv"
  metadata_file="$CHROOT_TMP_DIR/busybox-metadata.$$.json"
  chroot_busybox_selected_tools_tsv >"$selected_file"
  chroot_busybox_active_validation_tsv >"$validation_file" 2>/dev/null || true
  chroot_busybox_metadata_json >"$metadata_file"
  missing="$(chroot_busybox_native_missing_tools)"
  active="$(chroot_busybox_active_fallback_tools)"
  chroot_detect_python
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$selected_file" "$validation_file" "$metadata_file" "$missing" "$active" <<'PY'
import json
import sys

selected_file, validation_file, metadata_file, missing_text, active_text = sys.argv[1:6]

selected = []
try:
    with open(selected_file, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line:
                continue
            parts = line.split("\t")
            while len(parts) < 5:
                parts.append("")
            tool, kind, label, binary, subcmd = parts[:5]
            selected.append({"tool": tool, "kind": kind, "label": label, "binary": binary, "subcommand": subcmd})
except Exception:
    selected = []

validation = []
try:
    with open(validation_file, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line:
                continue
            parts = line.split("\t", 2)
            while len(parts) < 3:
                parts.append("")
            validation.append({"tool": parts[0], "status": parts[1], "detail": parts[2]})
except Exception:
    validation = []

try:
    with open(metadata_file, "r", encoding="utf-8") as fh:
        metadata = json.load(fh)
except Exception:
    metadata = {}

missing = [line.strip() for line in missing_text.splitlines() if line.strip()]
active = [line.strip() for line in active_text.splitlines() if line.strip()]
configured = bool(metadata.get("source_type"))
valid = bool(validation) and all(row.get("status") == "pass" for row in validation)
native_coverage = not missing

print(json.dumps({
    "fallback_required": not native_coverage,
    "fallback_configured": configured,
    "fallback_valid": valid,
    "fallback_active_tools": active,
    "native_provider_coverage": native_coverage,
    "native_missing_tools": missing,
    "managed_source": metadata,
    "selected_providers": selected,
    "validation_matrix": validation,
}, indent=2, sort_keys=True))
PY
  rm -f -- "$selected_file" "$validation_file" "$metadata_file" 2>/dev/null || true
}

chroot_busybox_doctor_summary() {
  local missing active active_csv missing_csv
  missing="$(chroot_busybox_native_missing_tools)"
  active="$(chroot_busybox_active_fallback_tools)"
  if [[ -z "$missing" ]]; then
    printf 'BusyBox: fetch/path is not required; native, Toybox, or built-in BusyBox providers cover all required backend tools.\n'
    return 0
  fi
  if [[ -n "$active" ]]; then
    active_csv="$(printf '%s\n' "$active" | chroot_busybox_join_lines_comma)"
    printf 'BusyBox: managed fallback is active for %s.\n' "$active_csv"
    return 0
  fi
  missing_csv="$(printf '%s\n' "$missing" | chroot_busybox_join_lines_comma)"
  printf 'BusyBox: fallback is required for %s but no valid managed BusyBox is configured. Run busybox fetch or busybox <path-to-busybox-or-applet-directory>.\n' "$missing_csv"
}

chroot_busybox_missing_tool_message() {
  local tools="$*"
  local normalized missing_csv
  if [[ -n "$tools" ]]; then
    normalized="$(printf '%s\n' "$tools" | tr ' ' '\n' | awk 'NF && !seen[$0]++')"
  else
    normalized="$(chroot_busybox_native_missing_tools)"
  fi
  missing_csv="$(printf '%s\n' "$normalized" | chroot_busybox_join_lines_comma)"
  [[ -n "$missing_csv" ]] || missing_csv="required host tools"
  cat <<EOF_MSG
Aurora could not find usable backend(s): $missing_csv.
BusyBox fallback can provide this if your device does not include working built-in tools.
Run: busybox status
Then run: busybox fetch
Or provide your own: busybox <path-to-busybox-or-applet-directory>
EOF_MSG
}

chroot_busybox_render_missing_tool_guidance() {
  chroot_busybox_missing_tool_message "$@"
}
