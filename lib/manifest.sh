#!/usr/bin/env bash

chroot_manifest_clean_field() {
  local value="${1:-}"
  value="${value//$'\t'/ }"
  value="${value//$'\r'/ }"
  value="${value//$'\n'/ }"
  printf '%s\n' "$value"
}

chroot_manifest_append_tsv() {
  local out="$1"
  local id="$2"
  local name="$3"
  local release="$4"
  local channel="$5"
  local install_target="$6"
  local arch="$7"
  local url="$8"
  local sha256="$9"
  local size_bytes="${10}"
  local compression="${11}"
  local source="${12}"
  local comment="${13:-}"

  id="$(chroot_manifest_clean_field "$id")"
  name="$(chroot_manifest_clean_field "$name")"
  release="$(chroot_manifest_clean_field "$release")"
  channel="$(chroot_manifest_clean_field "$channel")"
  install_target="$(chroot_manifest_clean_field "$install_target")"
  arch="$(chroot_manifest_clean_field "$arch")"
  url="$(chroot_manifest_clean_field "$url")"
  sha256="$(chroot_manifest_clean_field "$sha256")"
  size_bytes="$(chroot_manifest_clean_field "$size_bytes")"
  compression="$(chroot_manifest_clean_field "$compression")"
  source="$(chroot_manifest_clean_field "$source")"
  comment="$(chroot_manifest_clean_field "$comment")"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$id" "$name" "$release" "$channel" "$install_target" "$arch" "$url" "$sha256" "$size_bytes" "$compression" "$source" "$comment" >>"$out"
}

chroot_manifest_backfill_missing_sizes_tsv() {
  local tsv_file="$1"
  local tmp_file line_count=0
  local id name release channel install_target arch url sha256 size_bytes compression source comment refreshed_size

  [[ -f "$tsv_file" ]] || return 0
  tmp_file="$tsv_file.sizes.$$"
  : >"$tmp_file"

  while IFS=$'\t' read -r id name release channel install_target arch url sha256 size_bytes compression source comment || [[ -n "${id:-}" ]]; do
    [[ -n "${id:-}" ]] || continue
    if [[ ! "$size_bytes" =~ ^[0-9]+$ ]] || (( size_bytes <= 0 )); then
      refreshed_size="$(chroot_manifest_remote_size_bytes "$url" 20 2>/dev/null || printf '0')"
      if [[ "$refreshed_size" =~ ^[0-9]+$ ]] && (( refreshed_size > 0 )); then
        size_bytes="$refreshed_size"
      else
        size_bytes=0
      fi
    fi
    chroot_manifest_append_tsv "$tmp_file" "$id" "$name" "$release" "$channel" "$install_target" "$arch" "$url" "$sha256" "$size_bytes" "$compression" "$source" "$comment"
    line_count=$((line_count + 1))
  done <"$tsv_file"

  if (( line_count > 0 )); then
    mv -f -- "$tmp_file" "$tsv_file"
  else
    rm -f -- "$tmp_file"
  fi
}

chroot_manifest_normalize_arch() {
  local raw="${1:-}"
  raw="$(printf '%s\n' "$raw" | tr '[:upper:]' '[:lower:]')"
  case "$raw" in
    aarch64|arm64|arm64-v8a|armv8a|armv8|armv9|armv9l) printf 'aarch64\n' ;;
    arm|armv7|armv7l|armv7hl|armv8l|armhf|armel|armv6l|armeabi|armeabi-v7a) printf 'arm\n' ;;
    x86_64|amd64|x64|x86-64) printf 'x86_64\n' ;;
    i386|i486|i586|i686|x86) printf 'i386\n' ;;
    riscv64|rv64|riscv) printf 'riscv64\n' ;;
    *) printf 'unknown\n' ;;
  esac
}

chroot_manifest_android_abi_to_arch() {
  local raw="${1:-}"
  raw="$(chroot_manifest_trim "$raw" 2>/dev/null || printf '%s\n' "$raw")"
  raw="$(printf '%s\n' "$raw" | tr '[:upper:]' '[:lower:]')"
  case "$raw" in
    arm64-v8a|arm64|aarch64) printf 'aarch64\n' ;;
    armeabi-v7a|armeabi|armv7*|armhf|armel|armv6*|armv8l) printf 'arm\n' ;;
    x86_64|amd64|x64|x86-64) printf 'x86_64\n' ;;
    i386|i486|i586|i686|x86) printf 'i386\n' ;;
    riscv64|rv64) printf 'riscv64\n' ;;
    *) return 1 ;;
  esac
}

chroot_manifest_android_abi_list_to_arch() {
  local raw="${1:-}"
  local item arch
  local -a items
  local IFS=',; '

  read -r -a items <<<"$raw"
  for item in "${items[@]}"; do
    arch="$(chroot_manifest_android_abi_to_arch "$item" 2>/dev/null || true)"
    [[ -n "$arch" ]] || continue
    printf '%s\n' "$arch"
    return 0
  done
  return 1
}

chroot_manifest_android_arch_hint() {
  local getprop_bin=""
  local prop raw_arch

  if [[ -x "${CHROOT_SYSTEM_BIN_DEFAULT:-/system/bin}/getprop" ]]; then
    getprop_bin="${CHROOT_SYSTEM_BIN_DEFAULT:-/system/bin}/getprop"
  elif command -v getprop >/dev/null 2>&1; then
    getprop_bin="$(command -v getprop 2>/dev/null || true)"
  fi

  [[ -n "$getprop_bin" ]] || return 1

  while IFS= read -r prop; do
    [[ -n "$prop" ]] || continue
    raw_arch="$("$getprop_bin" "$prop" 2>/dev/null | tr -d '\r\n' || true)"
    [[ -n "$raw_arch" ]] || continue
    if raw_arch="$(chroot_manifest_android_abi_list_to_arch "$raw_arch" 2>/dev/null || true)"; then
      [[ -n "$raw_arch" ]] || continue
      printf '%s\n' "$raw_arch"
      return 0
    fi
  done <<'EOF_ANDROID_ABI_PROPS'
ro.product.cpu.abilist64
ro.system.product.cpu.abilist64
ro.vendor.product.cpu.abilist64
ro.product.cpu.abilist
ro.system.product.cpu.abilist
ro.vendor.product.cpu.abilist
ro.product.cpu.abilist32
ro.system.product.cpu.abilist32
ro.vendor.product.cpu.abilist32
ro.product.cpu.abi
ro.system.product.cpu.abi
ro.vendor.product.cpu.abi
EOF_ANDROID_ABI_PROPS

  return 1
}

chroot_manifest_host_arch() {
  local raw
  raw="$(chroot_manifest_android_arch_hint 2>/dev/null || true)"
  if [[ -n "$raw" ]]; then
    printf '%s\n' "$raw"
    return 0
  fi
  raw="$(uname -m 2>/dev/null || true)"
  chroot_manifest_normalize_arch "$raw"
}

chroot_manifest_require_supported_arch() {
  local arch
  arch="$(chroot_manifest_host_arch)"
  [[ "$arch" != "unknown" ]] || chroot_die "unsupported host architecture: $(uname -m 2>/dev/null || echo unknown)"
}

chroot_manifest_alpine_arch_key() {
  local arch="$1"
  case "$arch" in
    aarch64) printf 'aarch64\n' ;;
    arm) printf 'armv7\n' ;;
    x86_64) printf 'x86_64\n' ;;
    i386) printf 'x86\n' ;;
    riscv64) printf 'riscv64\n' ;;
    *) return 1 ;;
  esac
}

chroot_manifest_ubuntu_arch_key() {
  local arch="$1"
  case "$arch" in
    aarch64) printf 'arm64\n' ;;
    arm) printf 'armhf\n' ;;
    x86_64) printf 'amd64\n' ;;
    i386) printf 'i386\n' ;;
    riscv64) printf 'riscv64\n' ;;
    *) return 1 ;;
  esac
}

chroot_manifest_kali_arch_key() {
  local arch="$1"
  case "$arch" in
    aarch64) printf 'arm64\n' ;;
    arm) printf 'armhf\n' ;;
    x86_64) printf 'amd64\n' ;;
    i386) printf 'i386\n' ;;
    *) return 1 ;;
  esac
}

chroot_manifest_plugin_arch_keys() {
  local arch="$1"
  case "$arch" in
    aarch64) printf '%s\n' "aarch64" "arm64" "arm64-v8a" ;;
    arm) printf '%s\n' "arm" "armhf" "armv7l" "armeabi-v7a" ;;
    x86_64) printf '%s\n' "x86_64" "amd64" "x64" ;;
    i386) printf '%s\n' "i686" "i386" "x86" ;;
    riscv64) printf '%s\n' "riscv64" ;;
    *) return 1 ;;
  esac
}

chroot_manifest_selftest_emit() {
  local case_id="$1"
  local expected="$2"
  local actual="$3"
  local status="$4"
  expected="${expected//$'\t'/ }"
  expected="${expected//$'\n'/ }"
  actual="${actual//$'\t'/ }"
  actual="${actual//$'\n'/ }"
  printf '%s\t%s\t%s\t%s\n' "$case_id" "$expected" "$actual" "$status"
}

chroot_manifest_arch_selftest_rows() {
  local raw expected actual status

  while IFS=$'\t' read -r raw expected; do
    [[ -n "$raw" ]] || continue
    actual="$(chroot_manifest_normalize_arch "$raw")"
    status="pass"
    [[ "$actual" == "$expected" ]] || status="fail"
    chroot_manifest_selftest_emit "normalize:$raw" "$expected" "$actual" "$status"
  done <<'EOF_ARCH_NORMALIZE'
aarch64	aarch64
arm64	aarch64
armv7	arm
armv7l	arm
armv6l	arm
armhf	arm
x86_64	x86_64
amd64	x86_64
x64	x86_64
i686	i386
x86	i386
riscv64	riscv64
mips	unknown
EOF_ARCH_NORMALIZE

  while IFS=$'\t' read -r raw expected; do
    [[ -n "$raw" ]] || continue
    actual="$(chroot_manifest_alpine_arch_key "$raw" 2>/dev/null || true)"
    [[ -n "$actual" ]] || actual="(none)"
    status="pass"
    [[ "$actual" == "$expected" ]] || status="fail"
    chroot_manifest_selftest_emit "alpine_key:$raw" "$expected" "$actual" "$status"
  done <<'EOF_ARCH_ALPINE'
aarch64	aarch64
arm	armv7
x86_64	x86_64
i386	x86
riscv64	riscv64
unknown	(none)
EOF_ARCH_ALPINE

  while IFS=$'\t' read -r raw expected; do
    [[ -n "$raw" ]] || continue
    actual="$(chroot_manifest_ubuntu_arch_key "$raw" 2>/dev/null || true)"
    [[ -n "$actual" ]] || actual="(none)"
    status="pass"
    [[ "$actual" == "$expected" ]] || status="fail"
    chroot_manifest_selftest_emit "ubuntu_key:$raw" "$expected" "$actual" "$status"
  done <<'EOF_ARCH_UBUNTU'
aarch64	arm64
arm	armhf
x86_64	amd64
i386	i386
riscv64	riscv64
unknown	(none)
EOF_ARCH_UBUNTU

  while IFS=$'\t' read -r raw expected; do
    [[ -n "$raw" ]] || continue
    actual="$(chroot_manifest_kali_arch_key "$raw" 2>/dev/null || true)"
    [[ -n "$actual" ]] || actual="(none)"
    status="pass"
    [[ "$actual" == "$expected" ]] || status="fail"
    chroot_manifest_selftest_emit "kali_key:$raw" "$expected" "$actual" "$status"
  done <<'EOF_ARCH_KALI'
aarch64	arm64
arm	armhf
x86_64	amd64
i386	i386
riscv64	(none)
unknown	(none)
EOF_ARCH_KALI

  while IFS=$'\t' read -r raw expected; do
    [[ -n "$raw" ]] || continue
    actual="$(chroot_manifest_plugin_arch_keys "$raw" 2>/dev/null | paste -sd ',' - || true)"
    [[ -n "$actual" ]] || actual="(none)"
    status="pass"
    [[ "$actual" == "$expected" ]] || status="fail"
    chroot_manifest_selftest_emit "plugin_keys:$raw" "$expected" "$actual" "$status"
  done <<'EOF_ARCH_PLUGIN'
aarch64	aarch64,arm64,arm64-v8a
arm	arm,armhf,armv7l,armeabi-v7a
x86_64	x86_64,amd64,x64
i386	i686,i386,x86
riscv64	riscv64
unknown	(none)
EOF_ARCH_PLUGIN

  while IFS=$'\t' read -r raw expected; do
    [[ -n "$raw" ]] || continue
    actual="$(chroot_manifest_android_abi_to_arch "$raw" 2>/dev/null || true)"
    [[ -n "$actual" ]] || actual="(none)"
    status="pass"
    [[ "$actual" == "$expected" ]] || status="fail"
    chroot_manifest_selftest_emit "android_abi:$raw" "$expected" "$actual" "$status"
  done <<'EOF_ANDROID_ABI_SINGLE'
arm64-v8a	aarch64
arm64	aarch64
armeabi-v7a	arm
armeabi	arm
armv8l	arm
x86_64	x86_64
i686	i386
riscv64	riscv64
bogus	(none)
EOF_ANDROID_ABI_SINGLE

  while IFS=$'\t' read -r raw expected; do
    [[ -n "$raw" ]] || continue
    actual="$(chroot_manifest_android_abi_list_to_arch "$raw" 2>/dev/null || true)"
    [[ -n "$actual" ]] || actual="(none)"
    status="pass"
    [[ "$actual" == "$expected" ]] || status="fail"
    chroot_manifest_selftest_emit "android_abi_list:$raw" "$expected" "$actual" "$status"
  done <<'EOF_ANDROID_ABI_LIST'
arm64-v8a,armeabi-v7a	aarch64
armeabi-v7a,armeabi	arm
x86_64,x86_64	x86_64
i686,i386	i386
arm64-v8a;armeabi-v7a	aarch64
bogus,(none)	(none)
EOF_ANDROID_ABI_LIST

  local fixture
  fixture="$(mktemp "${CHROOT_TMP_DIR:-/tmp}/manifest-selftest.XXXXXX.json" 2>/dev/null || mktemp "/tmp/manifest-selftest.XXXXXX.json")"
  cat >"$fixture" <<'JSON_FIXTURE'
{
  "distros": [
    {
      "id": "demo",
      "release": "1.0",
      "arch": "x86_64",
      "rootfs_url": "https://example.invalid/demo.tar.xz",
      "sha256": "deadbeef",
      "install_target": "1.0"
    }
  ]
}
JSON_FIXTURE

  local rc expected_rc actual_rc
  rc=0
  chroot_manifest_select_entry_from_file_json "$fixture" "demo" "" "aarch64" >/dev/null 2>&1 || rc=$?
  expected_rc=2
  actual_rc="$rc"
  status="pass"
  [[ "$actual_rc" == "$expected_rc" ]] || status="fail"
  chroot_manifest_selftest_emit "upstream_arch_unavailable" "rc=$expected_rc" "rc=$actual_rc" "$status"

  rc=0
  chroot_manifest_select_entry_from_file_json "$fixture" "demo" "" "x86_64" >/dev/null 2>&1 || rc=$?
  expected_rc=0
  actual_rc="$rc"
  status="pass"
  [[ "$actual_rc" == "$expected_rc" ]] || status="fail"
  chroot_manifest_selftest_emit "upstream_arch_available" "rc=$expected_rc" "rc=$actual_rc" "$status"

  rc=0
  chroot_manifest_select_entry_from_file_json "$fixture" "missing" "" "x86_64" >/dev/null 2>&1 || rc=$?
  expected_rc=1
  actual_rc="$rc"
  status="pass"
  [[ "$actual_rc" == "$expected_rc" ]] || status="fail"
  chroot_manifest_selftest_emit "upstream_distro_missing" "rc=$expected_rc" "rc=$actual_rc" "$status"
  rm -f -- "$fixture"

  local candidates selection selected mode
  candidates=$'ubuntu-base-24.04.3-base-arm64.tar.gz\nubuntu-base-24.04.4-base-arm64.tar.gz\nubuntu-base-24.04.4-base-amd64.tar.gz'
  selection="$(chroot_manifest_select_archive_candidate "ubuntu" "24.04.4" "arm64" ".tar.gz" "$candidates" 2>/dev/null || true)"
  selected="$(chroot_manifest_archive_selection_field "$selection" selected 2>/dev/null || true)"
  mode="$(chroot_manifest_archive_selection_field "$selection" mode 2>/dev/null || true)"
  status="pass"
  [[ "$selected" == "ubuntu-base-24.04.4-base-arm64.tar.gz" && "$mode" == "exact" ]] || status="fail"
  chroot_manifest_selftest_emit "archive:ubuntu_exact_point" "ubuntu-base-24.04.4-base-arm64.tar.gz/exact" "$selected/$mode" "$status"

  candidates=$'ubuntu-base-24.04.3-base-arm64.tar.gz\nubuntu-base-24.04.4-base-arm64.tar.gz'
  selection="$(chroot_manifest_select_archive_candidate "ubuntu" "24.04.5" "arm64" ".tar.gz" "$candidates" 2>/dev/null || true)"
  selected="$(chroot_manifest_archive_selection_field "$selection" selected 2>/dev/null || true)"
  mode="$(chroot_manifest_archive_selection_field "$selection" mode 2>/dev/null || true)"
  status="pass"
  [[ "$selected" == "ubuntu-base-24.04.4-base-arm64.tar.gz" && "$mode" == "newest-same-series" ]] || status="fail"
  chroot_manifest_selftest_emit "archive:ubuntu_same_series_fallback" "ubuntu-base-24.04.4-base-arm64.tar.gz/newest-same-series" "$selected/$mode" "$status"

  candidates=$'ubuntu-base-22.04.5-base-amd64.tar.gz\nubuntu-base-22.04.4-base-amd64.tar.gz'
  selection="$(chroot_manifest_select_archive_candidate "ubuntu" "22.04.5" "arm64" ".tar.gz" "$candidates" 2>/dev/null || true)"
  selected="$(chroot_manifest_archive_selection_field "$selection" selected 2>/dev/null || true)"
  status="pass"
  [[ -z "$selected" ]] || status="fail"
  chroot_manifest_selftest_emit "archive:reject_wrong_arch" "(none)" "${selected:-"(none)"}" "$status"

  candidates=$'alpine-minirootfs-3.21.8-aarch64.tar.gz\nalpine-minirootfs-3.22.1-aarch64.tar.gz'
  selection="$(chroot_manifest_select_archive_candidate "alpine" "" "aarch64" ".tar.gz" "$candidates" 2>/dev/null || true)"
  selected="$(chroot_manifest_archive_selection_field "$selection" selected 2>/dev/null || true)"
  status="pass"
  [[ "$selected" == "alpine-minirootfs-3.22.1-aarch64.tar.gz" ]] || status="fail"
  chroot_manifest_selftest_emit "archive:alpine_newest" "alpine-minirootfs-3.22.1-aarch64.tar.gz" "$selected" "$status"

  candidates=$'kali-nethunter-rootfs-minimal-arm64.tar.xz\nkali-nethunter-rootfs-nano-arm64.tar.xz\nkali-nethunter-rootfs-full-arm64.tar.xz'
  selection="$(chroot_manifest_select_archive_candidate "kali" "nano" "arm64" ".tar.xz" "$candidates" 2>/dev/null || true)"
  selected="$(chroot_manifest_archive_selection_field "$selection" selected 2>/dev/null || true)"
  mode="$(chroot_manifest_archive_selection_field "$selection" mode 2>/dev/null || true)"
  status="pass"
  [[ "$selected" == "kali-nethunter-rootfs-nano-arm64.tar.xz" && "$mode" == "exact" ]] || status="fail"
  chroot_manifest_selftest_emit "archive:kali_exact_flavor" "kali-nethunter-rootfs-nano-arm64.tar.xz/exact" "$selected/$mode" "$status"

  while IFS=$'\t' read -r raw expected; do
    [[ -n "$raw" ]] || continue
    actual="$(chroot_manifest_guess_release_from_comment "$raw")"
    status="pass"
    [[ "$actual" == "$expected" ]] || status="fail"
    chroot_manifest_selftest_emit "comment_release:$raw" "$expected" "$actual" "$status"
  done <<'EOF_COMMENT_RELEASE'
Version 10.	10
Version 10.1	10.1
Version 43. Broken on Android 15+.	43
Leap release (16.0). No support for ARM and x86 32bit.	16.0
Version	current
EOF_COMMENT_RELEASE

  local tsv_fixture previous_fixture out_fixture rows_summary
  tsv_fixture="$(mktemp "${CHROOT_TMP_DIR:-/tmp}/manifest-live.XXXXXX.tsv" 2>/dev/null || mktemp "/tmp/manifest-live.XXXXXX.tsv")"
  previous_fixture="$(mktemp "${CHROOT_TMP_DIR:-/tmp}/manifest-prev.XXXXXX.json" 2>/dev/null || mktemp "/tmp/manifest-prev.XXXXXX.json")"
  out_fixture="$(mktemp "${CHROOT_TMP_DIR:-/tmp}/manifest-out.XXXXXX.json" 2>/dev/null || mktemp "/tmp/manifest-out.XXXXXX.json")"
  chroot_manifest_append_tsv "$tsv_fixture" "demo" "Demo Linux" "10" "release" "10" "aarch64" "https://example.invalid/demo.tar.xz" "abc123" "0" "tar.xz" "proot-plugin" "Version 10."
  cat >"$previous_fixture" <<'JSON_PREVIOUS_FIXTURE'
{
  "distros": [
    {
      "id": "demo",
      "name": "Demo Linux",
      "release": "current",
      "channel": "rolling",
      "install_target": "current",
      "arch": "aarch64",
      "rootfs_url": "https://example.invalid/demo.tar.xz",
      "sha256": "abc123",
      "size_bytes": 0,
      "compression": "tar.xz",
      "source": "proot-plugin",
      "provider_comment": "Version"
    }
  ]
}
JSON_PREVIOUS_FIXTURE
  chroot_manifest_build_json "$tsv_fixture" "$out_fixture" "$previous_fixture"
  rows_summary="$("$CHROOT_PYTHON_BIN" - "$out_fixture" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    rows = json.load(fh).get("distros", [])
print(",".join([f"{row.get('release')}:{row.get('stale')}" for row in rows]))
PY
)"
  status="pass"
  [[ "$rows_summary" == "10:False" ]] || status="fail"
  chroot_manifest_selftest_emit "manifest_merge:live_url_sha_replaces_stale" "10:False" "$rows_summary" "$status"
  rm -f -- "$tsv_fixture" "$previous_fixture" "$out_fixture"
}

chroot_manifest_trim() {
  local s="${1:-}"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s\n' "$s"
}

chroot_manifest_default_version_limit() {
  local limit="${CHROOT_CATALOG_VERSION_LIMIT_DEFAULT:-5}"
  if [[ ! "$limit" =~ ^[0-9]+$ ]] || (( limit <= 0 )); then
    limit=5
  fi
  printf '%s\n' "$limit"
}

chroot_manifest_detect_compression() {
  local url="${1:-}"
  case "$url" in
    *.tar.gz) printf 'tar.gz\n' ;;
    *.tar.xz) printf 'tar.xz\n' ;;
    *.tar.zst) printf 'tar.zst\n' ;;
    *.tar.bz2) printf 'tar.bz2\n' ;;
    *.tgz) printf 'tar.gz\n' ;;
    *) printf 'tar\n' ;;
  esac
}

chroot_manifest_guess_channel() {
  local rel
  rel="$(printf '%s\n' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  case "$rel" in
    *lts*) printf 'lts\n' ;;
    *stable*) printf 'stable\n' ;;
    *rolling*) printf 'rolling\n' ;;
    *interim*) printf 'interim\n' ;;
    current) printf 'rolling\n' ;;
    *release*|*[0-9]*) printf 'release\n' ;;
    '')
      printf 'release\n'
      ;;
    *)
      printf '%s\n' "$rel"
      ;;
  esac
}

chroot_manifest_guess_release_from_name() {
  local name="${1:-}"
  local rel=""

  rel="$(printf '%s\n' "$name" | sed -nE 's/.*\(([0-9][0-9A-Za-z._-]*)\).*/\1/p' | head -n1 || true)"
  if [[ -z "$rel" ]]; then
    if printf '%s\n' "$name" | grep -Eqi '\(([[:space:]]*)rolling'; then
      rel="rolling"
    elif printf '%s\n' "$name" | grep -Eqi '\(([[:space:]]*)stable'; then
      rel="stable"
    elif printf '%s\n' "$name" | grep -Eqi '\(([[:space:]]*)current'; then
      rel="current"
    fi
  fi

  chroot_manifest_trim "$rel"
}

chroot_manifest_guess_release_from_comment() {
  local comment="${1:-}"
  local rel=""

  rel="$(printf '%s\n' "$comment" | sed -nE 's/.*[Vv]ersion[[:space:]]+([0-9]+([.][0-9]+)*)([.])?([^0-9].*)?$/\1/p' | head -n1 || true)"
  if [[ -z "$rel" ]]; then
    rel="$(printf '%s\n' "$comment" | sed -nE 's/.*[Ll]eap[[:space:]]+release[[:space:]]*\(([0-9]+([.][0-9]+)*)\).*/\1/p' | head -n1 || true)"
  fi
  if [[ -z "$rel" ]]; then
    if printf '%s\n' "$comment" | grep -Eqi '\brolling\b'; then
      rel="rolling"
    elif printf '%s\n' "$comment" | grep -Eqi '\bcurrent\b'; then
      rel="current"
    elif printf '%s\n' "$comment" | grep -Eqi '\bstable\b'; then
      rel="stable"
    elif printf '%s\n' "$comment" | grep -Eqi '\blts\b'; then
      rel="lts"
    elif printf '%s\n' "$comment" | grep -Eqi '^[[:space:]]*version[[:space:].:-]*$'; then
      rel="current"
    fi
  fi

  chroot_manifest_trim "$rel"
}

chroot_manifest_guess_channel_from_comment() {
  local comment="${1:-}"
  if printf '%s\n' "$comment" | grep -Eqi '\blts\b'; then
    printf 'lts\n'
  elif printf '%s\n' "$comment" | grep -Eqi '\bstable\b'; then
    printf 'stable\n'
  elif printf '%s\n' "$comment" | grep -Eqi '\brolling\b'; then
    printf 'rolling\n'
  elif printf '%s\n' "$comment" | grep -Eqi '\bcurrent\b'; then
    printf 'current\n'
  else
    printf '\n'
  fi
}

chroot_manifest_guess_release_from_url() {
  local url="${1:-}"
  local distro_id="${2:-}"
  local base rel

  base="${url##*/}"
  base="$(printf '%s\n' "$base" | sed -E 's/-pd-v[0-9]+([.][0-9]+)*//g')"
  rel="$(printf '%s\n' "$base" | sed -nE "s/.*${distro_id}-([0-9][0-9A-Za-z._-]*)-[0-9A-Za-z._-]+\.tar\..*/\\1/p" | head -n1 || true)"
  if [[ -z "$rel" ]]; then
    rel="$(printf '%s\n' "$base" | sed -nE 's/.*-([0-9]{2}\.[0-9]+(\.[0-9]+)?)-.*/\1/p' | head -n1 || true)"
  fi
  chroot_manifest_trim "$rel"
}

chroot_manifest_select_archive_candidate() {
  local distro_id="$1"
  local requested="$2"
  local arch_key="$3"
  local suffixes="$4"
  local candidates_text="${5:-}"

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$distro_id" "$requested" "$arch_key" "$suffixes" "$candidates_text" <<'PY'
import json
import re
import sys

distro_id, requested, arch_key, suffixes_text, candidates_text = sys.argv[1:6]
suffixes = [s.strip().lower() for s in suffixes_text.split(",") if s.strip()]
candidates = []
seen = set()
for raw in candidates_text.splitlines():
    value = str(raw or "").strip()
    if not value:
        continue
    value = value.split()[0].lstrip("*")
    value = value.rsplit("/", 1)[-1]
    if not value or value in seen:
        continue
    seen.add(value)
    candidates.append(value)


def numeric_tokens(text):
    return tuple(int(x) for x in re.findall(r"\d+", str(text or "")))


def release_token(name):
    lowered = str(name or "").lower()
    lowered = re.sub(r"-pd-v\d+(?:\.\d+)*", "", lowered)
    matches = re.findall(r"(?<![a-z0-9])(\d+(?:\.\d+)+)(?![a-z0-9])", lowered)
    if matches:
        return matches[0]
    matches = re.findall(r"(?<![a-z0-9])(\d+)(?![a-z0-9])", lowered)
    return matches[0] if matches else ""


def contains_token(name, token):
    token = str(token or "").strip()
    if not token:
        return False
    return re.search(r"(?<![A-Za-z0-9])" + re.escape(token) + r"(?![A-Za-z0-9])", name) is not None


def arch_matches(name):
    if not arch_key:
        return True
    return contains_token(name, arch_key)


def suffix_matches(name):
    lowered = name.lower()
    return not suffixes or any(lowered.endswith(suffix) for suffix in suffixes)


filtered = [name for name in candidates if suffix_matches(name) and arch_matches(name)]
requested = str(requested or "").strip()
mode = "none"
selected = ""
selected_release = ""

if requested:
    exact = [name for name in filtered if contains_token(name, requested)]
    if exact:
        exact.sort(key=lambda name: (numeric_tokens(release_token(name)), name))
        selected = exact[-1]
        selected_release = release_token(selected)
        mode = "exact"

if not selected and requested and numeric_tokens(requested):
    req_tokens = numeric_tokens(requested)
    series = req_tokens[:2] if len(req_tokens) >= 2 else req_tokens[:1]
    same_series = []
    for name in filtered:
        rel = release_token(name)
        tokens = numeric_tokens(rel)
        if tokens[: len(series)] == series:
            same_series.append(name)
    if same_series:
        same_series.sort(key=lambda name: (numeric_tokens(release_token(name)), name))
        selected = same_series[-1]
        selected_release = release_token(selected)
        mode = "newest-same-series"

if not selected:
    versioned = [name for name in filtered if numeric_tokens(release_token(name))]
    if versioned:
        versioned.sort(key=lambda name: (numeric_tokens(release_token(name)), name))
        selected = versioned[-1]
        selected_release = release_token(selected)
        mode = "newest"
    elif filtered:
        filtered.sort()
        selected = filtered[-1]
        selected_release = release_token(selected)
        mode = "last"

if not selected:
    print(json.dumps({"selected": "", "mode": mode, "release": "", "candidates": len(candidates), "filtered": len(filtered)}, sort_keys=True))
    sys.exit(1)

print(json.dumps({"selected": selected, "mode": mode, "release": selected_release, "candidates": len(candidates), "filtered": len(filtered)}, sort_keys=True))
PY
}

chroot_manifest_archive_selection_field() {
  local selection_json="$1"
  local field="$2"
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$selection_json" "$field" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
print(payload.get(sys.argv[2], ""))
PY
}

chroot_manifest_remote_size_bytes() {
  local url="$1"
  local timeout="${2:-15}"
  local header_file err_file headers size host port ip

  header_file="$CHROOT_TMP_DIR/manifest-headers.$$.txt"
  err_file="$CHROOT_TMP_DIR/manifest-headers.$$.log"
  rm -f -- "$header_file" "$err_file"

  if "$CHROOT_CURL_BIN" --fail --location --connect-timeout "$timeout" --max-time "$timeout" --speed-time "$timeout" --speed-limit 1 --silent --show-error --head "$url" -D "$header_file" -o /dev/null 2>"$err_file"; then
    :
  elif grep -qi 'Could not resolve host' "$err_file"; then
    host="$(chroot_url_extract_host "$url")"
    port="$(chroot_url_extract_port "$url")"
    ip="$(chroot_resolve_host_ipv4 "$host")"
    if [[ -n "$host" && -n "$ip" ]]; then
      "$CHROOT_CURL_BIN" --fail --location --connect-timeout "$timeout" --max-time "$timeout" --speed-time "$timeout" --speed-limit 1 --silent --show-error --resolve "$host:$port:$ip" --head "$url" -D "$header_file" -o /dev/null 2>>"$err_file" || true
    fi
  fi

  size="$(awk '{ line=tolower($0); if (line ~ /^content-length:/) { gsub(/\r/, "", $2); size=$2 } } END{print size}' "$header_file" 2>/dev/null || true)"
  if [[ ! "$size" =~ ^[0-9]+$ ]] || (( size <= 0 )); then
    : >"$header_file"
    : >"$err_file"
    if "$CHROOT_CURL_BIN" --fail --location --connect-timeout "$timeout" --max-time "$timeout" --speed-time "$timeout" --speed-limit 1 --silent --show-error --range 0-0 "$url" -D "$header_file" -o /dev/null 2>"$err_file"; then
      :
    elif grep -qi 'Could not resolve host' "$err_file"; then
      host="$(chroot_url_extract_host "$url")"
      port="$(chroot_url_extract_port "$url")"
      ip="$(chroot_resolve_host_ipv4 "$host")"
      if [[ -n "$host" && -n "$ip" ]]; then
        "$CHROOT_CURL_BIN" --fail --location --connect-timeout "$timeout" --max-time "$timeout" --speed-time "$timeout" --speed-limit 1 --silent --show-error --resolve "$host:$port:$ip" --range 0-0 "$url" -D "$header_file" -o /dev/null 2>>"$err_file" || true
      fi
    fi

    size="$(grep -i '^content-range:' "$header_file" 2>/dev/null | tail -n1 | sed -nE 's#^.*/([0-9]+)\r?$#\1#p' | tail -n1 || true)"
    if [[ ! "$size" =~ ^[0-9]+$ ]] || (( size <= 0 )); then
      size="$(awk '{ line=tolower($0); if (line ~ /^content-length:/) { gsub(/\r/, "", $2); if ($2 ~ /^[0-9]+$/) size=$2 } } END{print size}' "$header_file" 2>/dev/null || true)"
    fi
  fi

  rm -f -- "$header_file" "$err_file"
  if [[ "$size" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$size"
  else
    printf '0\n'
  fi
}

chroot_manifest_select_ubuntu_versions() {
  local versions_text="${1:-}"
  local series_limit="${2:-5}"
  [[ -n "$versions_text" ]] || return 0

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$versions_text" "$series_limit" <<'PY'
import re
import sys

versions_text, limit_text = sys.argv[1:3]
try:
    limit = max(1, int(limit_text))
except Exception:
    limit = 5

versions = [line.strip() for line in versions_text.splitlines() if line.strip()]


def numeric_tokens(text):
    return tuple(int(x) for x in re.findall(r"\d+", str(text or "")))


latest_by_series = {}
for version in versions:
    parts = version.split(".")
    if len(parts) < 2:
        continue
    series = ".".join(parts[:2])
    current = latest_by_series.get(series)
    if current is None or numeric_tokens(version) > numeric_tokens(current):
        latest_by_series[series] = version

selected = sorted(latest_by_series.values(), key=numeric_tokens)[-limit:]
for version in selected:
    print(version)
PY
}

chroot_manifest_github_default_branch() {
  local owner="$1"
  local repo="$2"
  local fallback="${3:-main}"
  local api_url payload branch=""

  [[ -n "$owner" && -n "$repo" ]] || {
    printf '%s\n' "$fallback"
    return 0
  }

  api_url="https://api.github.com/repos/${owner}/${repo}"
  payload="$(chroot_curl_text "$api_url" 20 2>/dev/null || true)"
  if [[ -n "$payload" ]]; then
    chroot_require_python
    branch="$("$CHROOT_PYTHON_BIN" - "$payload" <<'PY'
import json
import sys

payload = sys.argv[1]
try:
    data = json.loads(payload)
except Exception:
    data = {}
branch = str(data.get("default_branch", "") or "").strip()
if branch:
    print(branch)
PY
)" || true
  fi

  if [[ -n "$branch" ]]; then
    printf '%s\n' "$branch"
  else
    printf '%s\n' "$fallback"
  fi
}

chroot_manifest_termux_plugin_branches() {
  local branch
  local default_branch
  local seen=" "

  default_branch="$(chroot_manifest_github_default_branch "termux" "proot-distro" "main" 2>/dev/null || true)"
  for branch in "$default_branch" "main" "master"; do
    [[ -n "$branch" ]] || continue
    case "$seen" in
      *" $branch "*) continue ;;
    esac
    seen+="$(printf '%s ' "$branch")"
    printf '%s\n' "$branch"
  done
}

chroot_manifest_termux_plugins_tsv() {
  local branch api_url html_url raw_base payload plugin_rows

  chroot_require_python
  while IFS= read -r branch; do
    [[ -n "$branch" ]] || continue
    api_url="https://api.github.com/repos/termux/proot-distro/contents/distro-plugins?ref=${branch}"
    html_url="https://github.com/termux/proot-distro/tree/${branch}/distro-plugins"
    raw_base="https://raw.githubusercontent.com/termux/proot-distro/${branch}/distro-plugins"

    payload="$(chroot_curl_text "$api_url" 20 2>/dev/null || true)"
    if [[ -n "$payload" ]]; then
      plugin_rows="$("$CHROOT_PYTHON_BIN" - "$payload" <<'PY'
import json
import sys

payload = sys.argv[1]
try:
    rows = json.loads(payload)
except Exception:
    rows = []

for row in rows:
    if not isinstance(row, dict):
        continue
    name = str(row.get("name", "") or "")
    download_url = str(row.get("download_url", "") or "")
    if not name.endswith(".sh"):
        continue
    if not download_url:
        continue
    print("\t".join([name, download_url]))
PY
)" || true
      if [[ -n "$plugin_rows" ]]; then
        printf '%s\n' "$plugin_rows"
        return 0
      fi
    fi

    payload="$(chroot_curl_text "$html_url" 20 2>/dev/null || true)"
    [[ -n "$payload" ]] || continue
    plugin_rows="$("$CHROOT_PYTHON_BIN" - "$payload" "$branch" "$raw_base" <<'PY'
import re
import sys

payload, branch, raw_base = sys.argv[1:4]
pattern = re.compile(r"/termux/proot-distro/blob/" + re.escape(branch) + r"/distro-plugins/([^\"/]+\.sh)")
seen = set()
for match in pattern.finditer(payload):
    name = str(match.group(1) or "").strip()
    if not name or name in seen:
        continue
    seen.add(name)
for name in sorted(seen):
    print("\t".join([name, f"{raw_base}/{name}"]))
PY
)" || true
    if [[ -n "$plugin_rows" ]]; then
      printf '%s\n' "$plugin_rows"
      return 0
    fi
  done < <(chroot_manifest_termux_plugin_branches)
}

chroot_manifest_collect_alpine() {
  local out="$1"
  local host_arch alpine_arch base html files selection file release sha url size_bytes

  host_arch="$(chroot_manifest_host_arch)"
  alpine_arch="$(chroot_manifest_alpine_arch_key "$host_arch" || true)"
  [[ -n "$alpine_arch" ]] || return 0

  base="https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/${alpine_arch}"
  html="$(chroot_curl_text "$base/" 20 || true)"
  [[ -n "$html" ]] || return 0

  files="$(printf '%s\n' "$html" | grep -Eo "alpine-minirootfs-[0-9.]+-${alpine_arch}\\.tar\\.gz" | sort -u || true)"
  [[ -n "$files" ]] || return 0

  selection="$(chroot_manifest_select_archive_candidate "alpine" "" "$alpine_arch" ".tar.gz" "$files" 2>/dev/null || true)"
  file="$(chroot_manifest_archive_selection_field "$selection" selected 2>/dev/null || true)"
  [[ -n "$file" ]] || return 0

  release="$(printf '%s\n' "$file" | sed -E "s/^alpine-minirootfs-([0-9.]+)-${alpine_arch}\\.tar\\.gz$/\\1/")"
  sha="$(chroot_curl_text "$base/$file.sha256" 20 2>/dev/null | awk '{print $1}' | head -n1 || true)"
  [[ -n "$sha" ]] || return 0

  url="$base/$file"
  size_bytes="$(chroot_manifest_remote_size_bytes "$url" 15 2>/dev/null || printf '0')"
  chroot_manifest_append_tsv "$out" "alpine" "Alpine Linux" "$release" "stable" "$release" "$host_arch" "$url" "$sha" "$size_bytes" "tar.gz" "alpine" ""
}

chroot_manifest_collect_ubuntu() {
  local out="$1"
  local host_arch ubuntu_arch base html versions version rel_base sums files selection file sha url channel series_limit size_bytes

  host_arch="$(chroot_manifest_host_arch)"
  ubuntu_arch="$(chroot_manifest_ubuntu_arch_key "$host_arch" || true)"
  [[ -n "$ubuntu_arch" ]] || return 0

  base="https://cdimage.ubuntu.com/ubuntu-base/releases"
  html="$(chroot_curl_text "$base/" 20 || true)"
  [[ -n "$html" ]] || return 0

  versions="$(printf '%s\n' "$html" | grep -Eo '[0-9]{2}\.[0-9]{2}(\.[0-9]+)?/' | tr -d '/' | sort -Vu)"
  [[ -n "$versions" ]] || return 0
  series_limit="${CHROOT_MANIFEST_UBUNTU_SERIES_LIMIT:-$(chroot_manifest_default_version_limit)}"
  versions="$(chroot_manifest_select_ubuntu_versions "$versions" "$series_limit" || true)"
  [[ -n "$versions" ]] || return 0

  while IFS= read -r version; do
    [[ -n "$version" ]] || continue
    rel_base="$base/$version/release"
    sums="$(chroot_curl_text "$rel_base/SHA256SUMS" 20 2>/dev/null || true)"
    [[ -n "$sums" ]] || continue

    files="$(printf '%s\n' "$sums" | awk -v arch_key="$ubuntu_arch" '
      {
        f=$2
        gsub(/\*/, "", f)
        if (f ~ ("^ubuntu-base-.*-base-" arch_key "\\.tar\\.gz$")) {
          print f
        }
      }
    ')"
    selection="$(chroot_manifest_select_archive_candidate "ubuntu" "$version" "$ubuntu_arch" ".tar.gz" "$files" 2>/dev/null || true)"
    file="$(chroot_manifest_archive_selection_field "$selection" selected 2>/dev/null || true)"
    [[ -n "$file" ]] || continue

    sha="$(printf '%s\n' "$sums" | awk -v target="$file" '
      {
        f=$2
        gsub(/\*/, "", f)
        if (f == target) {
          print $1
          exit
        }
      }
    ')"
    [[ -n "$sha" ]] || continue

    url="$rel_base/$file"
    size_bytes="$(chroot_manifest_remote_size_bytes "$url" 15 2>/dev/null || printf '0')"
    channel="interim"
    if [[ "$version" =~ ^[0-9]{2}\.04($|\.) ]]; then
      channel="lts"
    fi

    chroot_manifest_append_tsv "$out" "ubuntu" "Ubuntu Base" "$version" "$channel" "$version" "$host_arch" "$url" "$sha" "$size_bytes" "tar.gz" "ubuntu" ""
  done <<<"$versions"
}

chroot_manifest_collect_kali() {
  local out="$1"
  local host_arch kali_arch base html sums files flavors flavor selection file sha size_bytes

  host_arch="$(chroot_manifest_host_arch)"
  kali_arch="$(chroot_manifest_kali_arch_key "$host_arch" || true)"
  [[ -n "$kali_arch" ]] || return 0

  base="https://kali.download/nethunter-images/current/rootfs"
  html="$(chroot_curl_text "$base/" 20 2>/dev/null || true)"
  sums="$(chroot_curl_text "$base/SHA256SUMS" 20 2>/dev/null || true)"
  [[ -n "$html" && -n "$sums" ]] || return 0

  files="$(printf '%s\n' "$html" | grep -Eo "kali-nethunter-rootfs-[a-z0-9-]+-${kali_arch}\\.tar\\.xz" | sort -u || true)"
  flavors="$(printf '%s\n' "$files" | sed -E "s/^kali-nethunter-rootfs-([a-z0-9-]+)-${kali_arch}\\.tar\\.xz$/\\1/" | sort -u)"
  [[ -n "$flavors" ]] || return 0

  while IFS= read -r flavor; do
    [[ -n "$flavor" ]] || continue
    selection="$(chroot_manifest_select_archive_candidate "kali" "$flavor" "$kali_arch" ".tar.xz" "$files" 2>/dev/null || true)"
    file="$(chroot_manifest_archive_selection_field "$selection" selected 2>/dev/null || true)"
    [[ -n "$file" ]] || continue
    sha="$(printf '%s\n' "$sums" | awk -v target="$file" '{ f=$2; gsub(/\*/, "", f); if (f == target) {print $1; exit} }')"
    [[ -n "$sha" ]] || continue
    size_bytes="$(chroot_manifest_remote_size_bytes "$base/$file" 15 2>/dev/null || printf '0')"

    chroot_manifest_append_tsv \
      "$out" \
      "kali" \
      "Kali Linux" \
      "current" \
      "rolling" \
      "$flavor" \
      "$host_arch" \
      "$base/$file" \
      "$sha" \
      "$size_bytes" \
      "tar.xz" \
      "kali" \
      "Official NetHunter rootfs (${flavor})."
  done <<<"$flavors"
}

chroot_manifest_collect_from_proot_plugin_url() {
  local out="$1"
  local plugin_name="$2"
  local plugin_url="$3"
  local script host_arch parsed distro_id display_name comment url sha release channel compression size_bytes name_release comment_release url_release comment_channel

  host_arch="$(chroot_manifest_host_arch)"
  script="$(chroot_curl_text "$plugin_url" 20 2>/dev/null || true)"
  if [[ -z "$script" ]]; then
    chroot_log_warn distros "plugin fetch failed plugin=$plugin_name url=$plugin_url"
    return 0
  fi

  chroot_require_python
  parsed="$("$CHROOT_PYTHON_BIN" - "$script" "$host_arch" "$plugin_name" <<'PY'
import ast
import os
import re
import sys

script, host_arch, plugin_name = sys.argv[1:4]


def shell_unquote(value):
    value = str(value or "").strip()
    if not value:
        return ""
    if value[0] in "\"'" and value[-1:] == value[0]:
        try:
            return ast.literal_eval(value)
        except Exception:
            return value[1:-1]
    return value


def parse_scalar(name):
    pattern = re.compile(r"(?m)^[ \t]*" + re.escape(name) + r"=(\"(?:\\.|[^\"])*\"|'(?:\\.|[^'])*'|[^ \t\r\n#]+)")
    match = pattern.search(script)
    return shell_unquote(match.group(1)) if match else ""


def clean_array_key(key):
    key = shell_unquote(key)
    return key.strip()


def parse_array_assignments(name):
    pairs = {}
    value_pattern = r"(\"(?:\\.|[^\"])*\"|'(?:\\.|[^'])*'|[^ \t\r\n#)]+)"
    direct = re.compile(r"(?m)^[ \t]*" + re.escape(name) + r"\[([^\]\r\n]+)\]\s*=\s*" + value_pattern)
    for match in direct.finditer(script):
        key = clean_array_key(match.group(1))
        value = shell_unquote(match.group(2))
        if key and value:
            pairs[key] = value

    declare = re.compile(r"(?ms)^[ \t]*(?:declare[ \t]+(?:-[A-Za-z]*[Aa][A-Za-z]*|-A)[ \t]+)?" + re.escape(name) + r"=\((.*?)\)")
    item = re.compile(r"\[([^\]\r\n]+)\]\s*=\s*" + value_pattern)
    for block in declare.findall(script):
        for match in item.finditer(block):
            key = clean_array_key(match.group(1))
            value = shell_unquote(match.group(2))
            if key and value:
                pairs[key] = value
    return pairs


url_pairs = parse_array_assignments("TARBALL_URL")
sha_pairs = parse_array_assignments("TARBALL_SHA256")
name = parse_scalar("DISTRO_NAME") or os.path.splitext(plugin_name)[0]
comment = parse_scalar("DISTRO_COMMENT")
comment_out = comment if comment else "__AURORA_EMPTY__"

keys_by_arch = {
    "aarch64": ["aarch64", "arm64", "arm64-v8a"],
    "arm": ["arm", "armhf", "armv7l", "armeabi-v7a"],
    "x86_64": ["x86_64", "amd64", "x64"],
    "i386": ["i686", "i386", "x86"],
    "riscv64": ["riscv64"],
}

for key in keys_by_arch.get(host_arch, [host_arch]):
    url = url_pairs.get(key, "")
    sha = sha_pairs.get(key, "")
    if url and sha:
        distro_id = os.path.splitext(plugin_name)[0]
        print("\t".join([distro_id, name, comment_out, url, sha]))
        sys.exit(0)
sys.exit(1)
PY
)" || true
  if [[ -z "$parsed" ]]; then
    chroot_log_warn distros "plugin parse skipped plugin=$plugin_name arch=$host_arch url=$plugin_url"
    return 0
  fi

  IFS=$'\t' read -r distro_id display_name comment url sha <<<"$parsed"
  [[ "$comment" == "__AURORA_EMPTY__" ]] && comment=""
  if [[ -z "$distro_id" || -z "$url" || -z "$sha" ]]; then
    chroot_log_warn distros "plugin parse incomplete plugin=$plugin_name arch=$host_arch url=$plugin_url"
    return 0
  fi

  name_release="$(chroot_manifest_guess_release_from_name "$display_name")"
  comment_release="$(chroot_manifest_guess_release_from_comment "$comment")"
  url_release="$(chroot_manifest_guess_release_from_url "$url" "$distro_id")"
  comment_channel="$(chroot_manifest_guess_channel_from_comment "$comment")"

  release=""
  if [[ "$comment_release" =~ [0-9] ]]; then
    release="$comment_release"
  elif [[ -n "$name_release" ]]; then
    release="$name_release"
  elif [[ -n "$url_release" ]]; then
    release="$url_release"
  elif [[ -n "$comment_release" ]]; then
    release="$comment_release"
  fi
  if [[ -z "$release" ]]; then
    if printf '%s\n' "$comment" | grep -Eqi '\brolling\b'; then
      release="rolling"
    elif printf '%s\n' "$comment" | grep -Eqi '\bstable\b'; then
      release="stable"
    else
      release="current"
    fi
  fi

  channel="$(chroot_manifest_guess_channel "$release")"
  if [[ "$release" =~ [0-9] && -n "$comment_channel" && "$comment_channel" != "current" ]]; then
    channel="$comment_channel"
  fi
  compression="$(chroot_manifest_detect_compression "$url")"
  size_bytes="$(chroot_manifest_remote_size_bytes "$url" 15 2>/dev/null || printf '0')"
  chroot_manifest_append_tsv "$out" "$distro_id" "$display_name" "$release" "$channel" "$release" "$host_arch" "$url" "$sha" "$size_bytes" "$compression" "proot-plugin" "$comment"
}

chroot_manifest_collect_termux_plugins() {
  local out="$1"
  local plugin_name plugin_url found=0
  while IFS=$'\t' read -r plugin_name plugin_url; do
    [[ -n "$plugin_name" && -n "$plugin_url" ]] || continue
    found=1
    case "$plugin_name" in
      distro.sh|distro.sh.sample|termux.sh|alpine.sh|ubuntu.sh|kali.sh)
        continue
        ;;
    esac
    chroot_manifest_collect_from_proot_plugin_url "$out" "$plugin_name" "$plugin_url"
  done < <(chroot_manifest_termux_plugins_tsv || true)
  if (( found == 0 )); then
    chroot_log_warn distros "termux plugin list unavailable"
  fi
}

chroot_manifest_tsv_entry_count() {
  local tsv_file="$1"
  awk 'NF{c++} END{print c+0}' "$tsv_file" 2>/dev/null || printf '0'
}

chroot_manifest_record_provider_health() {
  local health_file="${CHROOT_MANIFEST_PROVIDER_HEALTH_FILE:-}"
  local provider="$1"
  local status="$2"
  local entries="${3:-0}"
  local detail="${4:-}"

  [[ -n "$health_file" ]] || return 0
  provider="$(chroot_manifest_clean_field "$provider")"
  status="$(chroot_manifest_clean_field "$status")"
  entries="$(chroot_manifest_clean_field "$entries")"
  detail="$(chroot_manifest_clean_field "$detail")"
  [[ "$entries" =~ ^[0-9]+$ ]] || entries=0
  printf '%s\t%s\t%s\t%s\n' "$provider" "$status" "$entries" "$detail" >>"$health_file"
}

chroot_manifest_collect_provider() {
  local provider="$1"
  local out="$2"
  local before after entries rc=0 status detail
  shift 2

  before="$(chroot_manifest_tsv_entry_count "$out")"
  "$@" "$out" || rc=$?
  after="$(chroot_manifest_tsv_entry_count "$out")"
  entries=$((after - before))
  if (( rc != 0 )); then
    status="error"
    detail="collector exited with status $rc"
  elif (( entries > 0 )); then
    status="ok"
    detail="provider returned live entries"
  else
    status="warn"
    detail="provider returned zero live entries"
  fi
  chroot_manifest_record_provider_health "$provider" "$status" "$entries" "$detail"
  return 0
}

chroot_manifest_generate() {
  local tsv_file="$1"
  chroot_manifest_require_supported_arch

  : >"$tsv_file"
  if [[ -n "${CHROOT_MANIFEST_PROVIDER_HEALTH_FILE:-}" ]]; then
    : >"$CHROOT_MANIFEST_PROVIDER_HEALTH_FILE"
  fi
  chroot_manifest_collect_provider "alpine" "$tsv_file" chroot_manifest_collect_alpine
  chroot_manifest_collect_provider "ubuntu" "$tsv_file" chroot_manifest_collect_ubuntu
  chroot_manifest_collect_provider "kali" "$tsv_file" chroot_manifest_collect_kali
  chroot_manifest_collect_provider "termux-proot-distro" "$tsv_file" chroot_manifest_collect_termux_plugins
}

chroot_manifest_build_json() {
  local tsv_file="$1"
  local out_json="$2"
  local previous_manifest="${3:-$CHROOT_MANIFEST_FILE}"
  local provider_health_file="${4:-}"

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$tsv_file" "$previous_manifest" "$provider_health_file" >"$out_json" <<'PY'
import json
import os
import re
import sys
from datetime import datetime, timezone

tsv_path, previous_path, provider_health_path = sys.argv[1:4]
now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

DEFAULT_POLICY = {
    "family": "linux",
    "kind": "general",
    "tier": "advanced",
    "visibility": "advanced",
    "rank": 500,
    "prefer_channels": ["stable", "lts", "release", "rolling", "interim"],
}

POLICY = {
    "alpine": {"family": "alpine", "kind": "minimal", "tier": "recommended", "visibility": "default", "rank": 10, "prefer_channels": ["stable"]},
    "debian": {"family": "debian", "kind": "general", "tier": "recommended", "visibility": "default", "rank": 20, "prefer_channels": ["stable", "lts", "release"]},
    "ubuntu": {"family": "debian", "kind": "general", "tier": "recommended", "visibility": "default", "rank": 30, "prefer_channels": ["lts", "stable", "release", "interim"]},
    "kali": {"family": "debian", "kind": "security", "tier": "recommended", "visibility": "default", "rank": 40, "prefer_channels": ["rolling", "current"]},
    "archlinux": {"family": "arch", "kind": "rolling", "tier": "recommended", "visibility": "default", "rank": 50, "prefer_channels": ["rolling", "current"]},
    "void": {"family": "independent", "kind": "rolling", "tier": "recommended", "visibility": "default", "rank": 60, "prefer_channels": ["rolling", "current"]},
    "fedora": {"family": "redhat", "kind": "general", "tier": "supported", "visibility": "default", "rank": 70, "prefer_channels": ["release", "stable"]},
    "opensuse": {"family": "suse", "kind": "general", "tier": "supported", "visibility": "default", "rank": 80, "prefer_channels": ["stable", "release"]},
    "artix": {"family": "arch", "kind": "rolling", "tier": "advanced", "visibility": "advanced", "rank": 200, "prefer_channels": ["rolling", "current"]},
    "manjaro": {"family": "arch", "kind": "rolling", "tier": "advanced", "visibility": "advanced", "rank": 210, "prefer_channels": ["rolling", "current"]},
    "chimera": {"family": "independent", "kind": "rolling", "tier": "advanced", "visibility": "advanced", "rank": 220, "prefer_channels": ["rolling", "current"]},
    "deepin": {"family": "debian", "kind": "desktop", "tier": "advanced", "visibility": "advanced", "rank": 230, "prefer_channels": ["stable", "release"]},
    "adelie": {"family": "independent", "kind": "rolling", "tier": "advanced", "visibility": "advanced", "rank": 240, "prefer_channels": ["rolling", "current"]},
    "almalinux": {"family": "redhat", "kind": "enterprise", "tier": "advanced", "visibility": "advanced", "rank": 250, "prefer_channels": ["stable", "release"]},
    "rockylinux": {"family": "redhat", "kind": "enterprise", "tier": "advanced", "visibility": "advanced", "rank": 260, "prefer_channels": ["stable", "release"]},
    "oracle": {"family": "redhat", "kind": "enterprise", "tier": "advanced", "visibility": "advanced", "rank": 270, "prefer_channels": ["stable", "release"]},
    "pardus": {"family": "debian", "kind": "general", "tier": "advanced", "visibility": "advanced", "rank": 280, "prefer_channels": ["stable", "release"]},
    "trisquel": {"family": "debian", "kind": "general", "tier": "advanced", "visibility": "advanced", "rank": 290, "prefer_channels": ["stable", "release"]},
}

CATALOG_NOTES = {
    "adelie": "Adelie is an independent musl-based distro focused on small, POSIX-oriented systems. It is useful for lightweight chroots and non-glibc testing. Packages use apk.",
    "almalinux": "AlmaLinux is a RHEL-compatible enterprise distro. It is useful for server-style workflows, rpm tooling, and Enterprise Linux compatibility testing. Packages use dnf with rpm packages.",
    "alpine": "Alpine is a small musl-based distro built for minimal systems and containers. It is useful for lightweight chroots, quick testing, and small installs. Packages use apk.",
    "archlinux": "Arch Linux is a rolling distro focused on current packages and simple upstream configuration. It is useful when you want a fresh userspace and pacman workflows. Packages use pacman.",
    "artix": "Artix is an Arch-based rolling distro without systemd. It is useful if you want Arch-style packages and pacman/AUR-adjacent workflows, but with a lighter init/service model. Packages use pacman.",
    "chimera": "Chimera is an independent musl/LLVM-based distro with a modern non-GNU userspace. It is useful for lightweight experiments and alternative toolchain workflows. Packages use apk.",
    "debian": "Debian is a stable general-purpose distro with broad software support. It is useful for reliable server, scripting, and compatibility-first chroots. Packages use apt with deb packages.",
    "deepin": "Deepin is a Debian-based desktop-oriented distro. It is useful if you want Deepin-style desktop packages or a Debian userspace aimed at GUI workflows. Packages use apt with deb packages.",
    "fedora": "Fedora is a fast-moving Red Hat family distro with newer system tools and libraries. It is useful for modern rpm/dnf workflows and development testing. Packages use dnf with rpm packages.",
    "kali": "Kali is a Debian-based security and testing distro. It is useful for NetHunter-style workflows; minimal starts small, while nano and full add more tools. Packages use apt with deb packages.",
    "manjaro": "Manjaro is an Arch-based rolling distro with a more curated package flow than Arch. It is useful for Arch-style tooling with a friendlier default ecosystem. Packages use pacman.",
    "opensuse": "openSUSE Leap is a SUSE-family stable distro. It is useful for zypper/rpm workflows, admin tools, and testing SUSE-style userspace. Packages use zypper with rpm packages.",
    "oracle": "Oracle Linux is a RHEL-compatible enterprise distro from Oracle. It is useful for server-style workflows, rpm tooling, and Oracle ecosystem compatibility. Packages use dnf with rpm packages.",
    "pardus": "Pardus is a Debian-based general-purpose distro. It is useful for apt/deb workflows with a Pardus userspace and familiar Debian-style tooling. Packages use apt with deb packages.",
    "rockylinux": "Rocky Linux is a RHEL-compatible enterprise distro. It is useful for server-style workflows, rpm tooling, and Enterprise Linux compatibility testing. Packages use dnf with rpm packages.",
    "trisquel": "Trisquel is an Ubuntu-based distro focused on free-software-only repositories. It is useful for a Debian/Ubuntu-style userspace with stricter software freedom defaults. Packages use apt with deb packages.",
    "ubuntu": "Ubuntu is a Debian-based distro with wide documentation and package availability. It is useful for beginner-friendly apt workflows and LTS-based chroots. Packages use apt with deb packages.",
    "void": "Void is an independent rolling distro with runit-style service conventions. It is useful for lean chroots, simple system tooling, and non-systemd workflows. Packages use xbps.",
}

TIER_ORDER = {"recommended": 4, "supported": 3, "advanced": 2, "degraded": 1}
RELEASE_KIND_ORDER = {"versioned": 5, "current": 4, "rolling": 3, "track": 2, "label": 1}
AUTHORITY_ORDER = {"official": 3, "ecosystem": 2, "cache": 1}
CHANNEL_FALLBACK = {"lts": 90, "stable": 80, "release": 70, "rolling": 60, "interim": 50, "current": 40}


def normalize_space(text):
    return " ".join(str(text or "").split())


def human_bytes(num):
    try:
        value = float(num)
    except Exception:
        return "unknown"
    if value <= 0:
        return "unknown"
    units = ["B", "K", "M", "G", "T", "P"]
    idx = 0
    while value >= 1024.0 and idx < len(units) - 1:
        value /= 1024.0
        idx += 1
    if idx == 0:
        return f"{int(value)}{units[idx]}"
    if value >= 10:
        return f"{value:.0f}{units[idx]}"
    return f"{value:.1f}{units[idx]}"


def parse_rows(path):
    rows = []
    if not os.path.exists(path):
        return rows
    with open(path, "r", encoding="utf-8") as fh:
        for raw in fh:
            raw = raw.rstrip("\n")
            if not raw:
                continue
            parts = raw.split("\t")
            install_target = ""
            if len(parts) == 12:
                distro_id, name, release, channel, install_target, arch, url, sha256, size_bytes, compression, source, comment = parts
            elif len(parts) == 11:
                distro_id, name, release, channel, arch, url, sha256, size_bytes, compression, source, comment = parts
                install_target = release
            else:
                continue
            if not distro_id or not sha256:
                continue
            rows.append(
                {
                    "id": str(distro_id),
                    "name": str(name),
                    "release": str(release),
                    "channel": str(channel),
                    "install_target": str(install_target or release),
                    "arch": str(arch),
                    "rootfs_url": str(url),
                    "sha256": str(sha256),
                    "size_bytes": int(size_bytes) if str(size_bytes).isdigit() else 0,
                    "compression": str(compression),
                    "source": str(source),
                    "provider_comment": normalize_space(comment),
                }
            )
    return rows


def parse_provider_health(path):
    rows = []
    if not path or not os.path.exists(path):
        return rows
    with open(path, "r", encoding="utf-8") as fh:
        for raw in fh:
            raw = raw.rstrip("\n")
            if not raw:
                continue
            parts = raw.split("\t", 3)
            while len(parts) < 4:
                parts.append("")
            provider, status, entries, detail = parts
            try:
                entry_count = int(entries)
            except Exception:
                entry_count = 0
            if not provider:
                continue
            rows.append(
                {
                    "provider": str(provider),
                    "status": str(status or "unknown"),
                    "entries": max(0, entry_count),
                    "detail": normalize_space(detail),
                }
            )
    return rows


def load_previous_rows(path):
    if not path or not os.path.exists(path):
        return []
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        rows = data.get("distros", [])
        if not isinstance(rows, list):
            return []
        return [row for row in rows if isinstance(row, dict)]
    except Exception:
        return []


def policy_for(distro_id):
    policy = dict(DEFAULT_POLICY)
    policy.update(POLICY.get(str(distro_id or ""), {}))
    return policy


def catalog_notes_for(distro_id, comment="", stale=False):
    notes = []
    distro_id = str(distro_id or "")
    base = normalize_space(CATALOG_NOTES.get(distro_id, "Provider-supplied rootfs entry; review its source, tier, and provider notes before installing."))
    if base:
        notes.append(base)
    if stale:
        notes.append("This entry is from stale manifest fallback because a live provider refresh was unavailable.")
    return list(dict.fromkeys(notes))


def infer_release_kind(release, channel):
    rel = str(release or "").strip().lower()
    chan = str(channel or "").strip().lower()
    if rel == "current":
        return "current"
    if rel == "rolling" or chan == "rolling":
        return "rolling"
    if rel in {"stable", "lts", "release"}:
        return "track"
    if any(ch.isdigit() for ch in rel):
        return "versioned"
    if chan in {"stable", "lts", "release", "interim"}:
        return "track"
    return "label"


def source_authority(source, stale=False):
    source = str(source or "")
    if stale:
        return "cache"
    if source in {"alpine", "ubuntu", "kali"}:
        return "official"
    return "ecosystem"


def comment_flags(comment):
    comment = str(comment or "").lower()
    flags = set()
    if "broken on android" in comment:
        flags.add("android_broken")
    if "unstable" in comment:
        flags.add("unstable")
    if "frozen" in comment:
        flags.add("frozen")
    if "only 64bit" in comment or "no support for arm" in comment or "no i686" in comment or "no armv7" in comment:
        flags.add("arch_limited")
    return flags


def channel_rank(policy, channel):
    channel = str(channel or "").lower().strip()
    prefs = [str(x).lower() for x in policy.get("prefer_channels", [])]
    if channel in prefs:
        return len(prefs) - prefs.index(channel) + 100
    return CHANNEL_FALLBACK.get(channel, 10)


def install_target_rank(distro_id, install_target):
    distro_id = str(distro_id or "")
    install_target = str(install_target or "").strip().lower()
    if distro_id == "kali":
        return {"minimal": 30, "nano": 20, "full": 10}.get(install_target, 0)
    return 0


def ubuntu_series(value):
    parts = str(value or "").split(".")
    if len(parts) >= 2 and all(part.isdigit() for part in parts[:2]):
        return ".".join(parts[:2])
    return str(value or "")


def recent_ubuntu_series(rows, limit):
    series_map = {}
    for row in rows:
        series = ubuntu_series(row.get("release", ""))
        if not series:
            continue
        current = series_map.get(series)
        if current is None or numeric_tokens(series) > numeric_tokens(current):
            series_map[series] = series
    ordered = sorted(series_map.values(), key=numeric_tokens)
    if limit > 0:
        ordered = ordered[-limit:]
    return set(ordered)


def cached_merge_allowed(row, live_rows_for_id, previous_rows_for_id):
    distro_id = str(row.get("id", "") or "")
    if distro_id == "kali":
        return install_target_rank(distro_id, row.get("install_target", "")) > 0
    if distro_id == "ubuntu":
        try:
            series_limit = max(1, int(os.environ.get("CHROOT_MANIFEST_UBUNTU_SERIES_LIMIT", os.environ.get("CHROOT_CATALOG_VERSION_LIMIT_DEFAULT", "5")) or "5"))
        except Exception:
            series_limit = 5
        row_series = ubuntu_series(row.get("release", ""))
        if not row_series:
            return False
        if any(ubuntu_series(live.get("release", "")) == row_series for live in live_rows_for_id):
            return False
        return row_series in recent_ubuntu_series(list(live_rows_for_id) + list(previous_rows_for_id), series_limit)
    return False


def numeric_tokens(text):
    return tuple(int(x) for x in re.findall(r"\d+", str(text or "")))


def release_score(entry):
    return (
        entry.get("channel_rank", 0),
        RELEASE_KIND_ORDER.get(entry.get("release_kind", "label"), 0),
        numeric_tokens(entry.get("release", "")),
        int(entry.get("size_bytes", 0) or 0),
        str(entry.get("release", "")).lower(),
    )


def pick_score(entry):
    return (
        0 if entry.get("stale") else 1,
        AUTHORITY_ORDER.get(entry.get("source_authority", "ecosystem"), 0),
        TIER_ORDER.get(entry.get("tier", "advanced"), 0),
        int(entry.get("install_target_rank", 0) or 0),
        release_score(entry),
    )


def decorate(entry, stale=False, availability="live"):
    entry = dict(entry)
    distro_id = str(entry.get("id", "") or "")
    policy = policy_for(distro_id)
    comment = normalize_space(entry.get("provider_comment") or entry.get("comment") or "")
    release = str(entry.get("release", "") or "")
    channel = str(entry.get("channel", "") or "")
    install_target = str(entry.get("install_target", "") or release or "current")
    tier = str(entry.get("tier", "") or policy["tier"])
    visibility = str(entry.get("visibility", "") or policy["visibility"])
    warnings = []
    if comment:
        warnings.append(comment)
    if stale:
        warnings.append("Using cached catalog data because a live provider refresh was unavailable.")
    notes = catalog_notes_for(distro_id, comment, stale)
    flags = comment_flags(comment)
    if "android_broken" in flags:
        tier = "degraded"
        visibility = "advanced"
    elif "unstable" in flags:
        if tier == "recommended":
            tier = "supported"
        elif tier == "supported":
            tier = "advanced"
    elif "frozen" in flags and tier == "recommended":
        tier = "supported"

    if distro_id == "kali":
        if install_target == "nano" and tier == "recommended":
            tier = "supported"
        elif install_target == "full":
            if tier == "recommended":
                tier = "advanced"
            visibility = "advanced"

    entry.update(
        {
            "id": distro_id,
            "name": str(entry.get("name", distro_id) or distro_id),
            "release": release or "current",
            "channel": channel or "release",
            "arch": str(entry.get("arch", "") or ""),
            "rootfs_url": str(entry.get("rootfs_url", "") or ""),
            "sha256": str(entry.get("sha256", "") or ""),
            "size_bytes": int(entry.get("size_bytes", 0) or 0),
            "compression": str(entry.get("compression", "") or ""),
            "source": str(entry.get("source", "") or ""),
            "provider_comment": comment,
            "notes": notes,
            "family": str(entry.get("family", "") or policy["family"]),
            "kind": str(entry.get("kind", "") or policy["kind"]),
            "tier": tier,
            "visibility": visibility,
            "recommended": tier == "recommended",
            "rank": int(entry.get("rank", policy["rank"])),
            "release_kind": str(entry.get("release_kind", "") or infer_release_kind(release, channel)),
            "source_authority": str(entry.get("source_authority", "") or source_authority(entry.get("source", ""), stale=stale)),
            "install_target": install_target,
            "install_target_rank": int(entry.get("install_target_rank", install_target_rank(distro_id, install_target))),
            "stale": bool(entry.get("stale", False) or stale),
            "availability": str(entry.get("availability", "") or availability),
            "warnings": list(dict.fromkeys(warnings)),
            "channel_rank": int(entry.get("channel_rank", channel_rank(policy, channel))),
            "updated_at": str(entry.get("updated_at", "") or now),
        }
    )
    return entry


live_rows = [decorate(row, stale=False, availability="live") for row in parse_rows(tsv_path)]
provider_health = parse_provider_health(provider_health_path)
deduped = {}
for row in live_rows:
    key = (row.get("id"), row.get("arch"), row.get("install_target"))
    current = deduped.get(key)
    if current is None or pick_score(row) > pick_score(current):
        deduped[key] = row

previous_rows = [decorate(row, stale=True, availability="cached") for row in load_previous_rows(previous_path)]
live_by_id = {}
live_identity_keys = set()
for row in deduped.values():
    live_by_id.setdefault(row.get("id"), []).append(row)
    live_identity_keys.add((row.get("id"), row.get("arch"), row.get("rootfs_url"), row.get("sha256")))

previous_by_id = {}
for row in previous_rows:
    previous_by_id.setdefault(row.get("id"), []).append(row)

for row in previous_rows:
    key = (row.get("id"), row.get("arch"), row.get("install_target"))
    current = deduped.get(key)
    if current is not None and pick_score(current) >= pick_score(row):
        continue
    identity_key = (row.get("id"), row.get("arch"), row.get("rootfs_url"), row.get("sha256"))
    if identity_key in live_identity_keys:
        continue

    live_rows_for_id = live_by_id.get(row.get("id"), [])
    if not live_rows_for_id or cached_merge_allowed(row, live_rows_for_id, previous_by_id.get(row.get("id"), [])):
        deduped[key] = row

rows = sorted(
    deduped.values(),
    key=lambda row: (
        row.get("id", ""),
        row.get("arch", ""),
        row.get("rank", 999),
        row.get("install_target", ""),
    ),
)

doc = {
    "schema_version": 2,
    "generated_at": now,
    "provider_health": provider_health,
    "provider_warnings": [row for row in provider_health if row.get("status") != "ok"],
    "distros": rows,
}
print(json.dumps(doc, indent=2, sort_keys=True))
PY
}

chroot_manifest_write_meta() {
  local tmp_meta="$1"
  local manifest_json="$2"

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$manifest_json" >"$tmp_meta" <<'PY'
import json
import sys

manifest_path = sys.argv[1]
with open(manifest_path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
rows = data.get("distros", [])
if not isinstance(rows, list):
    rows = []
providers = data.get("provider_health", [])
if not isinstance(providers, list):
    providers = []
provider_warnings = [row for row in providers if isinstance(row, dict) and row.get("status") != "ok"]
distros = sorted({str(row.get("id", "") or "") for row in rows if isinstance(row, dict) and str(row.get("id", "") or "")})
out = {
    "generated_at": str(data.get("generated_at", "")),
    "entries": len(rows),
    "distros": len(distros),
    "stale_entries": sum(1 for row in rows if isinstance(row, dict) and row.get("stale")),
    "providers": len(providers),
    "provider_warnings": len(provider_warnings),
    "provider_health": providers,
    "schema_version": int(data.get("schema_version", 1) or 1),
}
print(json.dumps(out, indent=2, sort_keys=True))
PY
}

chroot_manifest_validate_file() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$f" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
assert isinstance(data, dict)
assert isinstance(data.get("distros"), list)
for row in data.get("distros", []):
    assert isinstance(row, dict)
    assert str(row.get("id", "")).strip()
    assert str(row.get("arch", "")).strip()
    assert str(row.get("rootfs_url", "")).strip()
    assert str(row.get("sha256", "")).strip()
print("ok")
PY
}

chroot_manifest_refresh() {
  chroot_preflight_hard_fail

  local lock_name="global"
  chroot_lock_acquire "$lock_name" || chroot_die "failed to acquire global lock"

  local tsv_tmp json_tmp meta_tmp health_tmp entries provider_warning_count previous_ok=0
  tsv_tmp="$CHROOT_TMP_DIR/manifest.$$.tsv"
  json_tmp="$CHROOT_TMP_DIR/index.$$.json"
  meta_tmp="$CHROOT_TMP_DIR/index.$$.meta.json"
  health_tmp="$CHROOT_TMP_DIR/manifest.$$.providers.tsv"

  if [[ -f "$CHROOT_MANIFEST_FILE" ]]; then
    if chroot_manifest_validate_file "$CHROOT_MANIFEST_FILE" >/dev/null 2>&1; then
      previous_ok=1
    fi
  fi

  chroot_log_info distros "starting manifest refresh"
  if ! CHROOT_MANIFEST_PROVIDER_HEALTH_FILE="$health_tmp" chroot_manifest_generate "$tsv_tmp"; then
    rm -f -- "$tsv_tmp" "$json_tmp" "$meta_tmp" "$health_tmp"
    chroot_lock_release "$lock_name"
    if (( previous_ok == 1 )); then
      chroot_warn "Manifest refresh failed; keeping last-known-good catalog."
      chroot_log_warn distros "manifest refresh failed; reused last-known-good catalog"
      return 0
    fi
    chroot_die "failed generating manifest"
  fi

  entries="$(chroot_manifest_tsv_entry_count "$tsv_tmp")"
  if (( entries == 0 && previous_ok == 0 )); then
    rm -f -- "$tsv_tmp" "$json_tmp" "$meta_tmp" "$health_tmp"
    chroot_lock_release "$lock_name"
    chroot_die "manifest fetch produced zero entries"
  fi

  chroot_manifest_backfill_missing_sizes_tsv "$tsv_tmp"

  chroot_manifest_build_json "$tsv_tmp" "$json_tmp" "$CHROOT_MANIFEST_FILE" "$health_tmp"
  chroot_manifest_validate_file "$json_tmp" >/dev/null
  chroot_manifest_write_meta "$meta_tmp" "$json_tmp"
  provider_warning_count="$(awk -F '\t' '$2 != "ok"{c++} END{print c+0}' "$health_tmp" 2>/dev/null || printf '0')"

  mv -f -- "$json_tmp" "$CHROOT_MANIFEST_FILE"
  mv -f -- "$meta_tmp" "$CHROOT_MANIFEST_META_FILE"
  rm -f -- "$tsv_tmp" "$health_tmp"

  chroot_lock_release "$lock_name"
  chroot_log_info distros "manifest refreshed entries=$entries"
  if [[ "$provider_warning_count" =~ ^[0-9]+$ ]] && (( provider_warning_count > 0 )); then
    chroot_warn "Manifest refreshed with provider warnings; stale fallback may be used where live sources were unavailable."
    chroot_log_warn distros "manifest refreshed with provider warnings count=$provider_warning_count"
  fi
}

chroot_manifest_ensure_present() {
  if [[ ! -f "$CHROOT_MANIFEST_FILE" ]]; then
    chroot_log_run_internal_command core distros.refresh "" distros --refresh -- chroot_manifest_refresh
  fi
}

chroot_manifest_select_entry_from_file_json() {
  local manifest_file="$1"
  local distro="$2"
  local version="${3:-}"
  local host_arch="$4"

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$manifest_file" "$distro" "$version" "$host_arch" <<'PY'
import json
import re
import sys

manifest_path, distro, version, host_arch = sys.argv[1:5]

with open(manifest_path, "r", encoding="utf-8") as fh:
    data = json.load(fh)

all_for_distro = [d for d in data.get("distros", []) if str(d.get("id", "")) == distro]
if not all_for_distro:
    sys.exit(1)

entries = [d for d in all_for_distro if str(d.get("arch", "")) == host_arch]
if not entries:
    sys.exit(2)

if version:
    entries = [
        d
        for d in entries
        if str(d.get("install_target", d.get("release", ""))) == version or str(d.get("release", "")) == version
    ]

if not entries:
    sys.exit(1)

TIER_ORDER = {"recommended": 4, "supported": 3, "advanced": 2, "degraded": 1}
RELEASE_KIND_ORDER = {"versioned": 5, "current": 4, "rolling": 3, "track": 2, "label": 1}
AUTHORITY_ORDER = {"official": 3, "ecosystem": 2, "cache": 1}


def numeric_tokens(text):
    return tuple(int(x) for x in re.findall(r"\d+", str(text or "")))


def human_bytes(num):
    try:
        value = float(num)
    except Exception:
        return "unknown"
    if value <= 0:
        return "unknown"
    units = ["B", "K", "M", "G", "T", "P"]
    idx = 0
    while value >= 1024.0 and idx < len(units) - 1:
        value /= 1024.0
        idx += 1
    if idx == 0:
        return f"{int(value)}{units[idx]}"
    if value >= 10:
        return f"{value:.0f}{units[idx]}"
    return f"{value:.1f}{units[idx]}"


def score(entry):
    return (
        0 if entry.get("stale") else 1,
        AUTHORITY_ORDER.get(str(entry.get("source_authority", "ecosystem")), 0),
        TIER_ORDER.get(str(entry.get("tier", "advanced")), 0),
        int(entry.get("install_target_rank", 0) or 0),
        int(entry.get("channel_rank", 0) or 0),
        RELEASE_KIND_ORDER.get(str(entry.get("release_kind", "label")), 0),
        numeric_tokens(entry.get("release", "")),
        str(entry.get("release", "")).lower(),
    )


entries.sort(key=score)
print(json.dumps(entries[-1]))
PY
}

chroot_manifest_select_entry_json() {
  local distro="$1"
  local version="${2:-}"
  local host_arch
  host_arch="$(chroot_manifest_host_arch)"
  [[ "$host_arch" != "unknown" ]] || chroot_die "unsupported host architecture: $(uname -m 2>/dev/null || echo unknown)"

  chroot_manifest_ensure_present
  chroot_manifest_select_entry_from_file_json "$CHROOT_MANIFEST_FILE" "$distro" "$version" "$host_arch"
}

chroot_manifest_entry_field() {
  local entry_json="$1"
  local field="$2"
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$entry_json" "$field" <<'PY'
import json
import sys

entry = json.loads(sys.argv[1])
field = sys.argv[2]
val = entry.get(field, "")
if isinstance(val, bool):
    print("true" if val else "false")
else:
    print(val)
PY
}

chroot_manifest_versions_for_distro_detailed_tsv() {
  local distro="$1"
  local limit="${2:-$(chroot_manifest_default_version_limit)}"
  local host_arch
  host_arch="$(chroot_manifest_host_arch)"
  [[ "$host_arch" != "unknown" ]] || chroot_die "unsupported host architecture: $(uname -m 2>/dev/null || echo unknown)"
  if [[ ! "$limit" =~ ^[0-9]+$ ]] || (( limit <= 0 )); then
    limit="$(chroot_manifest_default_version_limit)"
  fi
  chroot_manifest_ensure_present
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$CHROOT_MANIFEST_FILE" "$distro" "$limit" "$host_arch" "$CHROOT_CACHE_DIR" <<'PY'
import json
import os
import re
import sys

manifest_path, distro, limit_text, host_arch, cache_dir = sys.argv[1:6]
try:
    limit = int(limit_text)
except Exception:
    limit = 5
if limit <= 0:
    limit = 5

with open(manifest_path, "r", encoding="utf-8") as fh:
    data = json.load(fh)

rows = [d for d in data.get("distros", []) if str(d.get("id", "")) == distro and str(d.get("arch", "")) == host_arch]

TIER_ORDER = {"recommended": 4, "supported": 3, "advanced": 2, "degraded": 1}
RELEASE_KIND_ORDER = {"versioned": 5, "current": 4, "rolling": 3, "track": 2, "label": 1}
AUTHORITY_ORDER = {"official": 3, "ecosystem": 2, "cache": 1}


def numeric_tokens(text):
    return tuple(int(x) for x in re.findall(r"\d+", str(text or "")))


def human_bytes(num):
    try:
        value = float(num)
    except Exception:
        return "unknown"
    if value <= 0:
        return "unknown"
    units = ["B", "K", "M", "G", "T", "P"]
    idx = 0
    while value >= 1024.0 and idx < len(units) - 1:
        value /= 1024.0
        idx += 1
    if idx == 0:
        return f"{int(value)}{units[idx]}"
    if value >= 10:
        return f"{value:.0f}{units[idx]}"
    return f"{value:.1f}{units[idx]}"


def archive_suffix_from_url(url):
    path = str(url or "").split("?", 1)[0].split("#", 1)[0]
    base = os.path.basename(path).lower()
    if base.endswith(".tar"):
        return ".tar"
    match = re.search(r"(\.tar\.[a-z0-9]+)$", base)
    if match:
        return match.group(1)
    for suffix in (".tgz", ".tbz", ".tbz2", ".txz", ".tzst", ".tlz", ".tlzma"):
        if base.endswith(suffix):
            return suffix
    return ".tar"


def download_cache_info(row):
    release = str(row.get("release", "") or "")
    install_target = str(row.get("install_target", "") or release)
    cache_key = release
    if install_target and install_target != release:
        cache_key = install_target
    suffix = archive_suffix_from_url(row.get("rootfs_url", ""))
    path = os.path.join(cache_dir, f"{distro}-{cache_key}{suffix}")
    size = 0
    cached = False
    try:
        if os.path.isfile(path):
            cached = True
            size = max(0, int(os.path.getsize(path)))
    except Exception:
        cached = False
        size = 0
    return cached, path, size


def score(entry):
    return (
        0 if entry.get("stale") else 1,
        AUTHORITY_ORDER.get(str(entry.get("source_authority", "ecosystem")), 0),
        TIER_ORDER.get(str(entry.get("tier", "advanced")), 0),
        int(entry.get("install_target_rank", 0) or 0),
        int(entry.get("channel_rank", 0) or 0),
        RELEASE_KIND_ORDER.get(str(entry.get("release_kind", "label")), 0),
        numeric_tokens(entry.get("release", "")),
        str(entry.get("release", "")).lower(),
    )


rows.sort(key=score, reverse=True)
for row in rows[:limit]:
    download_cached, download_cache_path, download_cache_size = download_cache_info(row)
    print(
        "\t".join(
            [
                str(row.get("install_target", row.get("release", ""))),
                str(row.get("release", "")),
                str(row.get("channel", "")),
                str(row.get("arch", "")),
                str(row.get("rootfs_url", "")),
                str(row.get("sha256", "")),
                str(row.get("compression", "")),
                str(row.get("source", "")),
                str(row.get("tier", "")),
                str(row.get("size_bytes", 0) or 0),
                str(human_bytes(row.get("size_bytes", 0))),
                "yes" if row.get("stale") else "no",
                "yes" if download_cached else "no",
                str(download_cache_path),
                str(download_cache_size),
                str(human_bytes(download_cache_size)),
                str(row.get("provider_comment", "")),
            ]
        )
    )
PY
}

chroot_manifest_enrich_catalog_sizes_json() {
  local manifest_in="$1"
  local manifest_out="$2"
  local host_arch="$3"
  local probe_rows map_file idx url size_bytes

  [[ -f "$manifest_in" ]] || return 1
  chroot_require_python

  probe_rows="$("$CHROOT_PYTHON_BIN" - "$manifest_in" "$host_arch" <<'PY'
import json
import sys

manifest_path, host_arch = sys.argv[1:3]
with open(manifest_path, "r", encoding="utf-8") as fh:
    doc = json.load(fh)

for idx, row in enumerate(doc.get("distros", [])):
    if not isinstance(row, dict):
        continue
    if str(row.get("arch", "")) != host_arch:
        continue
    if str(row.get("visibility", "advanced")) == "hidden":
        continue
    try:
        size_bytes = int(row.get("size_bytes", 0) or 0)
    except Exception:
        size_bytes = 0
    if size_bytes > 0:
        continue
    url = str(row.get("rootfs_url", "") or "").strip()
    if not url:
        continue
    print("\t".join([str(idx), url]))
PY
)" || true

  if [[ -z "$probe_rows" ]]; then
    cp -- "$manifest_in" "$manifest_out"
    return 0
  fi

  map_file="$CHROOT_TMP_DIR/manifest-size-map.$$.tsv"
  : >"$map_file"
  while IFS=$'\t' read -r idx url; do
    [[ -n "$idx" && -n "$url" ]] || continue
    size_bytes="$(chroot_manifest_remote_size_bytes "$url" 20 2>/dev/null || printf '0')"
    if [[ "$size_bytes" =~ ^[0-9]+$ ]] && (( size_bytes > 0 )); then
      printf '%s\t%s\n' "$idx" "$size_bytes" >>"$map_file"
    fi
  done <<<"$probe_rows"

  "$CHROOT_PYTHON_BIN" - "$manifest_in" "$map_file" >"$manifest_out" <<'PY'
import json
import sys

manifest_path, map_path = sys.argv[1:3]
with open(manifest_path, "r", encoding="utf-8") as fh:
    doc = json.load(fh)

updates = {}
try:
    with open(map_path, "r", encoding="utf-8") as fh:
        for raw in fh:
            raw = raw.rstrip("\n")
            if not raw:
                continue
            idx_text, size_text = raw.split("\t", 1)
            try:
                idx = int(idx_text)
                size = int(size_text)
            except Exception:
                continue
            if size > 0:
                updates[idx] = size
except FileNotFoundError:
    pass

rows = doc.get("distros", [])
if isinstance(rows, list):
    for idx, size in updates.items():
        if 0 <= idx < len(rows) and isinstance(rows[idx], dict):
            rows[idx]["size_bytes"] = size

print(json.dumps(doc, indent=2, sort_keys=True))
PY
  rm -f -- "$map_file"
}

chroot_manifest_catalog_json() {
  local max_versions="${1:-$(chroot_manifest_default_version_limit)}"
  local host_arch manifest_input manifest_tmp
  host_arch="$(chroot_manifest_host_arch)"
  [[ "$host_arch" != "unknown" ]] || chroot_die "unsupported host architecture: $(uname -m 2>/dev/null || echo unknown)"
  if [[ ! "$max_versions" =~ ^[0-9]+$ ]] || (( max_versions <= 0 )); then
    max_versions="$(chroot_manifest_default_version_limit)"
  fi
  chroot_manifest_ensure_present
  chroot_require_python
  manifest_input="$CHROOT_MANIFEST_FILE"
  manifest_tmp="$CHROOT_TMP_DIR/manifest-catalog.$$.json"
  if chroot_manifest_enrich_catalog_sizes_json "$CHROOT_MANIFEST_FILE" "$manifest_tmp" "$host_arch" >/dev/null 2>&1; then
    manifest_input="$manifest_tmp"
  fi
  "$CHROOT_PYTHON_BIN" - "$manifest_input" "$CHROOT_ROOTFS_DIR" "$CHROOT_STATE_DIR" "$CHROOT_RUNTIME_ROOT" "$CHROOT_CACHE_DIR" "$max_versions" "$host_arch" <<'PY'
import json
import os
import re
import sys

manifest_path, rootfs_dir, state_dir, runtime_root, cache_dir, max_versions_text, host_arch = sys.argv[1:8]
try:
    max_versions = int(max_versions_text)
except Exception:
    max_versions = 5
if max_versions <= 0:
    max_versions = 5

with open(manifest_path, "r", encoding="utf-8") as fh:
    doc = json.load(fh)

all_rows = [
    d
    for d in doc.get("distros", [])
    if str(d.get("arch", "")) == host_arch and str(d.get("visibility", "advanced")) != "hidden"
]

TIER_ORDER = {"recommended": 0, "supported": 1, "advanced": 2, "degraded": 3}
RELEASE_KIND_ORDER = {"versioned": 5, "current": 4, "rolling": 3, "track": 2, "label": 1}
AUTHORITY_ORDER = {"official": 3, "ecosystem": 2, "cache": 1}


def numeric_tokens(text):
    return tuple(int(x) for x in re.findall(r"\d+", str(text or "")))


def human_bytes(num):
    try:
        value = float(num)
    except Exception:
        return "unknown"
    if value <= 0:
        return "unknown"
    units = ["B", "K", "M", "G", "T", "P"]
    idx = 0
    while value >= 1024.0 and idx < len(units) - 1:
        value /= 1024.0
        idx += 1
    if idx == 0:
        return f"{int(value)}{units[idx]}"
    if value >= 10:
        return f"{value:.0f}{units[idx]}"
    return f"{value:.1f}{units[idx]}"


def archive_suffix_from_url(url):
    path = str(url or "").split("?", 1)[0].split("#", 1)[0]
    base = os.path.basename(path).lower()
    if base.endswith(".tar"):
        return ".tar"
    match = re.search(r"(\.tar\.[a-z0-9]+)$", base)
    if match:
        return match.group(1)
    for suffix in (".tgz", ".tbz", ".tbz2", ".txz", ".tzst", ".tlz", ".tlzma"):
        if base.endswith(suffix):
            return suffix
    return ".tar"


def download_cache_info(distro_id, row):
    release = str(row.get("release", "") or "")
    install_target = str(row.get("install_target", "") or release)
    cache_key = release
    if install_target and install_target != release:
        cache_key = install_target
    suffix = archive_suffix_from_url(row.get("rootfs_url", ""))
    path = os.path.join(cache_dir, f"{distro_id}-{cache_key}{suffix}")
    size = 0
    cached = False
    try:
        if os.path.isfile(path):
            cached = True
            size = max(0, int(os.path.getsize(path)))
    except Exception:
        cached = False
        size = 0
    return cached, path, size


def preferred_score(entry):
    return (
        0 if entry.get("stale") else 1,
        AUTHORITY_ORDER.get(str(entry.get("source_authority", "ecosystem")), 0),
        int(entry.get("install_target_rank", 0) or 0),
        int(entry.get("channel_rank", 0) or 0),
        RELEASE_KIND_ORDER.get(str(entry.get("release_kind", "label")), 0),
        numeric_tokens(entry.get("release", "")),
        str(entry.get("release", "")).lower(),
    )


def latest_score(entry):
    return (
        RELEASE_KIND_ORDER.get(str(entry.get("release_kind", "label")), 0),
        numeric_tokens(entry.get("release", "")),
        int(entry.get("install_target_rank", 0) or 0),
        int(entry.get("channel_rank", 0) or 0),
        str(entry.get("release", "")).lower(),
    )


groups = {}
for row in all_rows:
    distro_id = str(row.get("id", "")).strip()
    if not distro_id:
        continue
    groups.setdefault(distro_id, []).append(row)

distros = []
for distro_id, rows in groups.items():
    rows.sort(key=preferred_score, reverse=True)
    preferred = rows[0]
    latest = sorted(rows, key=latest_score, reverse=True)[0]
    name = str(preferred.get("name", distro_id) or distro_id)

    installed = os.path.isdir(os.path.join(rootfs_dir, distro_id))
    installed_release = ""
    state_file = os.path.join(state_dir, distro_id, "state.json")
    try:
        with open(state_file, "r", encoding="utf-8") as fh:
            state = json.load(fh)
            installed_release = str(state.get("release", ""))
    except Exception:
        installed_release = ""

    warnings = []
    notes = []
    for row in rows:
        for warning in row.get("warnings", []):
            if warning and warning not in warnings:
                warnings.append(str(warning))
        for note in row.get("notes", []):
            if note and note not in notes:
                notes.append(str(note))

    versions = []
    for row in rows[:max_versions]:
        download_cached, download_cache_path, download_cache_size = download_cache_info(distro_id, row)
        versions.append(
            {
                "install_target": str(row.get("install_target", row.get("release", ""))),
                "release": str(row.get("release", "")),
                "channel": str(row.get("channel", "")),
                "arch": str(row.get("arch", "")),
                "rootfs_url": str(row.get("rootfs_url", "")),
                "sha256": str(row.get("sha256", "")),
                "size_bytes": int(row.get("size_bytes", 0) or 0),
                "size_text": human_bytes(row.get("size_bytes", 0)),
                "compression": str(row.get("compression", "")),
                "source": str(row.get("source", "")),
                "source_authority": str(row.get("source_authority", "")),
                "release_kind": str(row.get("release_kind", "")),
                "tier": str(row.get("tier", "")),
                "recommended": bool(row.get("recommended")),
                "stale": bool(row.get("stale")),
                "notes": [str(note) for note in row.get("notes", []) if note],
                "download_cached": bool(download_cached),
                "download_cache_path": str(download_cache_path),
                "download_cache_size_bytes": int(download_cache_size),
                "download_cache_size_text": human_bytes(download_cache_size),
                "provider_comment": str(row.get("provider_comment", "")),
            }
        )

    distros.append(
        {
            "id": distro_id,
            "name": name,
            "family": str(preferred.get("family", "")),
            "kind": str(preferred.get("kind", "")),
            "tier": str(preferred.get("tier", "")),
            "visibility": str(preferred.get("visibility", "")),
            "recommended": bool(preferred.get("recommended")),
            "stale": any(bool(row.get("stale")) for row in rows),
            "sort_rank": int(preferred.get("rank", 999) or 999),
            "latest_release": str(latest.get("release", "")),
            "latest_channel": str(latest.get("channel", "")),
            "preferred_release": str(preferred.get("release", "")),
            "preferred_channel": str(preferred.get("channel", "")),
            "preferred_install_target": str(preferred.get("install_target", preferred.get("release", ""))),
            "preferred_size_bytes": int(preferred.get("size_bytes", 0) or 0),
            "preferred_size_text": human_bytes(preferred.get("size_bytes", 0)),
            "installed": bool(installed),
            "installed_release": installed_release,
            "provider_comment": str(preferred.get("provider_comment", "")),
            "notes": notes,
            "warnings": warnings,
            "versions": versions,
        }
    )

distros.sort(key=lambda row: (TIER_ORDER.get(str(row.get("tier", "advanced")), 9), int(row.get("sort_rank", 999) or 999), str(row.get("id", ""))))

out = {
    "generated_at": str(doc.get("generated_at", "")),
    "host_arch": host_arch,
    "entries": len(all_rows),
    "version_limit": max_versions,
    "runtime_root": str(runtime_root),
    "provider_health": doc.get("provider_health", []) if isinstance(doc.get("provider_health", []), list) else [],
    "provider_warnings": doc.get("provider_warnings", []) if isinstance(doc.get("provider_warnings", []), list) else [],
    "distros": distros,
}
print(json.dumps(out, indent=2))
PY
  rm -f -- "$manifest_tmp"
}

chroot_distros_select_index() {
  local max="$1"
  local prompt="$2"
  local allow_refresh="${3:-0}"
  local value
  while true; do
    printf '%s' "$prompt" >&2
    read -r value
    case "$value" in
      q|Q) printf 'quit\n'; return 0 ;;
      b|B) printf 'back\n'; return 0 ;;
      r|R)
        if (( allow_refresh == 1 )); then
          printf 'refresh\n'
          return 0
        fi
        ;;
      '')
        continue
        ;;
      *)
        if [[ "$value" =~ ^[0-9]+$ ]] && (( value >= 1 && value <= max )); then
          printf '%s\n' "$value"
          return 0
        fi
        ;;
    esac
    if (( allow_refresh == 1 )); then
      printf 'Invalid selection. Enter 1-%s, r, b, or q.\n' "$max" >&2
    else
      printf 'Invalid selection. Enter 1-%s, b, or q.\n' "$max" >&2
    fi
  done
}

chroot_cmd_distros() {
  local json_mode=0 refresh_mode=0
  local action_mode="" action_distro="" action_version=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)
        json_mode=1
        ;;
      --refresh)
        refresh_mode=1
        ;;
      --install|--download)
        [[ -z "$action_mode" ]] || chroot_die "--install and --download are mutually exclusive"
        if [[ "$1" == "--install" ]]; then
          action_mode="install"
        else
          action_mode="download"
        fi
        shift
        [[ $# -gt 0 ]] || chroot_die "$action_mode requires distro id"
        action_distro="$1"
        ;;
      --version)
        shift
        [[ $# -gt 0 ]] || chroot_die "--version requires value"
        action_version="$1"
        ;;
      *)
        chroot_die "unknown distros arg: $1"
        ;;
    esac
    shift
  done

  if [[ -n "$action_mode" ]]; then
    (( json_mode == 0 )) || chroot_die "--json cannot be combined with --install or --download"
    [[ -n "$action_distro" && -n "$action_version" ]] || chroot_die "usage: bash path/to/chroot distros --install <id> --version <target> [--refresh] | distros --download <id> --version <target> [--refresh]"
    chroot_require_distro_arg "$action_distro"

    if (( refresh_mode == 1 )); then
      chroot_manifest_refresh
    else
      chroot_manifest_ensure_present
    fi

    local install_entry
    local select_rc=0
    install_entry="$(chroot_manifest_select_entry_json "$action_distro" "$action_version")" || select_rc=$?
    if (( select_rc != 0 )); then
      case "$select_rc" in
        2) chroot_die "distro '$action_distro' has no release for host arch $(chroot_manifest_host_arch)" ;;
        *) chroot_die "distro/version not found in manifest" ;;
      esac
    fi
    if [[ "$action_mode" == "install" ]]; then
      chroot_install_manifest_entry_json "$install_entry"
    else
      chroot_download_manifest_entry_json "$install_entry"
    fi
    return 0
  fi

  [[ -n "$action_version" ]] && chroot_die "--version can only be used with --install or --download"

  if (( json_mode == 1 )); then
    if (( refresh_mode == 1 )); then
      chroot_manifest_refresh
    else
      chroot_manifest_ensure_present
    fi
    chroot_manifest_catalog_json "$(chroot_manifest_default_version_limit)"
    return 0
  fi

  [[ -t 0 && -t 1 ]] || chroot_die "distros requires an interactive terminal"

  chroot_preflight_hard_fail

  if (( refresh_mode == 1 )); then
    chroot_info "Refreshing distro catalog..."
    chroot_manifest_refresh
  else
    chroot_info "Loading cached distro catalog..."
    chroot_manifest_ensure_present
  fi

  local catalog_json distros_tsv
  local version_limit
  version_limit="$(chroot_manifest_default_version_limit)"
  catalog_json="$(chroot_manifest_catalog_json "$version_limit")"
  distros_tsv="$("$CHROOT_PYTHON_BIN" - "$catalog_json" <<'PY'
import json
import sys

doc = json.loads(sys.argv[1])
for distro in doc.get("distros", []):
    preferred_release = str(distro.get("preferred_release", ""))
    preferred_target = str(distro.get("preferred_install_target", preferred_release))
    preferred_label = preferred_target if preferred_target and preferred_target != preferred_release else preferred_release
    print("\t".join([str(distro.get("id", "")), str(distro.get("name", "")), preferred_label, str(distro.get("preferred_channel", "")), str(distro.get("tier", "")), "yes" if distro.get("installed") else "no", str(distro.get("installed_release", ""))]))
PY
)"

  local -a distro_rows
  mapfile -t distro_rows <<<"$distros_tsv"
  (( ${#distro_rows[@]} > 0 )) || chroot_die "no distros available in manifest"

  while true; do
    printf '\nAvailable distros:\n'
    local idx=1 row id name preferred channel tier installed installed_release
    for row in "${distro_rows[@]}"; do
      IFS=$'\t' read -r id name preferred channel tier installed installed_release <<<"$row"
      if [[ "$installed" == "yes" && -n "$installed_release" ]]; then
        printf '  %2d) %-10s %-18s default=%-10s channel=%-8s tier=%-10s installed=%s\n' \
          "$idx" "$id" "$name" "$preferred" "$channel" "$tier" "$installed_release"
      else
        printf '  %2d) %-10s %-18s default=%-10s channel=%-8s tier=%-10s installed=%s\n' \
          "$idx" "$id" "$name" "$preferred" "$channel" "$tier" "$installed"
      fi
      idx=$((idx + 1))
    done
    printf '\n'
    printf '  %s\n' "! Want a different distro or version? Download your own tarball, then use the install-local command."

    local pick
    pick="$(chroot_distros_select_index "${#distro_rows[@]}" "Select distro (1-${#distro_rows[@]}, r=refresh, q=quit): " 1)"
    [[ "$pick" != "quit" ]] || return 0
    [[ "$pick" != "back" ]] || continue
    if [[ "$pick" == "refresh" ]]; then
      chroot_info "Refreshing distro catalog..."
      chroot_manifest_refresh
      catalog_json="$(chroot_manifest_catalog_json "$version_limit")"
      distros_tsv="$("$CHROOT_PYTHON_BIN" - "$catalog_json" <<'PY'
import json
import sys

doc = json.loads(sys.argv[1])
for distro in doc.get("distros", []):
    preferred_release = str(distro.get("preferred_release", ""))
    preferred_target = str(distro.get("preferred_install_target", preferred_release))
    preferred_label = preferred_target if preferred_target and preferred_target != preferred_release else preferred_release
    print("\t".join([str(distro.get("id", "")), str(distro.get("name", "")), preferred_label, str(distro.get("preferred_channel", "")), str(distro.get("tier", "")), "yes" if distro.get("installed") else "no", str(distro.get("installed_release", ""))]))
PY
)"
      mapfile -t distro_rows <<<"$distros_tsv"
      (( ${#distro_rows[@]} > 0 )) || chroot_die "no distros available in manifest"
      continue
    fi

    local selected_row selected_distro selected_name
    selected_row="${distro_rows[$((pick - 1))]}"
    IFS=$'\t' read -r selected_distro selected_name _preferred _channel _tier _installed _installed_rel <<<"$selected_row"

    local version_rows_raw
    version_rows_raw="$(chroot_manifest_versions_for_distro_detailed_tsv "$selected_distro" "$version_limit" || true)"
    [[ -n "$version_rows_raw" ]] || {
      printf 'No versions found for %s on host arch %s\n' "$selected_distro" "$(chroot_manifest_host_arch)"
      continue
    }
    local -a version_rows
    mapfile -t version_rows <<<"$version_rows_raw"

    while true; do
      printf '\n%s choices:\n' "$selected_name"
      idx=1
      local vrow target release vchannel _varch _vurl _vsha _vcomp _vsource _vtier _vsize_bytes _vsize_text _vstale _vdownloaded _vdownload_path _vdownload_size_bytes _vdownload_size_text _vcomment label
      for vrow in "${version_rows[@]}"; do
        IFS=$'\t' read -r target release vchannel _varch _vurl _vsha _vcomp _vsource _vtier _vsize_bytes _vsize_text _vstale _vdownloaded _vdownload_path _vdownload_size_bytes _vdownload_size_text _vcomment <<<"$vrow"
        label="$release"
        if [[ -n "$target" && "$target" != "$release" ]]; then
          label="$target"
        fi
        if [[ "$_vstale" == "yes" ]]; then
          printf '  %2d) %-12s channel=%-8s tier=%-10s stale-provider\n' "$idx" "$label" "$vchannel" "$_vtier"
        elif [[ "$_vdownloaded" == "yes" ]]; then
          printf '  %2d) %-12s channel=%-8s tier=%-10s downloaded\n' "$idx" "$label" "$vchannel" "$_vtier"
        else
          printf '  %2d) %-12s channel=%-8s tier=%-10s\n' "$idx" "$label" "$vchannel" "$_vtier"
        fi
        idx=$((idx + 1))
      done

      local vpick
      vpick="$(chroot_distros_select_index "${#version_rows[@]}" "Select version (1-${#version_rows[@]}, b=back, q=quit): ")"
      [[ "$vpick" != "quit" ]] || return 0
      [[ "$vpick" != "back" ]] || break

      local chosen_version_row chosen_target chosen_release chosen_channel chosen_arch chosen_url chosen_sha chosen_comp chosen_source chosen_tier chosen_size_bytes chosen_size_text chosen_stale chosen_downloaded chosen_download_path chosen_download_size_bytes chosen_download_size_text chosen_comment
      chosen_version_row="${version_rows[$((vpick - 1))]}"
      IFS=$'\t' read -r chosen_target chosen_release chosen_channel chosen_arch chosen_url chosen_sha chosen_comp chosen_source chosen_tier chosen_size_bytes chosen_size_text chosen_stale chosen_downloaded chosen_download_path chosen_download_size_bytes chosen_download_size_text chosen_comment <<<"$chosen_version_row"

      local install_entry
      local select_rc=0
      install_entry="$(chroot_manifest_select_entry_json "$selected_distro" "$chosen_target")" || select_rc=$?
      if (( select_rc != 0 )); then
        case "$select_rc" in
          2) chroot_die "distro '$selected_distro' has no release for host arch $(chroot_manifest_host_arch)" ;;
          *) chroot_die "distro/version not found in manifest" ;;
        esac
      fi

      local installed_now="no" installed_rel_now=""
      if [[ -d "$(chroot_distro_rootfs_dir "$selected_distro")" ]]; then
        installed_now="yes"
        installed_rel_now="$(chroot_get_distro_flag "$selected_distro" release 2>/dev/null || true)"
      fi

      printf '\nSelected version details:\n'
      printf '  id:           %s\n' "$selected_distro"
      printf '  name:         %s\n' "$selected_name"
      printf '  target:       %s\n' "$chosen_target"
      printf '  release:      %s\n' "$chosen_release"
      printf '  channel:      %s\n' "$chosen_channel"
      printf '  tier:         %s\n' "$chosen_tier"
      printf '  arch:         %s\n' "$chosen_arch"
      printf '  size:         %s\n' "${chosen_size_text:-unknown}"
      printf '  compression:  %s\n' "$chosen_comp"
      printf '  source:       %s\n' "$chosen_source"
      printf '  stale manifest: %s\n' "$chosen_stale"
      printf '  downloaded:   %s\n' "$chosen_downloaded"
      if [[ "$chosen_downloaded" == "yes" ]]; then
        printf '  download size:%s\n' " ${chosen_download_size_text:-unknown}"
      fi
      printf '  url:          %s\n' "$chosen_url"
      printf '  sha256:       %s\n' "$chosen_sha"
      if [[ -n "$chosen_comment" ]]; then
        printf '  note:         %s\n' "$chosen_comment"
      fi
      if [[ "$installed_now" == "yes" && -n "$installed_rel_now" ]]; then
        printf '  installed:    yes (%s)\n' "$installed_rel_now"
      else
        printf '  installed:    %s\n' "$installed_now"
      fi
      printf '  install_path: %s\n' "$(chroot_distro_rootfs_dir "$selected_distro")"

      while true; do
        local confirm
        printf 'Action? [i=download+install, d=download-only, b=back, q=quit]: '
        read -r confirm
        case "$confirm" in
          i|I|y|Y)
            chroot_install_manifest_entry_json "$install_entry"
            return 0
            ;;
          d|D)
            chroot_download_manifest_entry_json "$install_entry"
            return 0
            ;;
          n|N|b|B|'')
            break
            ;;
          q|Q)
            return 0
            ;;
          *)
            printf 'Enter i, d, b, or q.\n' >&2
            ;;
        esac
      done
    done
  done
}
