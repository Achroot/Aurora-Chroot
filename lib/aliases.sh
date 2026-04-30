#!/usr/bin/env bash

CHROOT_ALIAS_BLOCK_START="# >>> aurora login distros quick aliases >>>"
CHROOT_ALIAS_BLOCK_END="# <<< aurora login distros quick aliases <<<"
CHROOT_ALIAS_LAST_TARGETS=""
CHROOT_ALIAS_LAST_TARGET_LABEL=""
CHROOT_ALIAS_LAST_LINE=""

chroot_alias_supported_env() {
  chroot_is_termux_env || return 1
  chroot_is_inside_chroot && return 1
  return 0
}

chroot_alias_home_dir() {
  local home_dir="${HOME:-$CHROOT_TERMUX_HOME_DEFAULT}"
  if [[ -z "$home_dir" || ! -d "$home_dir" ]]; then
    home_dir="$CHROOT_TERMUX_HOME_DEFAULT"
  fi
  printf '%s\n' "$home_dir"
}

chroot_alias_target_rc_files() {
  local mode="${1:-upsert}"
  local home_dir bashrc zshrc
  local have_bash=0 have_zsh=0

  home_dir="$(chroot_alias_home_dir)"
  [[ -n "$home_dir" ]] || return 0

  bashrc="$home_dir/.bashrc"
  zshrc="$home_dir/.zshrc"

  [[ -f "$bashrc" ]] && have_bash=1
  [[ -f "$zshrc" ]] && have_zsh=1

  if (( have_bash == 0 && have_zsh == 0 )); then
    if [[ "$mode" == "upsert" ]]; then
      printf '%s\n' "$bashrc"
    fi
    return 0
  fi

  (( have_bash == 1 )) && printf '%s\n' "$bashrc"
  (( have_zsh == 1 )) && printf '%s\n' "$zshrc"
}

chroot_alias_mktemp() {
  if [[ -n "${CHROOT_TMP_DIR:-}" && -d "$CHROOT_TMP_DIR" ]]; then
    mktemp "$CHROOT_TMP_DIR/alias-aurora.XXXXXX" 2>/dev/null || mktemp "/tmp/alias-aurora.XXXXXX"
    return
  fi
  mktemp "/tmp/alias-aurora.XXXXXX"
}

chroot_alias_stat_uid_gid() {
  local path="$1"
  stat -c '%u:%g' "$path" 2>/dev/null || true
}

chroot_alias_stat_mode() {
  local path="$1"
  stat -c '%a' "$path" 2>/dev/null || true
}

chroot_alias_restorecon_path() {
  local path="$1"
  local restorecon_bin=""

  if [[ -x "/system/bin/restorecon" ]]; then
    restorecon_bin="/system/bin/restorecon"
  elif chroot_cmd_exists restorecon; then
    restorecon_bin="$(command -v restorecon 2>/dev/null || true)"
  fi
  [[ -n "$restorecon_bin" ]] || return 0

  "$restorecon_bin" "$path" >/dev/null 2>&1 || "$restorecon_bin" -F "$path" >/dev/null 2>&1 || true
}

chroot_alias_file_owner_spec() {
  local file="$1"
  local owner="" home_dir

  if [[ -e "$file" ]]; then
    owner="$(chroot_alias_stat_uid_gid "$file")"
  fi
  if [[ -z "$owner" ]]; then
    home_dir="$(chroot_alias_home_dir)"
    if [[ -n "$home_dir" && -d "$home_dir" ]]; then
      owner="$(chroot_alias_stat_uid_gid "$home_dir")"
    fi
  fi
  printf '%s\n' "$owner"
}

chroot_alias_render_line() {
  local distro="$1"
  local aurora_path="$2"
  printf "alias %s='%s login %s'\n" "$distro" "$aurora_path" "$distro"
}

chroot_alias_target_name() {
  local file="$1"
  case "$(basename "$file")" in
    .bashrc) printf 'bashrc\n' ;;
    .zshrc) printf 'zshrc\n' ;;
    *)
      basename "$file"
      ;;
  esac
}

chroot_alias_targets_label_from_list() {
  local file_list="$1"
  local file name
  local -a labels=()
  local -A seen=()

  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    name="$(chroot_alias_target_name "$file")"
    [[ -n "$name" ]] || continue
    [[ -n "${seen[$name]:-}" ]] && continue
    seen["$name"]=1
    labels+=("$name")
  done <<<"$file_list"

  case "${#labels[@]}" in
    0) printf 'shell profiles\n' ;;
    1) printf '%s\n' "${labels[0]}" ;;
    *)
      printf '%s' "${labels[0]}"
      local idx
      for (( idx = 1; idx < ${#labels[@]}; idx++ )); do
        printf '/%s' "${labels[$idx]}"
      done
      printf '\n'
      ;;
  esac
}

chroot_alias_targets_paths_inline() {
  local file_list="$1"
  local file
  local first=1

  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    if (( first == 1 )); then
      printf '%s' "$file"
      first=0
    else
      printf ', %s' "$file"
    fi
  done <<<"$file_list"

  if (( first == 1 )); then
    printf 'shell profiles'
  fi
  printf '\n'
}

chroot_alias_print_upsert_notice() {
  local distro="$1"
  local targets line source_hint file

  targets="$(chroot_alias_targets_paths_inline "$CHROOT_ALIAS_LAST_TARGETS")"
  line="${CHROOT_ALIAS_LAST_LINE:-}"
  if [[ -z "$line" ]]; then
    line="$(chroot_alias_render_line "$distro" "$(chroot_aurora_launcher_path)")"
    line="${line%$'\n'}"
  fi

  chroot_info "Added login alias for $distro."
  chroot_info "Edited shell profile: $targets"
  chroot_info "Added alias line: $line"

  source_hint=""
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    if [[ -z "$source_hint" ]]; then
      source_hint="source $file"
    else
      source_hint="$source_hint; source $file"
    fi
  done <<<"$CHROOT_ALIAS_LAST_TARGETS"

  if [[ -n "$source_hint" ]]; then
    chroot_info "Run '$source_hint' or restart Termux before using '$distro'."
  else
    chroot_info "Restart Termux before using '$distro'."
  fi
}

chroot_alias_split_profile_content() {
  local file="$1"
  local base_out="$2"
  local alias_out="$3"
  local has_start=0 has_end=0

  : >"$base_out"
  : >"$alias_out"
  [[ -f "$file" ]] || return 0

  if grep -Fqx "$CHROOT_ALIAS_BLOCK_START" "$file"; then
    has_start=1
  fi
  if grep -Fqx "$CHROOT_ALIAS_BLOCK_END" "$file"; then
    has_end=1
  fi

  if (( has_start == 1 && has_end == 1 )); then
    awk -v start="$CHROOT_ALIAS_BLOCK_START" -v end="$CHROOT_ALIAS_BLOCK_END" \
      -v out_base="$base_out" -v out_alias="$alias_out" '
      BEGIN { in_block=0 }
      $0 == start { in_block=1; next }
      $0 == end { in_block=0; next }
      {
        if (in_block) {
          print >> out_alias
        } else {
          print >> out_base
        }
      }
    ' "$file"
    return 0
  fi

  cat "$file" >"$base_out"
}

chroot_alias_rebuild_lines() {
  local mode="$1"
  local distro="$2"
  local aurora_path="$3"
  local alias_in="$4"
  local alias_out="$5"

  local line name idx found=0 new_line=""
  local -a names=()
  local -a lines=()
  local -A seen=()

  while IFS= read -r line; do
    [[ "$line" =~ ^alias[[:space:]]+([A-Za-z0-9][A-Za-z0-9._-]*)= ]] || continue
    name="${BASH_REMATCH[1]}"
    [[ -n "${seen[$name]:-}" ]] && continue
    seen["$name"]=1
    names+=("$name")
    lines+=("$line")
  done <"$alias_in"

  case "$mode" in
    upsert)
      new_line="$(chroot_alias_render_line "$distro" "$aurora_path")"
      for idx in "${!names[@]}"; do
        if [[ "${names[$idx]}" == "$distro" ]]; then
          lines[$idx]="$new_line"
          found=1
          break
        fi
      done
      if (( found == 0 )); then
        names+=("$distro")
        lines+=("$new_line")
      fi
      ;;
    remove)
      local -a kept_names=()
      local -a kept_lines=()
      for idx in "${!names[@]}"; do
        if [[ "${names[$idx]}" == "$distro" ]]; then
          continue
        fi
        kept_names+=("${names[$idx]}")
        kept_lines+=("${lines[$idx]}")
      done
      names=("${kept_names[@]}")
      lines=("${kept_lines[@]}")
      ;;
    *)
      return 1
      ;;
  esac

  : >"$alias_out"
  for line in "${lines[@]}"; do
    printf '%s\n' "$line" >>"$alias_out"
  done
}

chroot_alias_write_profile() {
  local file="$1"
  local base_file="$2"
  local alias_lines="$3"
  local tmp_file owner mode file_exists=0

  [[ -e "$file" ]] && file_exists=1
  tmp_file="$(chroot_alias_mktemp)" || return 1
  owner="$(chroot_alias_file_owner_spec "$file")"
  mode="$(chroot_alias_stat_mode "$file")"

  if ! cat "$base_file" >"$tmp_file"; then
    rm -f -- "$tmp_file"
    return 1
  fi

  if [[ -s "$alias_lines" ]]; then
    if [[ -s "$tmp_file" ]] && [[ "$(tail -c1 "$tmp_file" 2>/dev/null || true)" != $'\n' ]]; then
      printf '\n' >>"$tmp_file"
    fi
    printf '%s\n' "$CHROOT_ALIAS_BLOCK_START" >>"$tmp_file"
    cat "$alias_lines" >>"$tmp_file"
    printf '%s\n' "$CHROOT_ALIAS_BLOCK_END" >>"$tmp_file"
  fi

  if (( file_exists == 1 )); then
    if ! cat "$tmp_file" >"$file"; then
      rm -f -- "$tmp_file"
      return 1
    fi
    rm -f -- "$tmp_file"
  elif ! mv -f -- "$tmp_file" "$file"; then
    rm -f -- "$tmp_file"
    return 1
  fi

  if [[ -n "$mode" ]]; then
    chmod "$mode" "$file" >/dev/null 2>&1 || true
  fi
  if [[ "$(id -u)" == "0" && -n "$owner" ]]; then
    chown "$owner" "$file" >/dev/null 2>&1 || true
    chroot_alias_restorecon_path "$file"
  fi
}

chroot_alias_update_file() {
  local file="$1"
  local mode="$2"
  local distro="$3"
  local aurora_path="${4:-}"
  local base_file alias_file rebuilt_file
  local rc=0

  base_file="$(chroot_alias_mktemp)" || return 1
  alias_file="$(chroot_alias_mktemp)" || {
    rm -f -- "$base_file"
    return 1
  }
  rebuilt_file="$(chroot_alias_mktemp)" || {
    rm -f -- "$base_file" "$alias_file"
    return 1
  }

  if [[ "$mode" == "upsert" ]]; then
    mkdir -p "$(dirname "$file")" || rc=1
  elif [[ ! -f "$file" ]]; then
    rm -f -- "$base_file" "$alias_file" "$rebuilt_file"
    return 0
  fi

  if (( rc == 0 )); then
    chroot_alias_split_profile_content "$file" "$base_file" "$alias_file" || rc=1
  fi
  if (( rc == 0 )); then
    chroot_alias_rebuild_lines "$mode" "$distro" "$aurora_path" "$alias_file" "$rebuilt_file" || rc=1
  fi
  if (( rc == 0 )); then
    chroot_alias_write_profile "$file" "$base_file" "$rebuilt_file" || rc=1
  fi

  rm -f -- "$base_file" "$alias_file" "$rebuilt_file"
  return "$rc"
}

chroot_alias_upsert_distro() {
  local distro="$1"
  local aurora_path rc=0 file

  CHROOT_ALIAS_LAST_TARGETS=""
  CHROOT_ALIAS_LAST_TARGET_LABEL=""

  chroot_require_distro_arg "$distro"
  chroot_alias_supported_env || return 0

  chroot_ensure_aurora_launcher >/dev/null 2>&1 || true
  aurora_path="$(chroot_aurora_launcher_path)"
  [[ -n "$aurora_path" ]] || return 1
  CHROOT_ALIAS_LAST_LINE="$(chroot_alias_render_line "$distro" "$aurora_path")"
  CHROOT_ALIAS_LAST_LINE="${CHROOT_ALIAS_LAST_LINE%$'\n'}"

  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    CHROOT_ALIAS_LAST_TARGETS+="$file"$'\n'
    if ! chroot_alias_update_file "$file" "upsert" "$distro" "$aurora_path"; then
      rc=1
    fi
  done < <(chroot_alias_target_rc_files "upsert")

  CHROOT_ALIAS_LAST_TARGET_LABEL="$(chroot_alias_targets_label_from_list "$CHROOT_ALIAS_LAST_TARGETS")"
  return "$rc"
}

chroot_alias_remove_distro() {
  local distro="$1"
  local rc=0 file

  CHROOT_ALIAS_LAST_TARGETS=""
  CHROOT_ALIAS_LAST_TARGET_LABEL=""

  chroot_require_distro_arg "$distro"
  chroot_alias_supported_env || return 0

  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    CHROOT_ALIAS_LAST_TARGETS+="$file"$'\n'
    if ! chroot_alias_update_file "$file" "remove" "$distro"; then
      rc=1
    fi
  done < <(chroot_alias_target_rc_files "remove")

  CHROOT_ALIAS_LAST_TARGET_LABEL="$(chroot_alias_targets_label_from_list "$CHROOT_ALIAS_LAST_TARGETS")"
  return "$rc"
}
