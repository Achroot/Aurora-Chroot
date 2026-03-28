#!/usr/bin/env bash

chroot_manifest_append_tsv() {
  local out="$1"
  local id="$2"
  local name="$3"
  local release="$4"
  local channel="$5"
  local arch="$6"
  local url="$7"
  local sha256="$8"
  local size_bytes="$9"
  local compression="${10}"
  local source="${11}"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$id" "$name" "$release" "$channel" "$arch" "$url" "$sha256" "$size_bytes" "$compression" "$source" >>"$out"
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

chroot_manifest_host_arch() {
  local raw
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
      "sha256": "deadbeef"
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
}

chroot_manifest_trim() {
  local s="${1:-}"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s\n' "$s"
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
    fi
  fi

  chroot_manifest_trim "$rel"
}

chroot_manifest_guess_release_from_url() {
  local url="${1:-}"
  local distro_id="${2:-}"
  local base rel

  base="${url##*/}"
  rel="$(printf '%s\n' "$base" | sed -nE "s/.*${distro_id}-([0-9][0-9A-Za-z._-]*)-[0-9A-Za-z._-]+\.tar\..*/\1/p" | head -n1 || true)"
  if [[ -z "$rel" ]]; then
    rel="$(printf '%s\n' "$base" | sed -nE 's/.*-([0-9]{2}\.[0-9]{2}(\.[0-9]+)?)-.*/\1/p' | head -n1 || true)"
  fi
  chroot_manifest_trim "$rel"
}

chroot_manifest_collect_alpine() {
  local out="$1"
  local host_arch alpine_arch base html file release sha url

  host_arch="$(chroot_manifest_host_arch)"
  alpine_arch="$(chroot_manifest_alpine_arch_key "$host_arch" || true)"
  [[ -n "$alpine_arch" ]] || return 0

  base="https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/${alpine_arch}"
  html="$(chroot_curl_text "$base/" 20 || true)"
  [[ -n "$html" ]] || return 0

  file="$(printf '%s\n' "$html" | grep -Eo "alpine-minirootfs-[0-9.]+-${alpine_arch}\\.tar\\.gz" | sort -Vu | tail -n1 || true)"
  [[ -n "$file" ]] || return 0

  release="$(printf '%s\n' "$file" | sed -E "s/^alpine-minirootfs-([0-9.]+)-${alpine_arch}\\.tar\\.gz$/\\1/")"
  sha="$(chroot_curl_text "$base/$file.sha256" 20 2>/dev/null | awk '{print $1}' | head -n1 || true)"
  [[ -n "$sha" ]] || return 0

  url="$base/$file"
  chroot_manifest_append_tsv "$out" "alpine" "Alpine Linux" "$release" "stable" "$host_arch" "$url" "$sha" "0" "tar.gz" "alpine"
}

chroot_manifest_collect_ubuntu() {
  local out="$1"
  local host_arch ubuntu_arch base html versions version rel_base sums file sha url channel

  host_arch="$(chroot_manifest_host_arch)"
  ubuntu_arch="$(chroot_manifest_ubuntu_arch_key "$host_arch" || true)"
  [[ -n "$ubuntu_arch" ]] || return 0

  base="https://cdimage.ubuntu.com/ubuntu-base/releases"
  html="$(chroot_curl_text "$base/" 20 || true)"
  [[ -n "$html" ]] || return 0

  versions="$(printf '%s\n' "$html" | grep -Eo '[0-9]{2}\.[0-9]{2}(\.[0-9]+)?/' | tr -d '/' | sort -Vu)"
  [[ -n "$versions" ]] || return 0

  while IFS= read -r version; do
    [[ -n "$version" ]] || continue
    rel_base="$base/$version/release"
    sums="$(chroot_curl_text "$rel_base/SHA256SUMS" 20 2>/dev/null || true)"
    [[ -n "$sums" ]] || continue

    file="$(printf '%s\n' "$sums" | awk -v arch_key="$ubuntu_arch" '
      {
        f=$2
        gsub(/\*/, "", f)
        if (f ~ ("^ubuntu-base-.*-base-" arch_key "\\.tar\\.gz$")) {
          print f
          exit
        }
      }
    ')"
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

    channel="interim"
    if [[ "$version" =~ ^[0-9]{2}\.04($|\.) ]]; then
      channel="lts"
    fi

    chroot_manifest_append_tsv "$out" "ubuntu" "Ubuntu Base" "$version" "$channel" "$host_arch" "$url" "$sha" "0" "tar.gz" "ubuntu"
  done <<<"$versions"
}

chroot_manifest_collect_from_proot_plugin() {
  local out="$1"
  local distro_id="$2"
  local display_name="$3"
  local plugin="$4"
  local fallback_release="$5"
  local fallback_channel="$6"

  local plugin_url script url sha release channel compression name_from_script host_arch
  local arch_probe
  host_arch="$(chroot_manifest_host_arch)"
  plugin_url="https://raw.githubusercontent.com/termux/proot-distro/master/distro-plugins/$plugin"
  script="$(chroot_curl_text "$plugin_url" 20 || true)"
  [[ -n "$script" ]] || return 0

  name_from_script="$(printf '%s\n' "$script" | sed -nE "s/^[[:space:]]*DISTRO_NAME=['\"]([^'\"]+)['\"].*/\1/p" | head -n1 || true)"
  chroot_require_python
  arch_probe="$("$CHROOT_PYTHON_BIN" - "$script" "$host_arch" <<'PY'
import re
import sys

script, host_arch = sys.argv[1:3]
url_pairs = dict(re.findall(r"TARBALL_URL\[['\"]([^'\"]+)['\"]\]\s*=\s*['\"]([^'\"]+)['\"]", script))
sha_pairs = dict(re.findall(r"TARBALL_SHA256\[['\"]([^'\"]+)['\"]\]\s*=\s*['\"]([^'\"]+)['\"]", script))

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
        print(f"{key}\t{url}\t{sha}")
        sys.exit(0)
sys.exit(1)
PY
)" || true
  if [[ -n "$arch_probe" ]]; then
    IFS=$'\t' read -r _arch_key url sha <<<"$arch_probe"
  fi

  [[ -n "$url" && -n "$sha" ]] || return 0

  if [[ -n "$name_from_script" ]]; then
    display_name="$name_from_script"
  fi

  release="$fallback_release"
  if [[ -z "$release" ]]; then
    release="$(chroot_manifest_guess_release_from_name "$display_name")"
  fi
  if [[ -z "$release" ]]; then
    release="$(chroot_manifest_guess_release_from_url "$url" "$distro_id")"
  fi
  if [[ -z "$release" ]]; then
    release="rolling"
  fi

  channel="$fallback_channel"
  if [[ -z "$channel" ]]; then
    channel="$(chroot_manifest_guess_channel "$release")"
  fi

  compression="$(chroot_manifest_detect_compression "$url")"

  chroot_manifest_append_tsv "$out" "$distro_id" "$display_name" "$release" "$channel" "$host_arch" "$url" "$sha" "0" "$compression" "proot-plugin"
}

chroot_manifest_collect_proot_plugins() {
  local out="$1"
  local row distro_id name release channel plugin
  local -a rows=(
    "archlinux|Arch Linux|rolling|rolling|archlinux.sh"
    "debian|Debian|stable|stable|debian.sh"
    "artix|Artix Linux|rolling|rolling|artix.sh"
    "fedora|Fedora|release|release|fedora.sh"
    "manjaro|Manjaro|rolling|rolling|manjaro.sh"
    "opensuse|openSUSE|release|release|opensuse.sh"
    "void|Void Linux|rolling|rolling|void.sh"
    "adelie|Adelie Linux|rolling|rolling|adelie.sh"
    "almalinux|AlmaLinux|stable|stable|almalinux.sh"
    "chimera|Chimera Linux|rolling|rolling|chimera.sh"
    "deepin|Deepin|stable|stable|deepin.sh"
    "oracle|Oracle Linux|stable|stable|oracle.sh"
    "pardus|Pardus|stable|stable|pardus.sh"
    "rockylinux|Rocky Linux|stable|stable|rockylinux.sh"
    "trisquel|Trisquel|stable|stable|trisquel.sh"
  )

  for row in "${rows[@]}"; do
    IFS='|' read -r distro_id name release channel plugin <<<"$row"
    chroot_manifest_collect_from_proot_plugin "$out" "$distro_id" "$name" "$plugin" "$release" "$channel"
  done
}

chroot_manifest_generate() {
  local tsv_file="$1"
  chroot_manifest_require_supported_arch

  : >"$tsv_file"
  chroot_manifest_collect_alpine "$tsv_file"
  chroot_manifest_collect_ubuntu "$tsv_file"
  chroot_manifest_collect_proot_plugins "$tsv_file"
}

chroot_manifest_build_json() {
  local tsv_file="$1"
  local out_json="$2"

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$tsv_file" >"$out_json" <<'PY'
import json
import sys
from datetime import datetime, timezone

path = sys.argv[1]
distros = []
with open(path, 'r', encoding='utf-8') as fh:
    for raw in fh:
        raw = raw.rstrip('\n')
        if not raw:
            continue
        parts = raw.split('\t')
        if len(parts) != 10:
            continue
        distro_id, name, release, channel, arch, url, sha256, size_bytes, compression, source = parts
        if not sha256:
            continue
        distros.append({
            "id": distro_id,
            "name": name,
            "release": release,
            "channel": channel,
            "arch": arch,
            "rootfs_url": url,
            "sha256": sha256,
            "size_bytes": int(size_bytes) if size_bytes.isdigit() else 0,
            "compression": compression,
            "source": source,
            "updated_at": datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z'),
        })

doc = {
    "schema_version": 1,
    "generated_at": datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z'),
    "distros": distros,
}
print(json.dumps(doc, indent=2, sort_keys=True))
PY
}

chroot_manifest_write_meta() {
  local tmp_meta="$1"
  local entry_count="$2"

  cat >"$tmp_meta" <<EOF_META
{
  "generated_at": "$(chroot_now_ts)",
  "entries": $entry_count,
  "schema_version": 1
}
EOF_META
}

chroot_manifest_validate_file() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$f" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as fh:
    data = json.load(fh)
assert isinstance(data, dict)
assert isinstance(data.get('distros'), list)
print('ok')
PY
}

chroot_manifest_refresh() {
  chroot_preflight_hard_fail

  local lock_name="global"
  chroot_lock_acquire "$lock_name" || chroot_die "failed to acquire global lock"

  local tsv_tmp json_tmp meta_tmp entries
  tsv_tmp="$CHROOT_TMP_DIR/manifest.$$.tsv"
  json_tmp="$CHROOT_TMP_DIR/index.$$.json"
  meta_tmp="$CHROOT_TMP_DIR/index.$$.meta.json"

  chroot_log_info distros "starting manifest refresh"
  if ! chroot_manifest_generate "$tsv_tmp"; then
    chroot_lock_release "$lock_name"
    chroot_die "failed generating manifest"
  fi

  entries="$(awk 'NF{c++} END{print c+0}' "$tsv_tmp" 2>/dev/null || printf '0')"
  if (( entries == 0 )); then
    rm -f -- "$tsv_tmp" "$json_tmp" "$meta_tmp"
    chroot_lock_release "$lock_name"
    chroot_die "manifest fetch produced zero entries"
  fi

  chroot_manifest_build_json "$tsv_tmp" "$json_tmp"
  chroot_manifest_validate_file "$json_tmp" >/dev/null

  chroot_manifest_write_meta "$meta_tmp" "$entries"

  mv -f -- "$json_tmp" "$CHROOT_MANIFEST_FILE"
  mv -f -- "$meta_tmp" "$CHROOT_MANIFEST_META_FILE"
  rm -f -- "$tsv_tmp"

  chroot_lock_release "$lock_name"
  chroot_log_info distros "manifest refreshed entries=$entries"
}

chroot_manifest_ensure_present() {
  if [[ ! -f "$CHROOT_MANIFEST_FILE" ]]; then
    chroot_manifest_refresh
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

with open(manifest_path, 'r', encoding='utf-8') as fh:
    data = json.load(fh)

all_for_distro = [d for d in data.get('distros', []) if d.get('id') == distro]
if not all_for_distro:
    sys.exit(1)

entries = [d for d in all_for_distro if d.get('arch') == host_arch]
if not entries:
    sys.exit(2)

if version:
    entries = [d for d in entries if d.get('release') == version]

if not entries:
    sys.exit(1)

def vkey(v):
    rel = str(v.get('release', ''))
    nums = []
    for tok in re.split(r'[^0-9]+', rel):
        if tok:
            nums.append(int(tok))
    return (nums, rel.lower())

entries.sort(key=vkey)
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
val = entry.get(field, '')
if isinstance(val, bool):
    print('true' if val else 'false')
else:
    print(val)
PY
}

chroot_manifest_versions_for_distro_detailed_tsv() {
  local distro="$1"
  local limit="${2:-5}"
  local host_arch
  host_arch="$(chroot_manifest_host_arch)"
  [[ "$host_arch" != "unknown" ]] || chroot_die "unsupported host architecture: $(uname -m 2>/dev/null || echo unknown)"
  if [[ ! "$limit" =~ ^[0-9]+$ ]] || (( limit <= 0 )); then
    limit=5
  fi
  chroot_manifest_ensure_present
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$CHROOT_MANIFEST_FILE" "$distro" "$limit" "$host_arch" <<'PY'
import json
import re
import sys

manifest_path, distro, limit_text, host_arch = sys.argv[1:5]
try:
    limit = int(limit_text)
except Exception:
    limit = 5
if limit <= 0:
    limit = 5

with open(manifest_path, 'r', encoding='utf-8') as fh:
    data = json.load(fh)

rows = [d for d in data.get('distros', []) if d.get('id') == distro and d.get('arch') == host_arch]

def vkey(v):
    rel = str(v.get('release', ''))
    nums = [int(x) for x in re.findall(r'\d+', rel)]
    return (nums, rel.lower())

rows.sort(key=vkey, reverse=True)
for row in rows[:limit]:
    print("\t".join([
        str(row.get('release', '')),
        str(row.get('channel', '')),
        str(row.get('arch', '')),
        str(row.get('rootfs_url', '')),
        str(row.get('sha256', '')),
        str(row.get('compression', '')),
        str(row.get('source', '')),
    ]))
PY
}

chroot_manifest_catalog_json() {
  local max_versions="${1:-5}"
  local host_arch
  host_arch="$(chroot_manifest_host_arch)"
  [[ "$host_arch" != "unknown" ]] || chroot_die "unsupported host architecture: $(uname -m 2>/dev/null || echo unknown)"
  if [[ ! "$max_versions" =~ ^[0-9]+$ ]] || (( max_versions <= 0 )); then
    max_versions=5
  fi
  chroot_manifest_ensure_present
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$CHROOT_MANIFEST_FILE" "$CHROOT_ROOTFS_DIR" "$CHROOT_STATE_DIR" "$CHROOT_RUNTIME_ROOT" "$max_versions" "$host_arch" <<'PY'
import json
import os
import re
import sys

manifest_path, rootfs_dir, state_dir, runtime_root, max_versions_text, host_arch = sys.argv[1:7]
try:
    max_versions = int(max_versions_text)
except Exception:
    max_versions = 5
if max_versions <= 0:
    max_versions = 5

with open(manifest_path, 'r', encoding='utf-8') as fh:
    doc = json.load(fh)

all_rows = [d for d in doc.get('distros', []) if d.get('arch') == host_arch]

def vkey(v):
    rel = str(v.get('release', ''))
    nums = [int(x) for x in re.findall(r'\d+', rel)]
    return (nums, rel.lower())

groups = {}
for row in all_rows:
    did = str(row.get('id', '')).strip()
    if not did:
        continue
    groups.setdefault(did, []).append(row)

distros = []
for did in sorted(groups.keys()):
    rows = groups[did]
    rows.sort(key=vkey, reverse=True)
    latest = rows[0]
    name = str(latest.get('name', did))

    installed = os.path.isdir(os.path.join(rootfs_dir, did))
    installed_release = ""
    state_file = os.path.join(state_dir, did, 'state.json')
    try:
        with open(state_file, 'r', encoding='utf-8') as fh:
            state = json.load(fh)
            installed_release = str(state.get('release', ''))
    except Exception:
        installed_release = ""

    versions = []
    for row in rows[:max_versions]:
        versions.append(
            {
                "release": str(row.get('release', '')),
                "channel": str(row.get('channel', '')),
                "arch": str(row.get('arch', '')),
                "rootfs_url": str(row.get('rootfs_url', '')),
                "sha256": str(row.get('sha256', '')),
                "compression": str(row.get('compression', '')),
                "source": str(row.get('source', '')),
            }
        )

    distros.append(
        {
            "id": did,
            "name": name,
            "latest_release": str(latest.get('release', '')),
            "latest_channel": str(latest.get('channel', '')),
            "installed": bool(installed),
            "installed_release": installed_release,
            "versions": versions,
        }
    )

out = {
    "generated_at": str(doc.get("generated_at", "")),
    "host_arch": host_arch,
    "entries": len(all_rows),
    "runtime_root": str(runtime_root),
    "distros": distros,
}
print(json.dumps(out, indent=2))
PY
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
  local json_mode=0 refresh_mode=0 install_mode=0
  local install_distro="" install_version=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)
        json_mode=1
        ;;
      --refresh)
        refresh_mode=1
        ;;
      --install)
        install_mode=1
        shift
        [[ $# -gt 0 ]] || chroot_die "--install requires distro id"
        install_distro="$1"
        ;;
      --version)
        shift
        [[ $# -gt 0 ]] || chroot_die "--version requires value"
        install_version="$1"
        ;;
      *)
        chroot_die "unknown distros arg: $1"
        ;;
    esac
    shift
  done

  if (( install_mode == 1 )); then
    (( json_mode == 0 )) || chroot_die "--json cannot be combined with --install"
    [[ -n "$install_distro" && -n "$install_version" ]] || chroot_die "usage: bash path/to/chroot distros --install <id> --version <release> [--refresh]"
    chroot_require_distro_arg "$install_distro"

    if (( refresh_mode == 1 )); then
      chroot_manifest_refresh
    else
      chroot_manifest_ensure_present
    fi

    local install_entry
    local select_rc=0
    install_entry="$(chroot_manifest_select_entry_json "$install_distro" "$install_version")" || select_rc=$?
    if (( select_rc != 0 )); then
      case "$select_rc" in
        2) chroot_die "distro '$install_distro' has no release for host arch $(chroot_manifest_host_arch)" ;;
        *) chroot_die "distro/version not found in manifest" ;;
      esac
    fi
    chroot_install_manifest_entry_json "$install_entry"
    return 0
  fi

  [[ -n "$install_version" ]] && chroot_die "--version can only be used with --install"

  if (( json_mode == 1 )); then
    if (( refresh_mode == 1 )); then
      chroot_manifest_refresh
    else
      chroot_manifest_ensure_present
    fi
    chroot_manifest_catalog_json 5
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
  catalog_json="$(chroot_manifest_catalog_json 5)"
  distros_tsv="$("$CHROOT_PYTHON_BIN" - "$catalog_json" <<'PY'
import json
import sys
doc = json.loads(sys.argv[1])
for d in doc.get("distros", []):
    print("\t".join([
        str(d.get("id", "")),
        str(d.get("name", "")),
        str(d.get("latest_release", "")),
        str(d.get("latest_channel", "")),
        "yes" if d.get("installed") else "no",
        str(d.get("installed_release", "")),
    ]))
PY
)"

  local -a distro_rows
  mapfile -t distro_rows <<<"$distros_tsv"
  (( ${#distro_rows[@]} > 0 )) || chroot_die "no distros available in manifest"

  while true; do
    printf '\nAvailable distros:\n'
    local idx=1 row id name latest channel installed installed_release
    for row in "${distro_rows[@]}"; do
      IFS=$'\t' read -r id name latest channel installed installed_release <<<"$row"
      if [[ "$installed" == "yes" && -n "$installed_release" ]]; then
        printf '  %2d) %-10s %-18s latest=%-10s channel=%-8s installed=%s\n' "$idx" "$id" "$name" "$latest" "$channel" "$installed_release"
      else
        printf '  %2d) %-10s %-18s latest=%-10s channel=%-8s installed=%s\n' "$idx" "$id" "$name" "$latest" "$channel" "$installed"
      fi
      idx=$((idx + 1))
    done

    local pick
    pick="$(chroot_distros_select_index "${#distro_rows[@]}" "Select distro (1-${#distro_rows[@]}, r=refresh, q=quit): " 1)"
    [[ "$pick" != "quit" ]] || return 0
    [[ "$pick" != "back" ]] || continue
    if [[ "$pick" == "refresh" ]]; then
      chroot_info "Refreshing distro catalog..."
      chroot_manifest_refresh
      catalog_json="$(chroot_manifest_catalog_json 5)"
      distros_tsv="$("$CHROOT_PYTHON_BIN" - "$catalog_json" <<'PY'
import json
import sys
doc = json.loads(sys.argv[1])
for d in doc.get("distros", []):
    print("\t".join([
        str(d.get("id", "")),
        str(d.get("name", "")),
        str(d.get("latest_release", "")),
        str(d.get("latest_channel", "")),
        "yes" if d.get("installed") else "no",
        str(d.get("installed_release", "")),
    ]))
PY
)"
      mapfile -t distro_rows <<<"$distros_tsv"
      (( ${#distro_rows[@]} > 0 )) || chroot_die "no distros available in manifest"
      continue
    fi

    local selected_row selected_distro selected_name
    selected_row="${distro_rows[$((pick - 1))]}"
    IFS=$'\t' read -r selected_distro selected_name _latest _channel _installed _installed_rel <<<"$selected_row"

    local version_rows_raw
    version_rows_raw="$(chroot_manifest_versions_for_distro_detailed_tsv "$selected_distro" 5 || true)"
    [[ -n "$version_rows_raw" ]] || {
      printf 'No versions found for %s on host arch %s\n' "$selected_distro" "$(chroot_manifest_host_arch)"
      continue
    }
    local -a version_rows
    mapfile -t version_rows <<<"$version_rows_raw"

    while true; do
      printf '\n%s versions:\n' "$selected_name"
      idx=1
      local vrow release vchannel _varch _vurl _vsha _vcomp _vsource
      for vrow in "${version_rows[@]}"; do
        IFS=$'\t' read -r release vchannel _varch _vurl _vsha _vcomp _vsource <<<"$vrow"
        printf '  %2d) %-12s channel=%s\n' "$idx" "$release" "$vchannel"
        idx=$((idx + 1))
      done

      local vpick
      vpick="$(chroot_distros_select_index "${#version_rows[@]}" "Select version (1-${#version_rows[@]}, b=back, q=quit): ")"
      [[ "$vpick" != "quit" ]] || return 0
      [[ "$vpick" != "back" ]] || break

      local chosen_version_row chosen_release chosen_channel chosen_arch chosen_url chosen_sha chosen_comp chosen_source
      chosen_version_row="${version_rows[$((vpick - 1))]}"
      IFS=$'\t' read -r chosen_release chosen_channel chosen_arch chosen_url chosen_sha chosen_comp chosen_source <<<"$chosen_version_row"

      local install_entry
      local select_rc=0
      install_entry="$(chroot_manifest_select_entry_json "$selected_distro" "$chosen_release")" || select_rc=$?
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
      printf '  id:          %s\n' "$selected_distro"
      printf '  name:        %s\n' "$selected_name"
      printf '  release:     %s\n' "$chosen_release"
      printf '  channel:     %s\n' "$chosen_channel"
      printf '  arch:        %s\n' "$chosen_arch"
      printf '  compression: %s\n' "$chosen_comp"
      printf '  source:      %s\n' "$chosen_source"
      printf '  url:         %s\n' "$chosen_url"
      printf '  sha256:      %s\n' "$chosen_sha"
      if [[ "$installed_now" == "yes" && -n "$installed_rel_now" ]]; then
        printf '  installed:   yes (%s)\n' "$installed_rel_now"
      else
        printf '  installed:   %s\n' "$installed_now"
      fi
      printf '  install_path: %s\n' "$(chroot_distro_rootfs_dir "$selected_distro")"

      while true; do
        local confirm
        printf 'Install this version now? [y/N/b/q]: '
        read -r confirm
        case "$confirm" in
          y|Y)
            chroot_install_manifest_entry_json "$install_entry"
            return 0
            ;;
          n|N|'')
            break
            ;;
          b|B)
            break
            ;;
          q|Q)
            return 0
            ;;
          *)
            printf 'Enter y, n, b, or q.\n' >&2
            ;;
        esac
      done
    done
  done
}
