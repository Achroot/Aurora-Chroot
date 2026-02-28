chroot_cmd_exec() {
  local distro="$1"
  shift

  [[ $# -gt 0 ]] || chroot_die "usage: bash path/to/chroot exec <distro> -- <cmd...>"
  [[ "$1" == "--" ]] || chroot_die "usage: bash path/to/chroot exec <distro> -- <cmd...>"
  shift
  [[ $# -gt 0 ]] || chroot_die "exec command is required"

  local -a exec_cmd=("$@")
  local cmd_str
  cmd_str="$(chroot_quote_cmd "${exec_cmd[@]}")"

  chroot_require_distro_arg "$distro"
  chroot_preflight_hard_fail
  [[ -d "$(chroot_distro_rootfs_dir "$distro")" ]] || chroot_die "distro not installed: $distro"

  chroot_cmd_mount "$distro"

  local rootfs session_id
  rootfs="$(chroot_distro_rootfs_dir "$distro")"
  session_id="$(chroot_now_compact)-$$"

  local term_value path_value lang_value host_sh display_value
  term_value="${TERM:-xterm-256color}"
  path_value="$(chroot_chroot_default_path)"
  lang_value="${LANG:-C.UTF-8}"
  display_value=""
  if chroot_x11_enabled; then
    display_value=":0"
  fi
  host_sh="${CHROOT_HOST_SH:-}"
  if [[ -z "$host_sh" || ! -x "$host_sh" ]]; then
    host_sh="$(chroot_detect_pick_path "${CHROOT_HOST_SH:-}" "sh" \
      "${CHROOT_SYSTEM_BIN_DEFAULT}/sh" "/bin/sh" "$CHROOT_TERMUX_BIN/sh" "/usr/bin/sh" || true)"
  fi
  [[ -n "$host_sh" ]] || chroot_die "unable to resolve host shell binary"

  local chroot_backend_bin chroot_backend_subcmd
  IFS=$'\t' read -r chroot_backend_bin chroot_backend_subcmd <<<"$(chroot_chroot_backend_parts_tsv || true)"
  [[ -n "$chroot_backend_bin" ]] || chroot_die "chroot backend unavailable; run doctor for diagnostics"

  local launcher_script pid_file tracked_pid launcher_pid poll_idx file_pid
  launcher_script="$CHROOT_TMP_DIR/.exec-launcher.${session_id}.sh"
  pid_file="$CHROOT_TMP_DIR/.exec-pid.${session_id}.txt"
  tracked_pid=""
  launcher_pid=0
  file_pid=""

  rm -f -- "$launcher_script" "$pid_file"
  cat >"$launcher_script" <<'SH'
set -eu

pid_file="$1"
term_value="$2"
path_value="$3"
lang_value="$4"
display_value="$5"
rootfs="$6"
shell_bin="$7"
chroot_bin="$8"
chroot_subcmd="$9"
shift 9

launch_direct() {
  echo "$$" > "$pid_file"
  if [ -n "$chroot_subcmd" ]; then
    if [ -n "$display_value" ]; then
      exec env -i HOME=/root TERM="$term_value" PATH="$path_value" LANG="$lang_value" DISPLAY="$display_value" "$chroot_bin" "$chroot_subcmd" "$rootfs" "$@"
    fi
    exec env -i HOME=/root TERM="$term_value" PATH="$path_value" LANG="$lang_value" "$chroot_bin" "$chroot_subcmd" "$rootfs" "$@"
  fi
  if [ -n "$display_value" ]; then
    exec env -i HOME=/root TERM="$term_value" PATH="$path_value" LANG="$lang_value" DISPLAY="$display_value" "$chroot_bin" "$rootfs" "$@"
  fi
  exec env -i HOME=/root TERM="$term_value" PATH="$path_value" LANG="$lang_value" "$chroot_bin" "$rootfs" "$@"
}

if command -v setsid >/dev/null 2>&1; then
  exec setsid "$shell_bin" -c '
set -eu
pid_file="$1"
term_value="$2"
path_value="$3"
lang_value="$4"
display_value="$5"
rootfs="$6"
chroot_bin="$7"
chroot_subcmd="$8"
shift 8
echo "$$" > "$pid_file"
if [ -n "$chroot_subcmd" ]; then
  if [ -n "$display_value" ]; then
    exec env -i HOME=/root TERM="$term_value" PATH="$path_value" LANG="$lang_value" DISPLAY="$display_value" "$chroot_bin" "$chroot_subcmd" "$rootfs" "$@"
  fi
  exec env -i HOME=/root TERM="$term_value" PATH="$path_value" LANG="$lang_value" "$chroot_bin" "$chroot_subcmd" "$rootfs" "$@"
fi
if [ -n "$display_value" ]; then
  exec env -i HOME=/root TERM="$term_value" PATH="$path_value" LANG="$lang_value" DISPLAY="$display_value" "$chroot_bin" "$rootfs" "$@"
fi
exec env -i HOME=/root TERM="$term_value" PATH="$path_value" LANG="$lang_value" "$chroot_bin" "$rootfs" "$@"
' sh "$pid_file" "$term_value" "$path_value" "$lang_value" "$display_value" "$rootfs" "$chroot_bin" "$chroot_subcmd" "$@"
fi

launch_direct "$@"
SH
  chmod 0700 "$launcher_script"

  chroot_log_info exec "start distro=$distro cmd=$cmd_str session=$session_id"
  chroot_run_root "$host_sh" "$launcher_script" "$pid_file" "$term_value" "$path_value" "$lang_value" "$display_value" "$rootfs" "$host_sh" "$chroot_backend_bin" "$chroot_backend_subcmd" "${exec_cmd[@]}" &
  launcher_pid=$!
  tracked_pid="$launcher_pid"

  for (( poll_idx = 0; poll_idx < 120; poll_idx++ )); do
    if [[ -s "$pid_file" ]]; then
      read -r file_pid <"$pid_file" || true
      if [[ "$file_pid" =~ ^[0-9]+$ ]]; then
        tracked_pid="$file_pid"
        break
      fi
    fi
    if ! kill -0 "$launcher_pid" >/dev/null 2>&1; then
      break
    fi
    sleep 0.05
  done

  chroot_session_add "$distro" "$session_id" "exec" "$cmd_str" "$tracked_pid" || chroot_warn "failed to track exec session $session_id"

  local rc=0
  set +e
  wait "$launcher_pid"
  rc=$?
  set -e
  rm -f -- "$launcher_script" "$pid_file"

  chroot_session_remove "$distro" "$session_id"
  if (( rc != 0 )); then
    chroot_log_error exec "failed distro=$distro session=$session_id rc=$rc"
    return "$rc"
  fi

  chroot_log_info exec "end distro=$distro session=$session_id rc=0"
}
