chroot_tor_reserved_ipv4_cidrs() {
  cat <<'EOF'
0.0.0.0/8
10.0.0.0/8
100.64.0.0/10
127.0.0.0/8
169.254.0.0/16
172.16.0.0/12
192.0.0.0/24
192.168.0.0/16
198.18.0.0/15
224.0.0.0/4
240.0.0.0/4
255.255.255.255/32
EOF
}

chroot_tor_lan_bypass_ipv4_cidrs() {
  cat <<'EOF'
0.0.0.0/8
10.0.0.0/8
100.64.0.0/10
169.254.0.0/16
172.16.0.0/12
192.0.0.0/24
192.168.0.0/16
198.18.0.0/15
224.0.0.0/4
240.0.0.0/4
255.255.255.255/32
EOF
}

chroot_tor_iptables_has_rule() {
  local bin="$1"
  shift
  local -a args=("$@")
  local table="filter" chain="" expected=""
  local idx

  if "$bin" -w 2 "$@" >/dev/null 2>&1; then
    return 0
  fi
  if "$bin" "$@" >/dev/null 2>&1; then
    return 0
  fi

  for (( idx=0; idx<${#args[@]}; idx++ )); do
    case "${args[$idx]}" in
      -t)
        if (( idx + 1 < ${#args[@]} )); then
          table="${args[$((idx + 1))]}"
        fi
        ;;
      -C)
        if (( idx + 1 < ${#args[@]} )); then
          chain="${args[$((idx + 1))]}"
          expected="-A $chain"
          if (( idx + 2 < ${#args[@]} )); then
            expected+=" ${args[*]:$((idx + 2))}"
          fi
        fi
        break
        ;;
    esac
  done

  [[ -n "$chain" && -n "$expected" ]] || return 1
  "$bin" -t "$table" -S "$chain" 2>/dev/null | grep -Fqx -- "$expected"
}

chroot_tor_iptables_run() {
  local bin="$1"
  shift
  local err_file rc
  err_file="$CHROOT_TMP_DIR/tor-iptables.$$.err"
  if "$bin" -w 2 "$@" >/dev/null 2>"$err_file"; then
    CHROOT_TOR_LAST_RULE_ERROR=""
    rm -f -- "$err_file"
    return 0
  fi
  : >"$err_file"
  if "$bin" "$@" >/dev/null 2>"$err_file"; then
    CHROOT_TOR_LAST_RULE_ERROR=""
    rm -f -- "$err_file"
    return 0
  fi
  rc=$?
  CHROOT_TOR_LAST_RULE_ERROR="$(tr '\n' ' ' <"$err_file" 2>/dev/null | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"
  rm -f -- "$err_file"
  return "$rc"
}

chroot_tor_iptables_ensure_chain() {
  local bin="$1"
  local table="$2"
  local chain="$3"
  if ! "$bin" -t "$table" -S "$chain" >/dev/null 2>&1; then
    chroot_tor_iptables_run "$bin" -t "$table" -N "$chain" || return 1
  fi
  chroot_tor_iptables_run "$bin" -t "$table" -F "$chain"
}

chroot_tor_iptables_delete_jump() {
  local bin="$1"
  local table="$2"
  local parent="$3"
  local target="$4"
  while chroot_tor_iptables_has_rule "$bin" -t "$table" -C "$parent" -j "$target"; do
    chroot_tor_iptables_run "$bin" -t "$table" -D "$parent" -j "$target" || break
  done
}

chroot_tor_iptables_flush_delete_chain() {
  local bin="$1"
  local table="$2"
  local chain="$3"
  chroot_tor_iptables_run "$bin" -t "$table" -F "$chain" >/dev/null 2>&1 || true
  chroot_tor_iptables_run "$bin" -t "$table" -X "$chain" >/dev/null 2>&1 || true
}

chroot_tor_ip_run() {
  local err_file rc
  err_file="$CHROOT_TMP_DIR/tor-ip.$$.err"
  if chroot_run_root "$CHROOT_TOR_IP_BIN" "$@" >/dev/null 2>"$err_file"; then
    CHROOT_TOR_LAST_RULE_ERROR=""
    rm -f -- "$err_file"
    return 0
  fi
  rc=$?
  CHROOT_TOR_LAST_RULE_ERROR="$(tr '\n' ' ' <"$err_file" 2>/dev/null | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"
  rm -f -- "$err_file"
  return "$rc"
}

chroot_tor_policy_pref_list() {
  local family="$1"
  local start_pref="$2"
  local end_pref="$3"
  local -a cmd=("$CHROOT_TOR_IP_BIN" rule list)

  if [[ "$family" == "6" ]]; then
    cmd=("$CHROOT_TOR_IP_BIN" -6 rule list)
  fi

  chroot_run_root "${cmd[@]}" 2>/dev/null | awk -F: -v min="$start_pref" -v max="$end_pref" '
    $1 ~ /^[0-9]+$/ {
      pref = $1 + 0
      if (pref >= min && pref <= max) {
        print pref
      }
    }
  '
}

chroot_tor_policy_rule_exists() {
  local family="$1"
  local pref="$2"
  local -a cmd=("$CHROOT_TOR_IP_BIN" rule list)

  if [[ "$family" == "6" ]]; then
    cmd=("$CHROOT_TOR_IP_BIN" -6 rule list)
  fi

  chroot_run_root "${cmd[@]}" 2>/dev/null | awk -F: -v wanted="$pref" '
    $1 ~ /^[0-9]+$/ && ($1 + 0) == wanted { found = 1 }
    END { exit(found ? 0 : 1) }
  '
}

chroot_tor_policy_active_prefs() {
  local distro="$1"
  local family="$2"

  case "$family" in
    4)
      if (( ${#CHROOT_TOR_POLICY_V4_ACTIVE_PREFS[@]} > 0 )); then
        printf '%s\n' "${CHROOT_TOR_POLICY_V4_ACTIVE_PREFS[@]}"
        return 0
      fi
      ;;
    6)
      if (( ${#CHROOT_TOR_POLICY_V6_ACTIVE_PREFS[@]} > 0 )); then
        printf '%s\n' "${CHROOT_TOR_POLICY_V6_ACTIVE_PREFS[@]}"
        return 0
      fi
      ;;
  esac

  chroot_tor_policy_read_prefs_file "$distro" "$family"
}

chroot_tor_policy_rules_active_v4() {
  local distro="$1"
  local pref found=0

  [[ -n "$CHROOT_TOR_IP_BIN" ]] || return 1
  while IFS= read -r pref; do
    [[ "$pref" =~ ^[0-9]+$ ]] || continue
    found=1
    chroot_tor_policy_rule_exists 4 "$pref" || return 1
  done < <(chroot_tor_policy_active_prefs "$distro" 4)
  (( found == 1 ))
}

chroot_tor_policy_rules_active_v6() {
  local distro="$1"
  local pref found=0

  [[ -n "$CHROOT_TOR_IP_BIN" ]] || return 1
  while IFS= read -r pref; do
    [[ "$pref" =~ ^[0-9]+$ ]] || continue
    found=1
    chroot_tor_policy_rule_exists 6 "$pref" || return 1
  done < <(chroot_tor_policy_active_prefs "$distro" 6)
  (( found == 1 ))
}

chroot_tor_policy_remove_rules() {
  local distro="$1"
  local pref

  if [[ -z "$CHROOT_TOR_IP_BIN" ]]; then
    CHROOT_TOR_POLICY_V4_ACTIVE_PREFS=()
    CHROOT_TOR_POLICY_V6_ACTIVE_PREFS=()
    chroot_tor_policy_clear_state "$distro"
    return 0
  fi

  while IFS= read -r pref; do
    [[ "$pref" =~ ^[0-9]+$ ]] || continue
    chroot_tor_ip_run rule del pref "$pref" >/dev/null 2>&1 || true
  done < <(chroot_tor_policy_active_prefs "$distro" 4 | sort -rn)

  while IFS= read -r pref; do
    [[ "$pref" =~ ^[0-9]+$ ]] || continue
    chroot_tor_ip_run -6 rule del pref "$pref" >/dev/null 2>&1 || true
  done < <(chroot_tor_policy_active_prefs "$distro" 6 | sort -rn)

  chroot_tor_ip_run route flush table "$CHROOT_TOR_POLICY_V4_TABLE" >/dev/null 2>&1 || true
  chroot_tor_ip_run -6 route flush table "$CHROOT_TOR_POLICY_V6_TABLE" >/dev/null 2>&1 || true
  CHROOT_TOR_POLICY_V4_ACTIVE_PREFS=()
  CHROOT_TOR_POLICY_V6_ACTIVE_PREFS=()
  chroot_tor_policy_clear_state "$distro"
}

chroot_tor_policy_apply_v4() {
  local distro="$1"
  local lan_bypass="${2:-1}"
  local pref="$CHROOT_TOR_POLICY_V4_PREF_BASE"
  local uid_spec cidr
  local -a applied_prefs=()

  [[ -n "$CHROOT_TOR_IP_BIN" ]] || {
    CHROOT_TOR_LAST_RULE_ERROR="ip binary unavailable for v4 policy routing fallback"
    return 1
  }

  CHROOT_TOR_POLICY_V4_ACTIVE_PREFS=()
  chroot_tor_policy_clear_prefs_file "$distro" 4 >/dev/null 2>&1 || true
  chroot_tor_ip_run route replace unreachable default table "$CHROOT_TOR_POLICY_V4_TABLE" || return 1

  while IFS= read -r uid_spec; do
    [[ -n "$uid_spec" ]] || continue
    cidr="127.0.0.0/8"
    (( pref <= CHROOT_TOR_POLICY_V4_PREF_END )) || {
      CHROOT_TOR_LAST_RULE_ERROR="v4 policy rule budget exceeded"
      return 1
    }
    chroot_tor_ip_run rule add pref "$pref" uidrange "$uid_spec" to "$cidr" lookup main || return 1
    applied_prefs+=("$pref")
    CHROOT_TOR_POLICY_V4_ACTIVE_PREFS=("${applied_prefs[@]}")
    pref=$((pref + 1))

    if [[ "$lan_bypass" == "1" ]]; then
      while IFS= read -r cidr; do
        [[ -n "$cidr" ]] || continue
        (( pref <= CHROOT_TOR_POLICY_V4_PREF_END )) || {
          CHROOT_TOR_LAST_RULE_ERROR="v4 policy rule budget exceeded"
          return 1
        }
        chroot_tor_ip_run rule add pref "$pref" uidrange "$uid_spec" to "$cidr" lookup main || return 1
        applied_prefs+=("$pref")
        CHROOT_TOR_POLICY_V4_ACTIVE_PREFS=("${applied_prefs[@]}")
        pref=$((pref + 1))
      done < <(chroot_tor_lan_bypass_ipv4_cidrs)
    fi

    (( pref <= CHROOT_TOR_POLICY_V4_PREF_END )) || {
      CHROOT_TOR_LAST_RULE_ERROR="v4 policy rule budget exceeded"
      return 1
    }
    chroot_tor_ip_run rule add pref "$pref" uidrange "$uid_spec" ipproto udp dport 53 lookup main || return 1
    applied_prefs+=("$pref")
    CHROOT_TOR_POLICY_V4_ACTIVE_PREFS=("${applied_prefs[@]}")
    pref=$((pref + 1))

    (( pref <= CHROOT_TOR_POLICY_V4_PREF_END )) || {
      CHROOT_TOR_LAST_RULE_ERROR="v4 policy rule budget exceeded"
      return 1
    }
    chroot_tor_ip_run rule add pref "$pref" uidrange "$uid_spec" ipproto udp lookup "$CHROOT_TOR_POLICY_V4_TABLE" || return 1
    applied_prefs+=("$pref")
    CHROOT_TOR_POLICY_V4_ACTIVE_PREFS=("${applied_prefs[@]}")
    pref=$((pref + 1))
  done < <(chroot_tor_target_uid_specs "$distro")

  chroot_tor_policy_write_prefs_file "$distro" 4 "${applied_prefs[@]}"
}

chroot_tor_policy_apply_v6() {
  local distro="$1"
  local pref="$CHROOT_TOR_POLICY_V6_PREF_BASE"
  local uid_spec
  local -a applied_prefs=()

  [[ -n "$CHROOT_TOR_IP_BIN" ]] || {
    CHROOT_TOR_LAST_RULE_ERROR="ip binary unavailable for v6 policy routing fallback"
    return 1
  }

  CHROOT_TOR_POLICY_V6_ACTIVE_PREFS=()
  chroot_tor_policy_clear_prefs_file "$distro" 6 >/dev/null 2>&1 || true
  chroot_tor_ip_run -6 route replace unreachable default table "$CHROOT_TOR_POLICY_V6_TABLE" || return 1

  while IFS= read -r uid_spec; do
    [[ -n "$uid_spec" ]] || continue
    (( pref <= CHROOT_TOR_POLICY_V6_PREF_END )) || {
      CHROOT_TOR_LAST_RULE_ERROR="v6 policy rule budget exceeded"
      return 1
    }
    chroot_tor_ip_run -6 rule add pref "$pref" uidrange "$uid_spec" to ::1/128 lookup main || return 1
    applied_prefs+=("$pref")
    CHROOT_TOR_POLICY_V6_ACTIVE_PREFS=("${applied_prefs[@]}")
    pref=$((pref + 1))

    (( pref <= CHROOT_TOR_POLICY_V6_PREF_END )) || {
      CHROOT_TOR_LAST_RULE_ERROR="v6 policy rule budget exceeded"
      return 1
    }
    chroot_tor_ip_run -6 rule add pref "$pref" uidrange "$uid_spec" lookup "$CHROOT_TOR_POLICY_V6_TABLE" || return 1
    applied_prefs+=("$pref")
    CHROOT_TOR_POLICY_V6_ACTIVE_PREFS=("${applied_prefs[@]}")
    pref=$((pref + 1))
  done < <(chroot_tor_target_uid_specs "$distro")

  chroot_tor_policy_write_prefs_file "$distro" 6 "${applied_prefs[@]}"
}

chroot_tor_rules_active() {
  local distro="$1"
  [[ -n "$CHROOT_TOR_IPTABLES_BIN" ]] || return 1
  chroot_tor_iptables_has_rule "$CHROOT_TOR_IPTABLES_BIN" -t nat -C OUTPUT -j "$CHROOT_TOR_CHAIN_NAT" || return 1
  if ! chroot_tor_iptables_has_rule "$CHROOT_TOR_IPTABLES_BIN" -t filter -C OUTPUT -j "$CHROOT_TOR_CHAIN_FILTER"; then
    chroot_tor_policy_rules_active_v4 "$distro" || return 1
  fi
  if [[ -n "$CHROOT_TOR_IP6TABLES_BIN" ]]; then
    if ! chroot_tor_iptables_has_rule "$CHROOT_TOR_IP6TABLES_BIN" -t filter -C OUTPUT -j "$CHROOT_TOR_CHAIN_FILTER6"; then
      chroot_tor_policy_rules_active_v6 "$distro" || return 1
    fi
  else
    chroot_tor_policy_rules_active_v6 "$distro" || return 1
  fi
}

chroot_tor_remove_rules() {
  local distro="$1"
  chroot_tor_policy_remove_rules "$distro"
  if [[ -n "$CHROOT_TOR_IPTABLES_BIN" ]]; then
    chroot_tor_iptables_delete_jump "$CHROOT_TOR_IPTABLES_BIN" nat OUTPUT "$CHROOT_TOR_CHAIN_NAT"
    chroot_tor_iptables_delete_jump "$CHROOT_TOR_IPTABLES_BIN" filter OUTPUT "$CHROOT_TOR_CHAIN_FILTER"
    chroot_tor_iptables_flush_delete_chain "$CHROOT_TOR_IPTABLES_BIN" nat "$CHROOT_TOR_CHAIN_NAT"
    chroot_tor_iptables_flush_delete_chain "$CHROOT_TOR_IPTABLES_BIN" filter "$CHROOT_TOR_CHAIN_FILTER"
  fi
  if [[ -n "$CHROOT_TOR_IP6TABLES_BIN" ]]; then
    chroot_tor_iptables_delete_jump "$CHROOT_TOR_IP6TABLES_BIN" filter OUTPUT "$CHROOT_TOR_CHAIN_FILTER6"
    chroot_tor_iptables_flush_delete_chain "$CHROOT_TOR_IP6TABLES_BIN" filter "$CHROOT_TOR_CHAIN_FILTER6"
  fi
}

chroot_tor_apply_rules() {
  local distro="$1"
  local daemon_uid="$2"
  local v4_backend="${3:-filter}"
  local v6_backend="${4:-filter}"
  local lan_bypass="${5:-1}"
  local uid_spec cidr

  chroot_tor_iptables_ensure_chain "$CHROOT_TOR_IPTABLES_BIN" nat "$CHROOT_TOR_CHAIN_NAT" || return 1
  if [[ "$v4_backend" == "filter" ]]; then
    chroot_tor_iptables_ensure_chain "$CHROOT_TOR_IPTABLES_BIN" filter "$CHROOT_TOR_CHAIN_FILTER" || return 1
  fi
  if [[ "$v6_backend" == "filter" ]]; then
    chroot_tor_iptables_ensure_chain "$CHROOT_TOR_IP6TABLES_BIN" filter "$CHROOT_TOR_CHAIN_FILTER6" || return 1
  fi

  chroot_tor_iptables_run "$CHROOT_TOR_IPTABLES_BIN" -t nat -A "$CHROOT_TOR_CHAIN_NAT" -m owner --uid-owner "$daemon_uid" -j RETURN || return 1
  chroot_tor_iptables_run "$CHROOT_TOR_IPTABLES_BIN" -t nat -A "$CHROOT_TOR_CHAIN_NAT" -o lo -j RETURN || return 1
  if [[ "$lan_bypass" == "1" ]]; then
    while IFS= read -r cidr; do
      [[ -n "$cidr" ]] || continue
      chroot_tor_iptables_run "$CHROOT_TOR_IPTABLES_BIN" -t nat -A "$CHROOT_TOR_CHAIN_NAT" -d "$cidr" -j RETURN || return 1
    done < <(chroot_tor_lan_bypass_ipv4_cidrs)
  fi

  while IFS= read -r uid_spec; do
    [[ -n "$uid_spec" ]] || continue
    chroot_tor_iptables_run "$CHROOT_TOR_IPTABLES_BIN" -t nat -A "$CHROOT_TOR_CHAIN_NAT" -m owner --uid-owner "$uid_spec" -p udp --dport 53 -j REDIRECT --to-ports "$CHROOT_TOR_DEFAULT_DNS_PORT" || return 1
    chroot_tor_iptables_run "$CHROOT_TOR_IPTABLES_BIN" -t nat -A "$CHROOT_TOR_CHAIN_NAT" -m owner --uid-owner "$uid_spec" -p tcp --dport 53 -j REDIRECT --to-ports "$CHROOT_TOR_DEFAULT_DNS_PORT" || return 1
    chroot_tor_iptables_run "$CHROOT_TOR_IPTABLES_BIN" -t nat -A "$CHROOT_TOR_CHAIN_NAT" -m owner --uid-owner "$uid_spec" -p tcp -j REDIRECT --to-ports "$CHROOT_TOR_DEFAULT_TRANS_PORT" || return 1
  done < <(chroot_tor_target_uid_specs "$distro")

  if [[ "$v4_backend" == "filter" ]]; then
    chroot_tor_iptables_run "$CHROOT_TOR_IPTABLES_BIN" -t filter -A "$CHROOT_TOR_CHAIN_FILTER" -m owner --uid-owner "$daemon_uid" -j RETURN || return 1
    chroot_tor_iptables_run "$CHROOT_TOR_IPTABLES_BIN" -t filter -A "$CHROOT_TOR_CHAIN_FILTER" -o lo -j RETURN || return 1
    if [[ "$lan_bypass" == "1" ]]; then
      while IFS= read -r cidr; do
        [[ -n "$cidr" ]] || continue
        chroot_tor_iptables_run "$CHROOT_TOR_IPTABLES_BIN" -t filter -A "$CHROOT_TOR_CHAIN_FILTER" -d "$cidr" -j RETURN || return 1
      done < <(chroot_tor_lan_bypass_ipv4_cidrs)
    fi

    while IFS= read -r uid_spec; do
      [[ -n "$uid_spec" ]] || continue
      chroot_tor_iptables_run "$CHROOT_TOR_IPTABLES_BIN" -t filter -A "$CHROOT_TOR_CHAIN_FILTER" -m owner --uid-owner "$uid_spec" -p udp -j REJECT || return 1
    done < <(chroot_tor_target_uid_specs "$distro")
  else
    chroot_tor_iptables_flush_delete_chain "$CHROOT_TOR_IPTABLES_BIN" filter "$CHROOT_TOR_CHAIN_FILTER"
    chroot_tor_policy_apply_v4 "$distro" "$lan_bypass" || return 1
  fi

  if [[ "$v6_backend" == "filter" ]]; then
    chroot_tor_iptables_run "$CHROOT_TOR_IP6TABLES_BIN" -t filter -A "$CHROOT_TOR_CHAIN_FILTER6" -m owner --uid-owner "$daemon_uid" -j RETURN || return 1
    chroot_tor_iptables_run "$CHROOT_TOR_IP6TABLES_BIN" -t filter -A "$CHROOT_TOR_CHAIN_FILTER6" -o lo -j RETURN || return 1
    while IFS= read -r uid_spec; do
      [[ -n "$uid_spec" ]] || continue
      chroot_tor_iptables_run "$CHROOT_TOR_IP6TABLES_BIN" -t filter -A "$CHROOT_TOR_CHAIN_FILTER6" -m owner --uid-owner "$uid_spec" -j REJECT || return 1
    done < <(chroot_tor_target_uid_specs "$distro")
  else
    chroot_tor_iptables_flush_delete_chain "$CHROOT_TOR_IP6TABLES_BIN" filter "$CHROOT_TOR_CHAIN_FILTER6"
    chroot_tor_policy_apply_v6 "$distro" || return 1
  fi

  chroot_tor_iptables_delete_jump "$CHROOT_TOR_IPTABLES_BIN" nat OUTPUT "$CHROOT_TOR_CHAIN_NAT"
  chroot_tor_iptables_delete_jump "$CHROOT_TOR_IPTABLES_BIN" filter OUTPUT "$CHROOT_TOR_CHAIN_FILTER"
  chroot_tor_iptables_delete_jump "$CHROOT_TOR_IP6TABLES_BIN" filter OUTPUT "$CHROOT_TOR_CHAIN_FILTER6"

  chroot_tor_iptables_run "$CHROOT_TOR_IPTABLES_BIN" -t nat -I OUTPUT 1 -j "$CHROOT_TOR_CHAIN_NAT" || return 1
  if [[ "$v4_backend" == "filter" ]]; then
    chroot_tor_iptables_run "$CHROOT_TOR_IPTABLES_BIN" -t filter -I OUTPUT 1 -j "$CHROOT_TOR_CHAIN_FILTER" || return 1
  fi
  if [[ "$v6_backend" == "filter" ]]; then
    chroot_tor_iptables_run "$CHROOT_TOR_IP6TABLES_BIN" -t filter -I OUTPUT 1 -j "$CHROOT_TOR_CHAIN_FILTER6" || return 1
  fi
}

chroot_tor_routing_probe_tsv() {
  local daemon_uid="$1"
  local nat_probe=0 filter_probe=0 filter6_probe=0 policy4_probe=0 policy6_probe=0
  local nat_error="" filter_error="" filter6_error="" policy4_error="" policy6_error=""
  local nat_chain filter_chain filter6_chain
  local probe_uid
  local probe_v4_table=52140 probe_v6_table=52141
  local probe_v4_pref_allow=32040 probe_v4_pref_block=32041
  local probe_v6_pref_allow=32042 probe_v6_pref_block=32043

  nat_chain="AURORA_TORP_NAT_$$"
  filter_chain="AURORA_TORP_FILT_$$"
  filter6_chain="AURORA_TORP6_FILT_$$"
  probe_uid="${daemon_uid:-0}"

  if [[ -n "$CHROOT_TOR_IPTABLES_BIN" ]]; then
    if chroot_tor_iptables_run "$CHROOT_TOR_IPTABLES_BIN" -t nat -N "$nat_chain" \
      && chroot_tor_iptables_run "$CHROOT_TOR_IPTABLES_BIN" -t nat -A "$nat_chain" -m owner --uid-owner "$daemon_uid" -j RETURN \
      && chroot_tor_iptables_run "$CHROOT_TOR_IPTABLES_BIN" -t nat -A "$nat_chain" -p tcp -j REDIRECT --to-ports 1 \
      && chroot_tor_iptables_run "$CHROOT_TOR_IPTABLES_BIN" -t nat -I OUTPUT 1 -j "$nat_chain"; then
      if chroot_tor_iptables_has_rule "$CHROOT_TOR_IPTABLES_BIN" -t nat -C OUTPUT -j "$nat_chain"; then
        nat_probe=1
      else
        nat_error="nat OUTPUT jump did not persist after insert"
      fi
    else
      nat_error="${CHROOT_TOR_LAST_RULE_ERROR:-failed to insert nat probe rules}"
    fi
    chroot_tor_iptables_delete_jump "$CHROOT_TOR_IPTABLES_BIN" nat OUTPUT "$nat_chain"
    chroot_tor_iptables_flush_delete_chain "$CHROOT_TOR_IPTABLES_BIN" nat "$nat_chain"

    if chroot_tor_iptables_run "$CHROOT_TOR_IPTABLES_BIN" -t filter -N "$filter_chain" \
      && chroot_tor_iptables_run "$CHROOT_TOR_IPTABLES_BIN" -t filter -A "$filter_chain" -m owner --uid-owner "$daemon_uid" -j RETURN \
      && chroot_tor_iptables_run "$CHROOT_TOR_IPTABLES_BIN" -t filter -A "$filter_chain" -p udp -j REJECT \
      && chroot_tor_iptables_run "$CHROOT_TOR_IPTABLES_BIN" -t filter -I OUTPUT 1 -j "$filter_chain"; then
      if chroot_tor_iptables_has_rule "$CHROOT_TOR_IPTABLES_BIN" -t filter -C OUTPUT -j "$filter_chain"; then
        filter_probe=1
      else
        filter_error="filter OUTPUT jump did not persist after insert"
      fi
    else
      filter_error="${CHROOT_TOR_LAST_RULE_ERROR:-failed to insert filter probe rules}"
    fi
    chroot_tor_iptables_delete_jump "$CHROOT_TOR_IPTABLES_BIN" filter OUTPUT "$filter_chain"
    chroot_tor_iptables_flush_delete_chain "$CHROOT_TOR_IPTABLES_BIN" filter "$filter_chain"
  else
    nat_error="iptables binary unavailable"
    filter_error="iptables binary unavailable"
  fi

  if [[ -n "$CHROOT_TOR_IP6TABLES_BIN" ]]; then
    if chroot_tor_iptables_run "$CHROOT_TOR_IP6TABLES_BIN" -t filter -N "$filter6_chain" \
      && chroot_tor_iptables_run "$CHROOT_TOR_IP6TABLES_BIN" -t filter -A "$filter6_chain" -m owner --uid-owner "$daemon_uid" -j RETURN \
      && chroot_tor_iptables_run "$CHROOT_TOR_IP6TABLES_BIN" -t filter -A "$filter6_chain" -j REJECT \
      && chroot_tor_iptables_run "$CHROOT_TOR_IP6TABLES_BIN" -t filter -I OUTPUT 1 -j "$filter6_chain"; then
      if chroot_tor_iptables_has_rule "$CHROOT_TOR_IP6TABLES_BIN" -t filter -C OUTPUT -j "$filter6_chain"; then
        filter6_probe=1
      else
        filter6_error="ip6tables OUTPUT jump did not persist after insert"
      fi
    else
      filter6_error="${CHROOT_TOR_LAST_RULE_ERROR:-failed to insert ipv6 probe rules}"
    fi
    chroot_tor_iptables_delete_jump "$CHROOT_TOR_IP6TABLES_BIN" filter OUTPUT "$filter6_chain"
    chroot_tor_iptables_flush_delete_chain "$CHROOT_TOR_IP6TABLES_BIN" filter "$filter6_chain"
  else
    filter6_error="ip6tables binary unavailable"
  fi

  if [[ -n "$CHROOT_TOR_IP_BIN" ]]; then
    chroot_tor_ip_run route replace unreachable default table "$probe_v4_table" >/dev/null 2>&1 || true
    if chroot_tor_ip_run rule add pref "$probe_v4_pref_allow" uidrange "$probe_uid-$probe_uid" ipproto udp dport 53 lookup main \
      && chroot_tor_ip_run rule add pref "$probe_v4_pref_block" uidrange "$probe_uid-$probe_uid" ipproto udp lookup "$probe_v4_table"; then
      if chroot_tor_policy_rule_exists 4 "$probe_v4_pref_block"; then
        policy4_probe=1
      else
        policy4_error="v4 policy-routing block rule did not persist after insert"
      fi
    else
      policy4_error="${CHROOT_TOR_LAST_RULE_ERROR:-failed to insert v4 policy-routing probe rules}"
    fi
    chroot_tor_ip_run rule del pref "$probe_v4_pref_block" >/dev/null 2>&1 || true
    chroot_tor_ip_run rule del pref "$probe_v4_pref_allow" >/dev/null 2>&1 || true
    chroot_tor_ip_run route flush table "$probe_v4_table" >/dev/null 2>&1 || true

    chroot_tor_ip_run -6 route replace unreachable default table "$probe_v6_table" >/dev/null 2>&1 || true
    if chroot_tor_ip_run -6 rule add pref "$probe_v6_pref_allow" uidrange "$probe_uid-$probe_uid" to ::1/128 lookup main \
      && chroot_tor_ip_run -6 rule add pref "$probe_v6_pref_block" uidrange "$probe_uid-$probe_uid" lookup "$probe_v6_table"; then
      if chroot_tor_policy_rule_exists 6 "$probe_v6_pref_block"; then
        policy6_probe=1
      else
        policy6_error="v6 policy-routing block rule did not persist after insert"
      fi
    else
      policy6_error="${CHROOT_TOR_LAST_RULE_ERROR:-failed to insert v6 policy-routing probe rules}"
    fi
    chroot_tor_ip_run -6 rule del pref "$probe_v6_pref_block" >/dev/null 2>&1 || true
    chroot_tor_ip_run -6 rule del pref "$probe_v6_pref_allow" >/dev/null 2>&1 || true
    chroot_tor_ip_run -6 route flush table "$probe_v6_table" >/dev/null 2>&1 || true
  else
    policy4_error="ip binary unavailable"
    policy6_error="ip binary unavailable"
  fi

  printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
    "$nat_probe" "$nat_error" "$filter_probe" "$filter_error" "$filter6_probe" "$filter6_error" "$policy4_probe" "$policy4_error" "$policy6_probe" "$policy6_error"
}

chroot_tor_doctor_json() {
  local distro="$1"
  local family tor_bin_host install_backend daemon_user daemon_uid daemon_gid daemon_mode daemon_warning
  local nat_probe=0 filter_probe=0 filter6_probe=0 policy4_probe=0 policy6_probe=0
  local nat_error="" filter_error="" filter6_error="" policy4_error="" policy6_error=""

  chroot_tor_detect_backends 0
  family="$(chroot_tor_detect_distro_family "$distro")"
  tor_bin_host="$(chroot_tor_rootfs_tor_bin "$distro" || true)"
  install_backend="$(chroot_tor_detect_install_backend "$distro")"
  IFS='|' read -r daemon_mode daemon_user daemon_uid daemon_gid daemon_warning <<<"$(chroot_tor_detect_daemon_identity "$distro")"
  IFS='|' read -r nat_probe nat_error filter_probe filter_error filter6_probe filter6_error policy4_probe policy4_error policy6_probe policy6_error <<<"$(chroot_tor_routing_probe_tsv "${daemon_uid:-0}")"

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$distro" "$family" "$tor_bin_host" "$install_backend" "$daemon_mode" "$daemon_user" "$daemon_uid" "$daemon_gid" "$daemon_warning" "${CHROOT_TOR_IPTABLES_BIN:-}" "${CHROOT_TOR_IP6TABLES_BIN:-}" "${CHROOT_TOR_IP_BIN:-}" "$nat_probe" "$nat_error" "$filter_probe" "$filter_error" "$filter6_probe" "$filter6_error" "$policy4_probe" "$policy4_error" "$policy6_probe" "$policy6_error" "$(chroot_tor_rotation_minutes)" "$(chroot_tor_bootstrap_timeout_seconds)" <<'PY'
import json
import sys

(
    distro,
    family,
    tor_bin,
    install_backend,
    daemon_mode,
    daemon_user,
    daemon_uid,
    daemon_gid,
    daemon_warning,
    iptables_bin,
    ip6tables_bin,
    ip_bin,
    nat_probe,
    nat_error,
    filter_probe,
    filter_error,
    filter6_probe,
    filter6_error,
    policy4_probe,
    policy4_error,
    policy6_probe,
    policy6_error,
    rotation_min,
    bootstrap_timeout_sec,
) = sys.argv[1:25]

effective_v4 = "filter" if filter_probe == "1" else ("policy-routing" if policy4_probe == "1" else "unsupported")
effective_v6 = "filter" if filter6_probe == "1" else ("policy-routing" if policy6_probe == "1" else "unsupported")

payload = {
    "distro": distro,
    "backend": {
        "distro_family": family,
        "tor_binary": tor_bin,
        "install_backend": install_backend,
        "auto_install_available": bool(install_backend),
        "iptables_v4": iptables_bin,
        "ip6tables": ip6tables_bin,
        "ip": ip_bin,
    },
    "daemon_identity": {
        "mode": daemon_mode,
        "user": daemon_user,
        "uid": int(daemon_uid) if str(daemon_uid).strip().isdigit() else None,
        "gid": int(daemon_gid) if str(daemon_gid).strip().isdigit() else None,
        "warning": daemon_warning,
    },
    "rotation": {
        "tor_rotation_min": int(rotation_min),
        "bootstrap_timeout_sec": int(bootstrap_timeout_sec),
    },
    "routing_probe": {
        "nat_ok": nat_probe == "1",
        "nat_error": nat_error,
        "filter_ok": filter_probe == "1",
        "filter_error": filter_error,
        "filter6_ok": filter6_probe == "1",
        "filter6_error": filter6_error,
        "policy_v4_ok": policy4_probe == "1",
        "policy_v4_error": policy4_error,
        "policy_v6_ok": policy6_probe == "1",
        "policy_v6_error": policy6_error,
        "effective_v4": effective_v4,
        "effective_v6": effective_v6,
    },
}
print(json.dumps(payload, indent=2, sort_keys=True))
PY
}
