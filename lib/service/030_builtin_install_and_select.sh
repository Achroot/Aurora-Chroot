chroot_service_builtin_install_assets() {
  local distro="$1"
  local builtin_id="${2:-}"

  builtin_id="${builtin_id,,}"
  case "$builtin_id" in
    pcbridge)
      local rootfs script_dir script_path tmp_script
      rootfs="$(chroot_distro_rootfs_dir "$distro")"
      [[ -d "$rootfs" ]] || chroot_die "distro not installed: $distro"
      script_dir="$rootfs/usr/local/sbin"
      script_path="$script_dir/aurora-pcbridge-start"
      tmp_script="$CHROOT_TMP_DIR/builtin-pcbridge-start-$$.sh"
      chroot_service_builtin_pcbridge_script_content >"$tmp_script"
      if ! chroot_run_root mkdir -p "$script_dir"; then
        rm -f -- "$tmp_script"
        chroot_die "failed to prepare built-in pcbridge script directory for $distro"
      fi
      if ! chroot_run_root install -m 0755 "$tmp_script" "$script_path"; then
        rm -f -- "$tmp_script"
        chroot_die "failed to install built-in pcbridge script for $distro"
      fi
      rm -f -- "$tmp_script"
      ;;
    sshd)
      local rootfs script_dir script_path tmp_script
      rootfs="$(chroot_distro_rootfs_dir "$distro")"
      [[ -d "$rootfs" ]] || chroot_die "distro not installed: $distro"
      script_dir="$rootfs/usr/local/sbin"
      script_path="$script_dir/aurora-sshd-start"
      tmp_script="$CHROOT_TMP_DIR/builtin-sshd-start-$$.sh"
      chroot_service_builtin_sshd_script_content >"$tmp_script"
      if ! chroot_run_root mkdir -p "$script_dir"; then
        rm -f -- "$tmp_script"
        chroot_die "failed to prepare built-in sshd script directory for $distro"
      fi
      if ! chroot_run_root install -m 0755 "$tmp_script" "$script_path"; then
        rm -f -- "$tmp_script"
        chroot_die "failed to install built-in sshd script for $distro"
      fi
      rm -f -- "$tmp_script"
      ;;
    zsh)
      local rootfs tmp_script zsh_distro_type=""
      rootfs="$(chroot_distro_rootfs_dir "$distro")"
      [[ -d "$rootfs" ]] || chroot_die "distro not installed: $distro"

      if [[ -x "$rootfs/usr/bin/pacman" ]]; then
        zsh_distro_type="arch"
      elif [[ -x "$rootfs/usr/bin/apt" ]] || [[ -x "$rootfs/usr/bin/apt-get" ]]; then
        zsh_distro_type="ubuntu"
      else
        chroot_die "zsh setup only supports Arch Linux (pacman) and Ubuntu (apt). Could not detect either in $distro."
      fi

      tmp_script="$CHROOT_TMP_DIR/builtin-zsh-setup-$$.sh"
      chroot_service_builtin_zsh_script_content >"$tmp_script"
      chroot_cmd_mount "$distro"
      if ! chroot_run_root install -m 0755 "$tmp_script" "$rootfs/tmp/aurora-zsh-setup.sh"; then
        rm -f -- "$tmp_script"
        chroot_die "failed to copy zsh setup script into $distro"
      fi
      rm -f -- "$tmp_script"
      local zsh_rc=0
      chroot_run_chroot_env "$rootfs" \
        "HOME=/root" \
        "TERM=${TERM:-xterm-256color}" \
        "PATH=$(chroot_chroot_default_path)" \
        "LANG=${LANG:-C.UTF-8}" \
        -- /bin/bash /tmp/aurora-zsh-setup.sh "$zsh_distro_type" || zsh_rc=$?
      chroot_run_root rm -f "$rootfs/tmp/aurora-zsh-setup.sh" 2>/dev/null || true
      if (( zsh_rc != 0 )); then
        chroot_die "zsh setup failed inside $distro (exit code: $zsh_rc)"
      fi
      ;;
  esac
}

chroot_service_builtin_list_human() {
  local builtin_id svc_name cmd_str desc
  printf '%-12s %-16s %-38s %s\n' "builtin_id" "service_name" "command" "description"
  printf '%-12s %-16s %-38s %s\n' "----------" "------------" "-------" "-----------"
  while IFS= read -r builtin_id; do
    [[ -n "$builtin_id" ]] || continue
    if ! IFS=$'\t' read -r svc_name cmd_str desc < <(chroot_service_builtin_resolve "$builtin_id"); then
      continue
    fi
    printf '%-12s %-16s %-38s %s\n' "$builtin_id" "$svc_name" "$cmd_str" "$desc"
  done < <(chroot_service_builtin_ids)
}

chroot_service_select_builtin() {
  local prompt="${1:-Select built-in service to install}"
  local -a ids=()
  local builtin_id svc_name cmd_str desc idx pick

  while IFS= read -r builtin_id; do
    [[ -n "$builtin_id" ]] || continue
    ids+=("$builtin_id")
  done < <(chroot_service_builtin_ids)

  if (( ${#ids[@]} == 0 )); then
    chroot_warn "No built-in services available."
    return 2
  fi

  printf '\nBuilt-in services:\n' >&2
  idx=1
  for builtin_id in "${ids[@]}"; do
    IFS=$'\t' read -r svc_name cmd_str desc < <(chroot_service_builtin_resolve "$builtin_id")
    printf '  %2d) %-10s service=%-12s cmd=%-38s %s\n' "$idx" "$builtin_id" "$svc_name" "$cmd_str" "$desc" >&2
    idx=$((idx + 1))
  done

  while true; do
    printf '%s (1-%s, q=cancel): ' "$prompt" "${#ids[@]}" >&2
    read -r pick
    case "$pick" in
      q|Q|'')
        return 1
        ;;
      *)
        if [[ "$pick" =~ ^[0-9]+$ ]] && (( pick >= 1 && pick <= ${#ids[@]} )); then
          printf '%s\n' "${ids[$((pick - 1))]}"
          return 0
        fi
        ;;
    esac
    printf 'Invalid selection.\n' >&2
  done
}

chroot_service_builtin_is_install_only() {
  local builtin_id="${1:-}"
  builtin_id="${builtin_id,,}"
  case "$builtin_id" in
    zsh) return 0 ;;
    *) return 1 ;;
  esac
}

chroot_service_install_builtin() {
  local distro="$1"
  local builtin_id="${2:-}"
  local resolved svc_name cmd_str desc def_file existing_cmd
  local already_installed=0

  builtin_id="${builtin_id,,}"
  resolved="$(chroot_service_builtin_resolve "$builtin_id" || true)"
  [[ -n "$resolved" ]] || chroot_die "unknown built-in service: $builtin_id"
  IFS=$'\t' read -r svc_name cmd_str desc <<<"$resolved"

  if chroot_service_builtin_is_install_only "$builtin_id"; then
    chroot_service_builtin_install_assets "$distro" "$builtin_id"
    return 0
  fi

  def_file="$(chroot_service_def_file "$distro" "$svc_name")"
  if [[ -f "$def_file" ]]; then
    existing_cmd="$(chroot_service_get_cmd "$distro" "$svc_name" 2>/dev/null || true)"
    if [[ "$existing_cmd" == "$cmd_str" ]]; then
      already_installed=1
    else
      chroot_die "service '$svc_name' already exists in $distro (remove it first, then retry install)"
    fi
  fi

  chroot_service_builtin_install_assets "$distro" "$builtin_id"

  if (( already_installed == 1 )); then
    chroot_info "Built-in '$builtin_id' already installed as service '$svc_name' in $distro (assets refreshed)"
    return 0
  fi

  chroot_service_add_def "$distro" "$svc_name" "$cmd_str"
  chroot_info "Installed built-in service '$builtin_id' as '$svc_name' in $distro"
}

chroot_service_select_def() {
  local distro="$1"
  local prompt="${2:-Select service}"
  local -a svcs=()
  local svc cmd_str pid state pid_text idx pick

  while IFS= read -r svc; do
    [[ -n "$svc" ]] || continue
    svcs+=("$svc")
  done < <(chroot_service_list_defs "$distro")

  if (( ${#svcs[@]} == 0 )); then
    chroot_warn "No services defined for $distro."
    return 2
  fi

  printf '\nServices in %s:\n' "$distro" >&2
  idx=1
  for svc in "${svcs[@]}"; do
    cmd_str="$(chroot_service_get_cmd "$distro" "$svc" 2>/dev/null || true)"
    cmd_str="${cmd_str//$'\r'/ }"
    cmd_str="${cmd_str//$'\n'/ }"
    if pid="$(chroot_service_get_pid "$distro" "$svc" 2>/dev/null)"; then
      state="running"
      pid_text="$pid"
    else
      state="stopped"
      pid_text="-"
    fi
    printf '  %2d) %-20s state=%-8s pid=%-8s cmd=%s\n' "$idx" "$svc" "$state" "$pid_text" "${cmd_str:-<none>}" >&2
    idx=$((idx + 1))
  done

  while true; do
    printf '%s (1-%s, q=cancel): ' "$prompt" "${#svcs[@]}" >&2
    read -r pick
    case "$pick" in
      q|Q|'')
        return 1
        ;;
      *)
        if [[ "$pick" =~ ^[0-9]+$ ]] && (( pick >= 1 && pick <= ${#svcs[@]} )); then
          printf '%s\n' "${svcs[$((pick - 1))]}"
          return 0
        fi
        ;;
    esac
    printf 'Invalid selection.\n' >&2
  done
}
