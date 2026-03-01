chroot_cmd_login() {
  local distro="$1"
  shift || true
  [[ $# -eq 0 ]] || chroot_die "usage: bash path/to/chroot login <distro>"

  chroot_require_distro_arg "$distro"
  chroot_preflight_hard_fail
  [[ -d "$(chroot_distro_rootfs_dir "$distro")" ]] || chroot_die "distro not installed: $distro"

  chroot_cmd_mount "$distro"

  local rootfs shell_bin session_id term_value path_value
  local -a env_pairs
  rootfs="$(chroot_distro_rootfs_dir "$distro")"
  shell_bin="/bin/bash"
  [[ -x "$rootfs/bin/bash" ]] || shell_bin="/bin/sh"
  term_value="${TERM:-xterm-256color}"
  path_value="$(chroot_chroot_default_path)"
  env_pairs=("HOME=/root" "TERM=$term_value" "PATH=$path_value" "LANG=${LANG:-C.UTF-8}")
  while IFS= read -r env_pair; do
    [[ -n "$env_pair" ]] || continue
    env_pairs+=("$env_pair")
  done < <(chroot_gui_env_pairs)

  session_id="$(chroot_now_compact)-$$"
  chroot_session_add "$distro" "$session_id" "login" "interactive" "$$"
  chroot_set_distro_flag "$distro" "last_login_at" "$(chroot_now_ts)"

  local rc=0
  chroot_log_info login "start distro=$distro user=root session=$session_id"

  local login_init="$rootfs/tmp/.aurora-login-init"
  if [[ "$shell_bin" == "/bin/bash" ]]; then
    local init_tmp="$CHROOT_TMP_DIR/aurora-login-init.$$"
    cat > "$init_tmp" << 'AURORA_INIT'
[ -r /etc/profile ] && . /etc/profile 2>/dev/null
if [ -r "$HOME/.bash_profile" ]; then . "$HOME/.bash_profile"
elif [ -r "$HOME/.bash_login" ]; then . "$HOME/.bash_login"
elif [ -r "$HOME/.profile" ]; then . "$HOME/.profile"
fi
[ -r "$HOME/.bashrc" ] && . "$HOME/.bashrc"
:
AURORA_INIT
    chroot_run_root cp "$init_tmp" "$login_init"
    chroot_run_root chmod 644 "$login_init"
    rm -f -- "$init_tmp"
  fi

  set +e
  if [[ "$shell_bin" == "/bin/bash" && -f "$login_init" ]]; then
    chroot_run_chroot_env "$rootfs" "${env_pairs[@]}" -- "$shell_bin" --init-file /tmp/.aurora-login-init -i
  else
    chroot_run_chroot_env "$rootfs" "${env_pairs[@]}" -- "$shell_bin" -l
  fi
  rc=$?
  set -e
  chroot_run_root rm -f -- "$login_init" 2>/dev/null || true

  chroot_session_remove "$distro" "$session_id"
  if (( rc != 0 )); then
    chroot_log_warn login "shell exited rc=$rc distro=$distro session=$session_id"
    chroot_warn "login shell exited with code $rc"
    return "$rc"
  fi

  chroot_log_info login "end distro=$distro session=$session_id rc=0"
}
