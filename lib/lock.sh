#!/usr/bin/env bash

if ! declare -p CHROOT_HELD_LOCKS >/dev/null 2>&1; then
  declare -ag CHROOT_HELD_LOCKS=()
fi

chroot_lock_track_has() {
  local name="$1"
  local held
  for held in "${CHROOT_HELD_LOCKS[@]}"; do
    [[ "$held" == "$name" ]] && return 0
  done
  return 1
}

chroot_lock_track_add() {
  local name="$1"
  chroot_lock_track_has "$name" && return 0
  CHROOT_HELD_LOCKS+=("$name")
}

chroot_lock_track_remove() {
  local name="$1"
  local -a kept=()
  local held
  for held in "${CHROOT_HELD_LOCKS[@]}"; do
    [[ "$held" == "$name" ]] && continue
    kept+=("$held")
  done
  CHROOT_HELD_LOCKS=("${kept[@]}")
}

chroot_lock_release_held() {
  local -a held=("${CHROOT_HELD_LOCKS[@]}")
  local i

  CHROOT_HELD_LOCKS=()
  for (( i=${#held[@]}-1; i>=0; i-- )); do
    chroot_lock_release "${held[$i]}" >/dev/null 2>&1 || true
  done
}

chroot_lock_path() {
  local name="$1"
  printf '%s/%s.lockdir' "$CHROOT_LOCK_DIR" "$name"
}

chroot_lock_owner_file() {
  local lock_path="$1"
  printf '%s/owner.pid' "$lock_path"
}

chroot_lock_meta_file() {
  local lock_path="$1"
  printf '%s/meta' "$lock_path"
}

chroot_lock_age_sec() {
  local lock_path="$1"
  local now mtime
  now="$(date +%s)"
  mtime="$(stat -c %Y "$lock_path" 2>/dev/null || true)"
  [[ "$mtime" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$(( now - mtime ))"
}

chroot_lock_proc_starttime() {
  local pid="$1"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  awk '{print $22}' "/proc/$pid/stat" 2>/dev/null
}

chroot_lock_meta_value() {
  local lock_path="$1"
  local key="$2"
  local meta_file
  meta_file="$(chroot_lock_meta_file "$lock_path")"
  [[ -f "$meta_file" ]] || return 1
  awk -F= -v k="$key" '$1 == k {print substr($0, index($0,"=")+1); exit}' "$meta_file"
}

chroot_lock_owner_hint() {
  local lock_path="$1"
  local owner_file owner_pid owner_time owner_name owner_start age owner_live
  owner_file="$(chroot_lock_owner_file "$lock_path")"

  owner_pid="$(cat "$owner_file" 2>/dev/null || true)"
  [[ -n "$owner_pid" ]] || owner_pid="unknown"
  owner_time="$(chroot_lock_meta_value "$lock_path" "time" 2>/dev/null || true)"
  owner_name="$(chroot_lock_meta_value "$lock_path" "name" 2>/dev/null || true)"
  owner_start="$(chroot_lock_meta_value "$lock_path" "starttime" 2>/dev/null || true)"
  age="$(chroot_lock_age_sec "$lock_path" 2>/dev/null || true)"

  [[ -n "$owner_time" ]] || owner_time="unknown"
  [[ -n "$owner_name" ]] || owner_name="unknown"
  [[ -n "$owner_start" ]] || owner_start="unknown"
  [[ "$age" =~ ^[0-9]+$ ]] || age="unknown"

  owner_live="unknown"
  if [[ "$owner_pid" =~ ^[0-9]+$ ]]; then
    if kill -0 "$owner_pid" >/dev/null 2>&1; then
      owner_live="yes"
    else
      owner_live="no"
    fi
  fi

  printf 'owner_pid=%s owner_live=%s owner_time=%s owner_starttime=%s owner_name=%s lock_age_sec=%s' \
    "$owner_pid" "$owner_live" "$owner_time" "$owner_start" "$owner_name" "$age"
}

chroot_lock_is_stale() {
  local lock_path="$1"
  local owner_file owner_pid age meta_starttime current_starttime
  owner_file="$(chroot_lock_owner_file "$lock_path")"

  [[ -d "$lock_path" ]] || return 1
  if [[ ! -f "$owner_file" ]]; then
    # Treat a fresh lockdir without owner.pid as in-progress, not stale.
    # Only reclaim it after it has clearly aged out.
    age="$(chroot_lock_age_sec "$lock_path" 2>/dev/null || true)"
    if [[ "$age" =~ ^[0-9]+$ ]] && (( age > 10 )); then
      return 0
    fi
    return 1
  fi

  owner_pid="$(cat "$owner_file" 2>/dev/null || true)"
  if [[ ! "$owner_pid" =~ ^[0-9]+$ ]]; then
    age="$(chroot_lock_age_sec "$lock_path" 2>/dev/null || true)"
    if [[ "$age" =~ ^[0-9]+$ ]] && (( age > 10 )); then
      return 0
    fi
    return 1
  fi

  if kill -0 "$owner_pid" >/dev/null 2>&1; then
    # Compare proc starttime here so a reused PID is not mistaken for the lock owner.
    # If that metadata is unreadable, leave the live PID treated as active.
    meta_starttime="$(chroot_lock_meta_value "$lock_path" "starttime" 2>/dev/null || true)"
    if [[ "$meta_starttime" =~ ^[0-9]+$ ]]; then
      current_starttime="$(chroot_lock_proc_starttime "$owner_pid" 2>/dev/null || true)"
      if [[ "$current_starttime" =~ ^[0-9]+$ ]]; then
        [[ "$current_starttime" == "$meta_starttime" ]] && return 1
        return 0
      fi
    fi
    return 1
  fi

  return 0
}

chroot_lock_acquire() {
  local name="$1"
  local timeout="${2:-$CHROOT_LOCK_TIMEOUT_SEC_DEFAULT}"
  local lock_path owner_file meta_file start now starttime

  lock_path="$(chroot_lock_path "$name")"
  owner_file="$(chroot_lock_owner_file "$lock_path")"
  meta_file="$(chroot_lock_meta_file "$lock_path")"

  start="$(date +%s)"
  starttime="$(chroot_lock_proc_starttime "$$" 2>/dev/null || true)"
  while true; do
    if mkdir "$lock_path" 2>/dev/null; then
      printf '%s\n' "$$" >"$owner_file"
      {
        printf 'pid=%s\n' "$$"
        printf 'starttime=%s\n' "${starttime:-unknown}"
        printf 'time=%s\n' "$(chroot_now_ts)"
        printf 'name=%s\n' "$name"
      } >"$meta_file"
      chroot_lock_track_add "$name"
      return 0
    fi

    if chroot_lock_is_stale "$lock_path"; then
      rm -rf -- "$lock_path"
      continue
    fi

    now="$(date +%s)"
    if (( now - start >= timeout )); then
      local owner_hint user_msg
      owner_hint="$(chroot_lock_owner_hint "$lock_path" 2>/dev/null || true)"
      chroot_log_error lock "timeout acquiring lock $name $owner_hint"
      if [[ "$name" == "global" ]]; then
        user_msg="another long refresh/install may still be running; could not acquire global lock ($owner_hint)"
      else
        user_msg="another operation may still be running; could not acquire lock '$name' ($owner_hint)"
      fi
      chroot_err "$user_msg"
      return 1
    fi

    sleep 1
  done
}

chroot_lock_release() {
  local name="$1"
  local lock_path owner_file owner_pid
  lock_path="$(chroot_lock_path "$name")"
  owner_file="$(chroot_lock_owner_file "$lock_path")"

  [[ -d "$lock_path" ]] || {
    chroot_lock_track_remove "$name"
    return 0
  }
  owner_pid="$(cat "$owner_file" 2>/dev/null || true)"

  if [[ "$owner_pid" =~ ^[0-9]+$ && "$owner_pid" != "$$" ]]; then
    if kill -0 "$owner_pid" >/dev/null 2>&1; then
      return 0
    fi
    # Only remove another process's lock when you can prove it is stale.
    chroot_lock_is_stale "$lock_path" || return 0
  elif [[ ! "$owner_pid" =~ ^[0-9]+$ ]]; then
    # If owner metadata is broken, still require the lockdir to look stale before removing it.
    chroot_lock_is_stale "$lock_path" || return 0
  fi

  rm -rf -- "$lock_path"
  chroot_lock_track_remove "$name"
}

chroot_lock_repair_stale() {
  local repaired=0
  local lock_path
  for lock_path in "$CHROOT_LOCK_DIR"/*.lockdir; do
    [[ -e "$lock_path" ]] || continue
    if chroot_lock_is_stale "$lock_path"; then
      rm -rf -- "$lock_path"
      repaired=$((repaired + 1))
    fi
  done
  printf '%s\n' "$repaired"
}
