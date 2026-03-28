chroot_root_diag_clear() {
  CHROOT_ROOT_DIAGNOSTICS=""
}

chroot_root_diag_add() {
  local msg="$1"
  if [[ -n "$CHROOT_ROOT_DIAGNOSTICS" ]]; then
    CHROOT_ROOT_DIAGNOSTICS+="; "
  fi
  CHROOT_ROOT_DIAGNOSTICS+="$msg"
}

chroot_root_probe_clear() {
  CHROOT_ROOT_PROBE_TRACE=""
}

chroot_root_probe_add() {
  local phase="$1"
  local candidate="$2"
  local result="$3"
  local detail="$4"
  local line
  line="${phase}"$'\t'"${candidate}"$'\t'"${result}"$'\t'"${detail}"
  if [[ -n "$CHROOT_ROOT_PROBE_TRACE" ]]; then
    CHROOT_ROOT_PROBE_TRACE+=$'\n'
  fi
  CHROOT_ROOT_PROBE_TRACE+="$line"
}

chroot_root_resolve_candidate_path() {
  local candidate="$1"
  [[ -n "$candidate" ]] || return 1
  if [[ "$candidate" == */* ]]; then
    [[ -x "$candidate" ]] || return 1
    printf '%s\n' "$candidate"
    return 0
  fi
  command -v "$candidate" 2>/dev/null || return 1
}

chroot_root_launcher_probe() {
  local launcher="$1"
  local subcmd="${2:-}"
  local host_sh
  local -a launcher_cmd subcmd_parts

  host_sh="${CHROOT_HOST_SH:-}"
  if [[ -z "$host_sh" ]]; then
    host_sh="$(command -v sh 2>/dev/null || true)"
  fi
  [[ -n "$host_sh" ]] || host_sh="sh"

  launcher_cmd=("$launcher")
  if [[ -n "$subcmd" ]]; then
    read -r -a subcmd_parts <<<"$subcmd"
    if (( ${#subcmd_parts[@]} > 0 )); then
      launcher_cmd+=("${subcmd_parts[@]}")
    fi
  fi

  "${launcher_cmd[@]}" -c "id -u >/dev/null 2>&1" >/dev/null 2>&1 && return 0
  "${launcher_cmd[@]}" "$host_sh" -c "id -u >/dev/null 2>&1" >/dev/null 2>&1 && return 0
  return 1
}

chroot_root_override_parts() {
  local raw="${CHROOT_ROOT_LAUNCHER:-}"
  local -a parts
  local idx subcmd=""
  raw="${raw#"${raw%%[![:space:]]*}"}"
  raw="${raw%"${raw##*[![:space:]]}"}"
  [[ -n "$raw" ]] || return 1

  read -r -a parts <<<"$raw"
  (( ${#parts[@]} > 0 )) || return 1
  if (( ${#parts[@]} > 2 )); then
    chroot_root_diag_add "override launcher has extra args; preserving all tokens"
  fi
  if (( ${#parts[@]} > 1 )); then
    subcmd="${parts[1]}"
    for (( idx = 2; idx < ${#parts[@]}; idx++ )); do
      subcmd+=" ${parts[$idx]}"
    done
  fi
  printf '%s\t%s\n' "${parts[0]}" "$subcmd"
}

chroot_resolve_root_launcher() {
  if [[ "$(id -u)" == "0" ]]; then
    CHROOT_ROOT_LAUNCHER_BIN=""
    CHROOT_ROOT_LAUNCHER_SUBCMD=""
    CHROOT_ROOT_LAUNCHER_KIND="direct-root"
    CHROOT_ROOT_BACKEND_READY=1
    CHROOT_ROOT_DIAGNOSTICS="already running as uid 0"
    CHROOT_ROOT_PROBE_TRACE=$'direct-root\tuid=0\tpass\talready running as root'
    return 0
  fi

  if [[ "$CHROOT_ROOT_BACKEND_READY" == "1" && -n "$CHROOT_ROOT_LAUNCHER_BIN" ]]; then
    if [[ -z "$CHROOT_ROOT_PROBE_TRACE" ]]; then
      CHROOT_ROOT_PROBE_TRACE=$'cache\tresolved-backend\tpass\tusing cached resolved root launcher'
    fi
    return 0
  fi

  chroot_detect_bins
  chroot_root_diag_clear
  chroot_root_probe_clear
  CHROOT_ROOT_LAUNCHER_SUBCMD=""

  local override_token override_subcmd resolved candidate probe_subcmd resolved_base
  IFS=$'\t' read -r override_token override_subcmd <<<"$(chroot_root_override_parts || true)"
  if [[ -n "$override_token" ]]; then
    resolved="$(chroot_root_resolve_candidate_path "$override_token" || true)"
    if [[ -n "$resolved" ]] && chroot_root_launcher_probe "$resolved" "$override_subcmd"; then
      CHROOT_ROOT_LAUNCHER_BIN="$resolved"
      CHROOT_ROOT_LAUNCHER_SUBCMD="$override_subcmd"
      CHROOT_ROOT_LAUNCHER_KIND="override"
      CHROOT_ROOT_BACKEND_READY=1
      if [[ -n "$override_subcmd" ]]; then
        chroot_root_diag_add "using override launcher: $resolved $override_subcmd"
      else
        chroot_root_diag_add "using override launcher: $resolved"
      fi
      chroot_root_probe_add "override" "$override_token ${override_subcmd:-}" "pass" "override launcher probe passed"
      return 0
    fi
    chroot_root_diag_add "override launcher is unusable: $override_token ${override_subcmd:-}"
    if [[ -n "$resolved" ]]; then
      chroot_root_probe_add "override" "$override_token ${override_subcmd:-}" "fail" "candidate resolved at $resolved but probe failed"
    else
      chroot_root_probe_add "override" "$override_token ${override_subcmd:-}" "fail" "candidate not found or not executable"
    fi
  else
    chroot_root_probe_add "override" "CHROOT_ROOT_LAUNCHER" "skip" "not set"
  fi

  for candidate in "ksu" "kernelsu" "apatch-su" "apatch_su"; do
    resolved="$(chroot_root_resolve_candidate_path "$candidate" || true)"
    if [[ -z "$resolved" ]]; then
      chroot_root_probe_add "provider-native" "$candidate" "skip" "not found"
      continue
    fi
    if chroot_root_launcher_probe "$resolved" ""; then
      CHROOT_ROOT_LAUNCHER_BIN="$resolved"
      CHROOT_ROOT_LAUNCHER_SUBCMD=""
      CHROOT_ROOT_LAUNCHER_KIND="provider-native"
      CHROOT_ROOT_BACKEND_READY=1
      chroot_root_diag_add "using provider launcher: $resolved"
      chroot_root_probe_add "provider-native" "$candidate" "pass" "resolved=$resolved"
      return 0
    fi
    chroot_root_probe_add "provider-native" "$candidate" "fail" "resolved=$resolved probe failed"
  done
  chroot_root_diag_add "provider-native launchers not usable"

  for candidate in "${CHROOT_SYSTEM_XBIN_DEFAULT}/su" "${CHROOT_SYSTEM_BIN_DEFAULT}/su" "/system_ext/bin/su" "/vendor/bin/su" "/sbin/su" "/su/bin/su" "/debug_ramdisk/su" "/system/bin/.ext/.su" "su" "tsu"; do
    resolved="$(chroot_root_resolve_candidate_path "$candidate" || true)"
    if [[ -z "$resolved" ]]; then
      chroot_root_probe_add "compatibility-su" "$candidate" "skip" "not found"
      continue
    fi
    if chroot_root_launcher_probe "$resolved" ""; then
      CHROOT_ROOT_LAUNCHER_BIN="$resolved"
      CHROOT_ROOT_LAUNCHER_SUBCMD=""
      CHROOT_ROOT_LAUNCHER_KIND="compatibility-su"
      CHROOT_ROOT_BACKEND_READY=1
      chroot_root_diag_add "using compatibility launcher: $resolved"
      chroot_root_probe_add "compatibility-su" "$candidate" "pass" "resolved=$resolved"
      return 0
    fi
    chroot_root_probe_add "compatibility-su" "$candidate" "fail" "resolved=$resolved probe failed"

    resolved_base="$(basename "$resolved" 2>/dev/null || true)"
    case "$resolved_base" in
      su|.su)
        for probe_subcmd in "--mount-master" "-mm"; do
          if chroot_root_launcher_probe "$resolved" "$probe_subcmd"; then
            CHROOT_ROOT_LAUNCHER_BIN="$resolved"
            CHROOT_ROOT_LAUNCHER_SUBCMD="$probe_subcmd"
            CHROOT_ROOT_LAUNCHER_KIND="compatibility-su"
            CHROOT_ROOT_BACKEND_READY=1
            chroot_root_diag_add "using compatibility launcher: $resolved $probe_subcmd"
            chroot_root_probe_add "compatibility-su" "$candidate $probe_subcmd" "pass" "resolved=$resolved"
            return 0
          fi
          chroot_root_probe_add "compatibility-su" "$candidate $probe_subcmd" "fail" "resolved=$resolved probe failed"
        done
        ;;
    esac
  done
  for candidate in "${CHROOT_BUSYBOX_BIN:-}" "busybox" "toybox"; do
    resolved="$(chroot_root_resolve_candidate_path "$candidate" || true)"
    if [[ -z "$resolved" ]]; then
      chroot_root_probe_add "compatibility-wrapper" "$candidate su" "skip" "launcher not found"
      continue
    fi
    if chroot_root_launcher_probe "$resolved" "su"; then
      CHROOT_ROOT_LAUNCHER_BIN="$resolved"
      CHROOT_ROOT_LAUNCHER_SUBCMD="su"
      CHROOT_ROOT_LAUNCHER_KIND="compatibility-su"
      CHROOT_ROOT_BACKEND_READY=1
      chroot_root_diag_add "using compatibility launcher: $resolved su"
      chroot_root_probe_add "compatibility-wrapper" "$candidate su" "pass" "resolved=$resolved"
      return 0
    fi
    chroot_root_probe_add "compatibility-wrapper" "$candidate su" "fail" "resolved=$resolved probe failed"
  done

  chroot_root_diag_add "no compatible root launcher found"
  chroot_root_probe_add "result" "root-backend" "fail" "no compatible root launcher found"
  CHROOT_ROOT_LAUNCHER_BIN=""
  CHROOT_ROOT_LAUNCHER_SUBCMD=""
  CHROOT_ROOT_LAUNCHER_KIND=""
  CHROOT_ROOT_BACKEND_READY=0
  return 1
}

chroot_maybe_reexec_root_context() {
  if chroot_is_inside_chroot || [[ "$(id -u)" == "0" ]]; then
    return 0
  fi

  chroot_resolve_root_launcher || chroot_die "root backend unavailable; ${CHROOT_ROOT_DIAGNOSTICS:-no diagnostics}. set CHROOT_ROOT_LAUNCHER=<launcher> if your device uses a custom backend"

  if [[ "${CHROOT_REEXEC_ROOT_CONTEXT:-0}" == "1" ]]; then
    chroot_die "failed to re-exec under detected root backend (${CHROOT_ROOT_LAUNCHER_BIN})"
  fi

  local self qcmd arg cmd_name service_action service_name script_runner
  local need_interactive=0
  local -a launcher_cmd launcher_subcmd_parts
  cmd_name="${1:-}"
  service_action="${3:-}"
  service_name="${4:-}"
  if [[ $# -ge 2 ]]; then
    case "${2:-}" in
      service|sessions|tor)
        cmd_name="${2:-}"
        service_action="${3:-}"
        service_name="${4:-}"
        ;;
    esac
  fi
  self="$(chroot_resolve_self_path)"
  if [[ ! -f "$self" ]]; then
    self="${CHROOT_INVOKED_PATH:-$0}"
  fi
  [[ -f "$self" ]] || chroot_die "failed to resolve executable script path for root re-exec"

  script_runner="${CHROOT_BASH_BIN:-}"
  if [[ -z "$script_runner" || ! -x "$script_runner" ]]; then
    script_runner="$(command -v bash 2>/dev/null || true)"
  fi
  if [[ -z "$script_runner" || ! -x "$script_runner" ]]; then
    script_runner="${CHROOT_HOST_SH:-}"
  fi
  if [[ -z "$script_runner" || ! -x "$script_runner" ]]; then
    script_runner="$(command -v sh 2>/dev/null || true)"
  fi
  [[ -n "$script_runner" ]] || chroot_die "failed to resolve script runner for root re-exec"

  qcmd="CHROOT_REEXEC_ROOT_CONTEXT=1 PATH=$(printf '%q' "$PATH") HOME=$(printf '%q' "${HOME:-$CHROOT_TERMUX_HOME_DEFAULT}") CHROOT_RUNTIME_ROOT=$(printf '%q' "$CHROOT_RUNTIME_ROOT")"
  if [[ -n "${CHROOT_ROOT_LAUNCHER:-}" ]]; then
    qcmd+=" CHROOT_ROOT_LAUNCHER=$(printf '%q' "$CHROOT_ROOT_LAUNCHER")"
  fi
  # Execute through a shell runner so script works from noexec storage mounts.
  qcmd+=" $(printf '%q' "$script_runner") $(printf '%q' "$self")"
  for arg in "$@"; do
    qcmd+=" $(printf '%q' "$arg")"
  done

  launcher_cmd=("$CHROOT_ROOT_LAUNCHER_BIN")
  if [[ -n "${CHROOT_ROOT_LAUNCHER_SUBCMD:-}" ]]; then
    read -r -a launcher_subcmd_parts <<<"$CHROOT_ROOT_LAUNCHER_SUBCMD"
    if (( ${#launcher_subcmd_parts[@]} > 0 )); then
      launcher_cmd+=("${launcher_subcmd_parts[@]}")
    fi
  fi
  if [[ "$cmd_name" == "login" || "$cmd_name" == "exec" ]]; then
    need_interactive=1
  elif [[ "$cmd_name" == "service" ]]; then
    case "$service_action" in
      on|start|restart)
        if [[ "${service_name,,}" == "pcbridge" ]]; then
          need_interactive=1
        fi
        ;;
    esac
  fi
  if [[ "$need_interactive" == "1" ]] && chroot_su_supports_interactive; then
    if [[ -n "$CHROOT_SU_INTERACTIVE_FLAG" ]]; then
      launcher_cmd+=("$CHROOT_SU_INTERACTIVE_FLAG")
    fi
  fi
  launcher_cmd+=(-c "$qcmd")
  exec "${launcher_cmd[@]}"
}

chroot_maybe_reexec_magisk_context() {
  chroot_maybe_reexec_root_context "$@"
}
