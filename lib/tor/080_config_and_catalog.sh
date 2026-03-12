chroot_tor_default_config_json() {
  cat <<'JSON'
{
  "schema_version": 1,
  "bypass_packages": [],
  "exit_countries": [],
  "exit_strict": false
}
JSON
}

chroot_tor_config_ensure_file() {
  local distro="$1"
  local config_file tmp
  config_file="$(chroot_tor_config_file "$distro")"
  [[ -f "$config_file" ]] && return 0
  chroot_tor_ensure_state_layout "$distro"
  tmp="$config_file.$$.tmp"
  chroot_tor_default_config_json >"$tmp"
  mv -f -- "$tmp" "$config_file"
}

chroot_tor_config_show_json() {
  local distro="$1"
  local config_file
  config_file="$(chroot_tor_config_file "$distro")"
  [[ -f "$config_file" ]] || {
    chroot_tor_default_config_json
    return 0
  }
  cat "$config_file"
}

chroot_tor_config_summary_tsv() {
  local distro="$1"
  local config_file
  config_file="$(chroot_tor_config_file "$distro")"
  [[ -f "$config_file" ]] || {
    printf '0\t0\t0\n'
    return 0
  }
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$config_file" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {}

bypass = data.get("bypass_packages", [])
if not isinstance(bypass, list):
    bypass = []
countries = data.get("exit_countries", [])
if not isinstance(countries, list):
    countries = []
strict = "1" if data.get("exit_strict") else "0"
print("\t".join([str(len(bypass)), str(len(countries)), strict]))
PY
}

chroot_tor_bypass_packages_json() {
  local distro="$1"
  [[ -f "$(chroot_tor_config_file "$distro")" ]] || {
    printf '[]\n'
    return 0
  }
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$(chroot_tor_config_file "$distro")" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {}

rows = data.get("bypass_packages", [])
if not isinstance(rows, list):
    rows = []
print(json.dumps(sorted(set(str(x).strip() for x in rows if str(x).strip()))))
PY
}

chroot_tor_bypass_package_add_exact() {
  local distro="$1"
  local package_name="$2"
  [[ -n "$package_name" ]] || chroot_die "package name is required"
  chroot_tor_config_ensure_file "$distro"
  chroot_require_python
  local config_file tmp
  config_file="$(chroot_tor_config_file "$distro")"
  tmp="$config_file.$$.tmp"
  "$CHROOT_PYTHON_BIN" - "$config_file" "$tmp" "$package_name" <<'PY'
import json
import sys

src, dst, package_name = sys.argv[1:4]
with open(src, "r", encoding="utf-8") as fh:
    data = json.load(fh)

rows = data.get("bypass_packages", [])
if not isinstance(rows, list):
    rows = []
rows = sorted(set(str(x).strip() for x in rows if str(x).strip()))
if package_name not in rows:
    rows.append(package_name)
data["bypass_packages"] = sorted(set(rows))

with open(dst, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY
  mv -f -- "$tmp" "$config_file"
}

chroot_tor_bypass_package_remove_exact() {
  local distro="$1"
  local package_name="$2"
  [[ -n "$package_name" ]] || chroot_die "package name is required"
  chroot_tor_config_ensure_file "$distro"
  chroot_require_python
  local config_file tmp
  config_file="$(chroot_tor_config_file "$distro")"
  tmp="$config_file.$$.tmp"
  "$CHROOT_PYTHON_BIN" - "$config_file" "$tmp" "$package_name" <<'PY'
import json
import sys

src, dst, package_name = sys.argv[1:4]
with open(src, "r", encoding="utf-8") as fh:
    data = json.load(fh)

rows = data.get("bypass_packages", [])
if not isinstance(rows, list):
    rows = []
rows = [str(x).strip() for x in rows if str(x).strip() and str(x).strip() != package_name]
data["bypass_packages"] = sorted(set(rows))

with open(dst, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY
  mv -f -- "$tmp" "$config_file"
}

chroot_tor_bypass_show_json() {
  local distro="$1"
  local scope_filter="${2:-all}"
  chroot_tor_apps_list_json "$distro" "$scope_filter" 1
}

chroot_tor_country_catalog_tsv() {
  cat <<'EOF'
AE	United Arab Emirates
AR	Argentina
AT	Austria
AU	Australia
BE	Belgium
BG	Bulgaria
BR	Brazil
BY	Belarus
CA	Canada
CH	Switzerland
CL	Chile
CN	China
CO	Colombia
CZ	Czechia
DE	Germany
DK	Denmark
EE	Estonia
EG	Egypt
ES	Spain
FI	Finland
FR	France
GB	United Kingdom
GE	Georgia
GR	Greece
HK	Hong Kong
HR	Croatia
HU	Hungary
ID	Indonesia
IE	Ireland
IL	Israel
IN	India
IS	Iceland
IT	Italy
JP	Japan
KR	South Korea
KZ	Kazakhstan
LT	Lithuania
LU	Luxembourg
LV	Latvia
MA	Morocco
MD	Moldova
ME	Montenegro
MK	North Macedonia
MX	Mexico
MY	Malaysia
NL	Netherlands
NO	Norway
NZ	New Zealand
PE	Peru
PH	Philippines
PL	Poland
PT	Portugal
RO	Romania
RS	Serbia
RU	Russia
SE	Sweden
SG	Singapore
SI	Slovenia
SK	Slovakia
TH	Thailand
TR	Turkiye
TW	Taiwan
UA	Ukraine
US	United States
VN	Vietnam
ZA	South Africa
EOF
}

chroot_tor_country_catalog_json() {
  chroot_require_python
  local tsv_file
  tsv_file="$CHROOT_TMP_DIR/tor-countries.$$.tsv"
  chroot_tor_country_catalog_tsv >"$tsv_file"
  "$CHROOT_PYTHON_BIN" - "$tsv_file" <<'PY'
import json
import sys

path = sys.argv[1]
rows = []
with open(path, "r", encoding="utf-8") as fh:
    for raw in fh:
        raw = raw.strip()
        if not raw:
            continue
        code, name = raw.split("\t", 1)
        rows.append({"code": code.lower(), "name": name})
print(json.dumps(rows, indent=2, sort_keys=True))
PY
  rm -f -- "$tsv_file"
}

chroot_tor_country_search_json() {
  local query="${1:-}"
  chroot_require_python
  local tsv_file
  tsv_file="$CHROOT_TMP_DIR/tor-countries.$$.tsv"
  chroot_tor_country_catalog_tsv >"$tsv_file"
  "$CHROOT_PYTHON_BIN" - "$tsv_file" "$query" <<'PY'
import json
import sys

path, query = sys.argv[1:3]
query = str(query or "").strip().lower()
rows = []
with open(path, "r", encoding="utf-8") as fh:
    for raw in fh:
        raw = raw.strip()
        if not raw:
            continue
        code, name = raw.split("\t", 1)
        if query and query not in code.lower() and query not in name.lower():
            continue
        rows.append({"code": code.lower(), "name": name})
print(json.dumps(rows, indent=2, sort_keys=True))
PY
  rm -f -- "$tsv_file"
}

chroot_tor_country_select_match() {
  local json_payload="$1"
  local prompt="${2:-Select country}"

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$json_payload" "$prompt" <<'PY'
import json
import sys

rows = json.loads(sys.argv[1])
prompt = sys.argv[2]
if not rows:
    sys.exit(2)

for idx, row in enumerate(rows, start=1):
    print(f"  {idx:2d}) {row.get('code','').upper():<4} {row.get('name','')}", file=sys.stderr)

while True:
    try:
        pick = input(f"{prompt} (1-{len(rows)}, q=cancel): ")
    except EOFError:
        sys.exit(1)
    if pick in {"", "q", "Q"}:
        sys.exit(1)
    if pick.isdigit():
        idx = int(pick)
        if 1 <= idx <= len(rows):
          print(str(rows[idx - 1].get("code", "")))
          sys.exit(0)
    print("Invalid selection.", file=sys.stderr)
PY
}

chroot_tor_country_resolve_query() {
  local query="$1"
  local json_payload count exact code

  [[ -n "$query" ]] || chroot_die "country query is required"

  json_payload="$(chroot_tor_country_search_json "$query")"
  chroot_require_python
  exact="$("$CHROOT_PYTHON_BIN" - "$json_payload" "$query" <<'PY'
import json
import sys

rows = json.loads(sys.argv[1])
query = str(sys.argv[2]).strip().lower()
for row in rows:
    code = str(row.get("code", "")).strip().lower()
    name = str(row.get("name", "")).strip().lower()
    if code == query or name == query:
        print(code)
        sys.exit(0)
sys.exit(1)
PY
  )" || true
  if [[ -n "$exact" ]]; then
    printf '%s\n' "$exact"
    return 0
  fi

  count="$("$CHROOT_PYTHON_BIN" - "$json_payload" <<'PY'
import json
import sys
print(len(json.loads(sys.argv[1])))
PY
)"
  [[ "$count" =~ ^[0-9]+$ ]] || count=0
  if (( count == 1 )); then
    code="$("$CHROOT_PYTHON_BIN" - "$json_payload" <<'PY'
import json
import sys
rows = json.loads(sys.argv[1])
print(str(rows[0].get("code", "")) if rows else "")
PY
)"
    [[ -n "$code" ]] || chroot_die "failed to resolve country query: $query"
    printf '%s\n' "$code"
    return 0
  fi
  if (( count == 0 )); then
    chroot_die "no country matches query: $query"
  fi
  if [[ ! -t 0 ]]; then
    chroot_die "multiple countries match '$query'; use a two-letter country code"
  fi
  chroot_tor_country_select_match "$json_payload" "Select country"
}

chroot_tor_exit_show_json() {
  local distro="$1"
  [[ -f "$(chroot_tor_config_file "$distro")" ]] || {
    printf '{\n  "countries": [],\n  "strict": false\n}\n'
    return 0
  }
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$(chroot_tor_config_file "$distro")" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {}

countries = [str(x).strip().lower() for x in data.get("exit_countries", []) if str(x).strip()]
strict = bool(data.get("exit_strict"))
print(json.dumps({"countries": countries, "strict": strict}, indent=2, sort_keys=True))
PY
}

chroot_tor_exit_add_code_exact() {
  local distro="$1"
  local code="$2"
  code="${code,,}"
  [[ "$code" =~ ^[a-z]{2}$ ]] || chroot_die "exit country code must be a two-letter code"
  chroot_tor_config_ensure_file "$distro"
  chroot_require_python
  local config_file tmp
  config_file="$(chroot_tor_config_file "$distro")"
  tmp="$config_file.$$.tmp"
  "$CHROOT_PYTHON_BIN" - "$config_file" "$tmp" "$code" <<'PY'
import json
import sys

src, dst, code = sys.argv[1:4]
with open(src, "r", encoding="utf-8") as fh:
    data = json.load(fh)

rows = [str(x).strip().lower() for x in data.get("exit_countries", []) if str(x).strip()]
if code not in rows:
    rows.append(code)
data["exit_countries"] = sorted(set(rows))

with open(dst, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY
  mv -f -- "$tmp" "$config_file"
}

chroot_tor_exit_remove_code_exact() {
  local distro="$1"
  local code="$2"
  code="${code,,}"
  [[ "$code" =~ ^[a-z]{2}$ ]] || chroot_die "exit country code must be a two-letter code"
  chroot_tor_config_ensure_file "$distro"
  chroot_require_python
  local config_file tmp
  config_file="$(chroot_tor_config_file "$distro")"
  tmp="$config_file.$$.tmp"
  "$CHROOT_PYTHON_BIN" - "$config_file" "$tmp" "$code" <<'PY'
import json
import sys

src, dst, code = sys.argv[1:4]
with open(src, "r", encoding="utf-8") as fh:
    data = json.load(fh)

rows = [str(x).strip().lower() for x in data.get("exit_countries", []) if str(x).strip().lower() != code]
data["exit_countries"] = sorted(set(rows))

with open(dst, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY
  mv -f -- "$tmp" "$config_file"
}

chroot_tor_exit_clear() {
  local distro="$1"
  chroot_tor_config_ensure_file "$distro"
  chroot_require_python
  local config_file tmp
  config_file="$(chroot_tor_config_file "$distro")"
  tmp="$config_file.$$.tmp"
  "$CHROOT_PYTHON_BIN" - "$config_file" "$tmp" <<'PY'
import json
import sys

src, dst = sys.argv[1:3]
with open(src, "r", encoding="utf-8") as fh:
    data = json.load(fh)
data["exit_countries"] = []
data["exit_strict"] = False
with open(dst, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY
  mv -f -- "$tmp" "$config_file"
}

chroot_tor_exit_set_strict() {
  local distro="$1"
  local value="$2"
  local strict_bool="false"
  local config_json
  case "${value,,}" in
    1|true|yes|on) strict_bool="true" ;;
    0|false|no|off) strict_bool="false" ;;
    *) chroot_die "strict value must be on|off" ;;
  esac
  chroot_tor_config_ensure_file "$distro"
  if [[ "$strict_bool" == "true" ]]; then
    config_json="$(chroot_tor_exit_show_json "$distro")"
    chroot_require_python
    "$CHROOT_PYTHON_BIN" - "$config_json" <<'PY'
import json
import sys

try:
    data = json.loads(sys.argv[1])
except Exception:
    data = {}

countries = data.get("countries", [])
if not isinstance(countries, list):
    countries = []
countries = [str(x).strip().lower() for x in countries if str(x).strip()]
if not countries:
    raise SystemExit("strict mode requires at least one saved exit country")
PY
  fi
  chroot_require_python
  local config_file tmp
  config_file="$(chroot_tor_config_file "$distro")"
  tmp="$config_file.$$.tmp"
  "$CHROOT_PYTHON_BIN" - "$config_file" "$tmp" "$strict_bool" <<'PY'
import json
import sys

src, dst, strict_text = sys.argv[1:4]
with open(src, "r", encoding="utf-8") as fh:
    data = json.load(fh)
data["exit_strict"] = strict_text == "true"
with open(dst, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY
  mv -f -- "$tmp" "$config_file"
}

chroot_tor_exit_resolved_tsv() {
  local distro="$1"
  local config_file tsv_file
  config_file="$(chroot_tor_config_file "$distro")"
  [[ -f "$config_file" ]] || {
    printf '0\t\t\n'
    return 0
  }
  tsv_file="$CHROOT_TMP_DIR/tor-countries.$$.tsv"
  chroot_tor_country_catalog_tsv >"$tsv_file"
  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$config_file" "$tsv_file" <<'PY'
import json
import sys

config_path, tsv_path = sys.argv[1:3]
try:
    with open(config_path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {}

catalog = {}
with open(tsv_path, "r", encoding="utf-8") as fh:
    for raw in fh:
        raw = raw.strip()
        if not raw:
            continue
        code, name = raw.split("\t", 1)
        catalog[code.lower()] = name

codes = [str(x).strip().lower() for x in data.get("exit_countries", []) if str(x).strip()]
strict = "1" if data.get("exit_strict") else "0"
resolved = []
for code in codes:
    resolved.append(f"{code}:{catalog.get(code, code.upper())}")
print("\t".join([strict, ",".join(codes), " | ".join(resolved)]))
PY
  rm -f -- "$tsv_file"
}

chroot_tor_exit_policy_tsv() {
  local distro="$1"
  local strict codes resolved
  local -a code_list=()
  local csv="" code

  IFS=$'\t' read -r strict codes resolved <<<"$(chroot_tor_exit_resolved_tsv "$distro")"
  if [[ -n "$codes" ]]; then
    IFS=',' read -r -a code_list <<<"$codes"
    for code in "${code_list[@]}"; do
      [[ "$code" =~ ^[A-Za-z]{2}$ ]] || continue
      [[ -n "$csv" ]] && csv+=","
      csv+="{${code^^}}"
    done
  fi
  printf '%s\t%s\t%s\n' "${strict:-0}" "${codes:-}" "$csv"
}
