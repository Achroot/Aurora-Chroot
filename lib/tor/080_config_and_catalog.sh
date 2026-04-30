chroot_tor_default_config_json() {
  cat <<'JSON'
{
  "schema_version": 3,
  "bypass_packages": [],
  "exit_countries": [],
  "exit_strict": false,
  "exit_performance": false,
  "exit_performance_ignored_countries": []
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
    printf '0\t0\t0\t0\t0\n'
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
ignored = data.get("exit_performance_ignored_countries", [])
if not isinstance(ignored, list):
    ignored = []
strict = "1" if data.get("exit_strict") else "0"
performance = "1" if data.get("exit_performance") else "0"
print("\t".join([str(len(bypass)), str(len(countries)), strict, performance, str(len(ignored))]))
PY
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

chroot_tor_exit_cache_refresh() {
  local distro="$1"
  local out_file
  chroot_tor_ensure_state_layout "$distro"
  chroot_tor_config_ensure_file "$distro"
  chroot_require_python
  out_file="$CHROOT_TMP_DIR/tor-exit.$$.json"
  "$CHROOT_PYTHON_BIN" - "$(chroot_tor_config_file "$distro")" "$out_file" "$(chroot_now_ts)" <<'PY'
import json
import sys

config_path, out_path, generated_at = sys.argv[1:4]

catalog = [
    ("ae", "United Arab Emirates"),
    ("ar", "Argentina"),
    ("at", "Austria"),
    ("au", "Australia"),
    ("be", "Belgium"),
    ("bg", "Bulgaria"),
    ("br", "Brazil"),
    ("by", "Belarus"),
    ("ca", "Canada"),
    ("ch", "Switzerland"),
    ("cl", "Chile"),
    ("cn", "China"),
    ("co", "Colombia"),
    ("cz", "Czechia"),
    ("de", "Germany"),
    ("dk", "Denmark"),
    ("ee", "Estonia"),
    ("eg", "Egypt"),
    ("es", "Spain"),
    ("fi", "Finland"),
    ("fr", "France"),
    ("gb", "United Kingdom"),
    ("ge", "Georgia"),
    ("gr", "Greece"),
    ("hk", "Hong Kong"),
    ("hr", "Croatia"),
    ("hu", "Hungary"),
    ("id", "Indonesia"),
    ("ie", "Ireland"),
    ("il", "Israel"),
    ("in", "India"),
    ("is", "Iceland"),
    ("it", "Italy"),
    ("jp", "Japan"),
    ("kr", "South Korea"),
    ("kz", "Kazakhstan"),
    ("lt", "Lithuania"),
    ("lu", "Luxembourg"),
    ("lv", "Latvia"),
    ("ma", "Morocco"),
    ("md", "Moldova"),
    ("me", "Montenegro"),
    ("mk", "North Macedonia"),
    ("mx", "Mexico"),
    ("my", "Malaysia"),
    ("nl", "Netherlands"),
    ("no", "Norway"),
    ("nz", "New Zealand"),
    ("pe", "Peru"),
    ("ph", "Philippines"),
    ("pl", "Poland"),
    ("pt", "Portugal"),
    ("ro", "Romania"),
    ("rs", "Serbia"),
    ("ru", "Russia"),
    ("se", "Sweden"),
    ("sg", "Singapore"),
    ("si", "Slovenia"),
    ("sk", "Slovakia"),
    ("th", "Thailand"),
    ("tr", "Turkiye"),
    ("tw", "Taiwan"),
    ("ua", "Ukraine"),
    ("us", "United States"),
    ("vn", "Vietnam"),
    ("za", "South Africa"),
]

try:
    with open(config_path, "r", encoding="utf-8") as fh:
        config = json.load(fh)
        if not isinstance(config, dict):
            config = {}
except Exception:
    config = {}

selected = set(str(x).strip().lower() for x in config.get("exit_countries", []) if str(x).strip())
ignored = set(str(x).strip().lower() for x in config.get("exit_performance_ignored_countries", []) if str(x).strip())
strict = bool(config.get("exit_strict"))
performance = bool(config.get("exit_performance"))

rows = []
for code, name in catalog:
    rows.append(
        {
            "code": code,
            "name": name,
            "display_name": f"{name} ({code.upper()})",
            "performance_ignored": code in ignored,
            "selected": code in selected,
        }
    )

rows.sort(key=lambda row: (0 if row.get("selected") else 1, str(row.get("name") or "").lower()))

payload = {
    "schema_version": 4,
    "generated_at": generated_at,
    "strict": strict,
    "performance": performance,
    "country_count": len(rows),
    "performance_ignored_country_count": len([row for row in rows if row.get("performance_ignored")]),
    "selected_country_count": len([row for row in rows if row.get("selected")]),
    "countries": rows,
}

with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY
  mv -f -- "$out_file" "$(chroot_tor_exit_inventory_file "$distro")"
  chroot_log_info tor "exit-cache-refresh distro=$distro"
}

chroot_tor_exit_cache_ensure() {
  local distro="$1"
  local cache_file
  cache_file="$(chroot_tor_exit_inventory_file "$distro")"
  if [[ ! -f "$cache_file" ]]; then
    chroot_log_run_internal_command tor tor.exit.refresh "$distro" "$distro" tor exit refresh --json -- chroot_tor_exit_cache_refresh "$distro"
  fi
}

chroot_tor_exit_list_json() {
  local distro="$1"
  local selected_only="${2:-0}"
  local query="${3:-}"
  local refresh_flag="${4:-0}"

  if [[ "$refresh_flag" == "1" ]]; then
    chroot_tor_exit_cache_refresh "$distro"
  else
    chroot_tor_exit_cache_ensure "$distro"
  fi

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$(chroot_tor_exit_inventory_file "$distro")" "$selected_only" "$query" <<'PY'
import json
import sys

path, selected_only_text, query = sys.argv[1:4]
selected_only = selected_only_text == "1"
query = str(query or "").strip().lower()
try:
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
        if not isinstance(data, dict):
            data = {}
except Exception:
    data = {}

rows = []
for row in data.get("countries", []):
    if not isinstance(row, dict):
        continue
    selected = bool(row.get("selected"))
    if selected_only and not selected:
        continue
    code = str(row.get("code", "")).strip().lower()
    name = str(row.get("name", "")).strip()
    display_name = str(row.get("display_name", "")).strip() or f"{name} ({code.upper()})"
    haystack = " ".join(part for part in [code, name.lower(), display_name.lower()] if part)
    if query and query not in haystack:
        continue
    item = dict(row)
    item["display_name"] = display_name
    rows.append(item)

rows.sort(key=lambda row: (0 if row.get("selected") else 1, str(row.get("name") or "").lower()))
payload = dict(data)
payload["country_count"] = len(rows)
payload["performance_ignored_country_count"] = len([row for row in rows if row.get("performance_ignored")])
payload["selected_country_count"] = len([row for row in rows if row.get("selected")])
payload["selected_filter"] = selected_only
payload["query"] = query
payload["countries"] = rows
print(json.dumps(payload, indent=2, sort_keys=True))
PY
}

chroot_tor_exit_performance_ignore_list_json() {
  local distro="$1"
  local refresh_flag="${2:-0}"
  local query="${3:-}"

  if [[ "$refresh_flag" == "1" ]]; then
    chroot_tor_exit_cache_refresh "$distro"
  else
    chroot_tor_exit_cache_ensure "$distro"
  fi

  chroot_require_python
  "$CHROOT_PYTHON_BIN" - "$(chroot_tor_exit_inventory_file "$distro")" "$query" <<'PY'
import json
import sys

path, query = sys.argv[1:3]
query = str(query or "").strip().lower()
try:
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
        if not isinstance(data, dict):
            data = {}
except Exception:
    data = {}

rows = []
for row in data.get("countries", []):
    if not isinstance(row, dict):
        continue
    code = str(row.get("code", "")).strip().lower()
    name = str(row.get("name", "")).strip()
    display_name = str(row.get("display_name", "")).strip() or f"{name} ({code.upper()})"
    haystack = " ".join(part for part in [code, name.lower(), display_name.lower()] if part)
    if query and query not in haystack:
        continue
    item = dict(row)
    item["display_name"] = display_name
    rows.append(item)

rows.sort(key=lambda row: (0 if row.get("performance_ignored") else 1, str(row.get("name") or "").lower()))
payload = dict(data)
payload["country_count"] = len(rows)
payload["performance_ignored_country_count"] = len([row for row in rows if row.get("performance_ignored")])
payload["query"] = query
payload["countries"] = rows
print(json.dumps(payload, indent=2, sort_keys=True))
PY
}

chroot_tor_exit_list_human() {
  chroot_require_python
  "$CHROOT_PYTHON_BIN" -c '
import json
import sys

try:
    data = json.load(sys.stdin)
except Exception:
    data = {}
rows = data.get("countries", []) if isinstance(data, dict) else []
strict = bool(data.get("strict")) if isinstance(data, dict) else False
performance = bool(data.get("performance")) if isinstance(data, dict) else False
ignored_count = int(data.get("performance_ignored_country_count", 0) or 0) if isinstance(data, dict) else 0
if performance:
    print("[x] = saved for non-performance runs only; configured performance runs use live Tor relay data")
elif strict:
    print("[x] = must use these exits because strict mode is on")
else:
    print("[x] = preferred when available because strict mode is off")
if ignored_count > 0:
    suffix = "country" if ignored_count == 1 else "countries"
    print(f"Performance Ignore saved: {ignored_count} {suffix}. Use `tor exit performance-ignore list` to inspect them.")
printed = 0
for row in rows if isinstance(rows, list) else []:
    if not isinstance(row, dict):
        continue
    marker = "[x]" if row.get("selected") else "[ ]"
    value = str(row.get("display_name") or row.get("name") or row.get("code") or "")
    print("{} {}".format(marker, value))
    printed += 1
if printed == 0:
    print("No countries matched.")
  '
}

chroot_tor_exit_performance_ignore_list_human() {
  chroot_require_python
  "$CHROOT_PYTHON_BIN" -c '
import json
import sys

try:
    data = json.load(sys.stdin)
except Exception:
    data = {}
rows = data.get("countries", []) if isinstance(data, dict) else []
print("[x] = ignored during live performance sampling | [ ] = allowed")
printed = 0
for row in rows if isinstance(rows, list) else []:
    if not isinstance(row, dict):
        continue
    marker = "[x]" if row.get("performance_ignored") else "[ ]"
    value = str(row.get("display_name") or row.get("name") or row.get("code") or "")
    print("{} {}".format(marker, value))
    printed += 1
if printed == 0:
    print("No countries matched.")
'
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
  local json_payload resolution_json code match_count suggestions_text matches_json

  [[ -n "$query" ]] || chroot_die "country query is required"

  json_payload="$(chroot_tor_country_catalog_json)"
  chroot_require_python
  resolution_json="$("$CHROOT_PYTHON_BIN" - "$json_payload" "$query" <<'PY'
import difflib
import json
import sys

rows = json.loads(sys.argv[1])
query_raw = str(sys.argv[2] or "").strip()
query = query_raw.lower()

def normalize(text):
    return "".join(ch.lower() for ch in str(text or "") if ch.isalnum())

query_norm = normalize(query_raw)
catalog = []
for row in rows if isinstance(rows, list) else []:
    if not isinstance(row, dict):
        continue
    code = str(row.get("code", "") or "").strip().lower()
    name = str(row.get("name", "") or "").strip()
    if not code:
        continue
    catalog.append(
        {
            "code": code,
            "name": name,
            "code_l": code.lower(),
            "name_l": name.lower(),
            "code_n": normalize(code),
            "name_n": normalize(name),
        }
    )

def dedupe(items):
    seen = set()
    out = []
    for item in items:
        code = str(item.get("code", "") or "")
        if not code or code in seen:
            continue
        seen.add(code)
        out.append({"code": code, "name": str(item.get("name", "") or "")})
    return out

exact_code = []
exact_name = []
exact_normalized = []
partial = []

for item in catalog:
    if item["code_l"] == query:
        exact_code.append(item)
        continue
    if item["name_l"] == query:
        exact_name.append(item)
        continue
    if query_norm and query_norm in {item["code_n"], item["name_n"]}:
        exact_normalized.append(item)
        continue
    if (query and (query in item["code_l"] or query in item["name_l"])) or (
        query_norm and (query_norm in item["code_n"] or query_norm in item["name_n"])
    ):
        partial.append(item)

exact_code = dedupe(exact_code)
exact_name = dedupe(exact_name)
exact_normalized = dedupe(exact_normalized)
partial = dedupe(partial)

resolved_code = ""
match_rows = []
if len(exact_code) == 1:
    resolved_code = str(exact_code[0].get("code", "") or "")
elif len(exact_name) == 1:
    resolved_code = str(exact_name[0].get("code", "") or "")
elif len(exact_normalized) == 1:
    resolved_code = str(exact_normalized[0].get("code", "") or "")
elif len(partial) == 1:
    resolved_code = str(partial[0].get("code", "") or "")
else:
    merged = []
    for group in [exact_code, exact_name, exact_normalized, partial]:
        merged.extend(group)
    match_rows = dedupe(merged)

scored = {}
for item in catalog:
    best = 0.0
    raw_fields = [item["code_l"], item["name_l"]]
    norm_fields = [item["code_n"], item["name_n"]]
    if query and any(field == query for field in raw_fields if field):
        best = max(best, 1.0)
    if query and any(field.startswith(query) for field in raw_fields if field):
        best = max(best, 0.93)
    if query and any(query in field for field in raw_fields if field):
        best = max(best, 0.88)
    if query_norm:
        if any(field == query_norm for field in norm_fields if field):
            best = max(best, 0.98)
        if any(field.startswith(query_norm) for field in norm_fields if field):
            best = max(best, 0.95)
        if any(query_norm in field for field in norm_fields if field):
            best = max(best, 0.90)
        for field in norm_fields:
            if not field:
                continue
            best = max(best, difflib.SequenceMatcher(None, query_norm, field).ratio())
    if best < 0.55:
        continue
    code = str(item.get("code", "") or "")
    current = scored.get(code)
    if current is None or best > current["score"]:
        scored[code] = {
            "score": best,
            "code": code,
            "name": str(item.get("name", "") or ""),
        }

suggestions = [
    {"code": item["code"], "name": item["name"]}
    for item in sorted(
        scored.values(),
        key=lambda row: (-float(row.get("score", 0.0) or 0.0), str(row.get("name", "")).lower(), str(row.get("code", "")).lower()),
    )[:3]
]

print(
    json.dumps(
        {
            "resolved_code": resolved_code,
            "match_count": len(match_rows),
            "matches": match_rows,
            "suggestions": suggestions,
        },
        indent=2,
        sort_keys=True,
    )
)
PY
  )" || true

  code="$("$CHROOT_PYTHON_BIN" - "$resolution_json" <<'PY'
import json
import sys
try:
    data = json.loads(sys.argv[1])
except Exception:
    data = {}
print(str(data.get("resolved_code", "") or ""))
PY
)"
  if [[ -n "$code" ]]; then
    printf '%s\n' "$code"
    return 0
  fi

  match_count="$("$CHROOT_PYTHON_BIN" - "$resolution_json" <<'PY'
import json
import sys
try:
    data = json.loads(sys.argv[1])
except Exception:
    data = {}
print(int(data.get("match_count", 0) or 0))
PY
)"
  [[ "$match_count" =~ ^[0-9]+$ ]] || match_count=0

  suggestions_text="$("$CHROOT_PYTHON_BIN" - "$resolution_json" <<'PY'
import json
import sys
try:
    data = json.loads(sys.argv[1])
except Exception:
    data = {}
items = []
for row in data.get("suggestions", []):
    if not isinstance(row, dict):
        continue
    code = str(row.get("code", "") or "").strip().upper()
    name = str(row.get("name", "") or "").strip()
    if code and name:
        items.append(f"{name} ({code})")
    elif name:
        items.append(name)
    elif code:
        items.append(code)
print(", ".join(items))
PY
)"

  if (( match_count == 0 )); then
    if [[ -n "$suggestions_text" ]]; then
      chroot_die "no country matches query: $query; did you mean: $suggestions_text"
    fi
    chroot_die "no country matches query: $query"
  fi
  if [[ ! -t 0 ]]; then
    if [[ -n "$suggestions_text" ]]; then
      chroot_die "multiple countries match '$query'; be more specific. did you mean: $suggestions_text"
    fi
    chroot_die "multiple countries match '$query'; use a two-letter country code"
  fi

  matches_json="$("$CHROOT_PYTHON_BIN" - "$resolution_json" <<'PY'
import json
import sys
try:
    data = json.loads(sys.argv[1])
except Exception:
    data = {}
print(json.dumps(data.get("matches", []), indent=2, sort_keys=True))
PY
)"
  chroot_tor_country_select_match "$matches_json" "Select country"
}

chroot_tor_exit_describe_codes() {
  (( $# > 0 )) || return 0
  chroot_require_python
  local tsv_file
  tsv_file="$CHROOT_TMP_DIR/tor-countries.$$.tsv"
  chroot_tor_country_catalog_tsv >"$tsv_file"
  "$CHROOT_PYTHON_BIN" - "$tsv_file" "$@" <<'PY'
import sys

tsv_path, *codes = sys.argv[1:]
catalog = {}
with open(tsv_path, "r", encoding="utf-8") as fh:
    for raw in fh:
        raw = raw.strip()
        if not raw:
            continue
        code, name = raw.split("\t", 1)
        catalog[code.lower()] = name

seen = set()
items = []
for code in codes:
    code = str(code or "").strip().lower()
    if not code or code in seen:
        continue
    seen.add(code)
    name = catalog.get(code, "")
    if name:
        items.append(f"{name} ({code.upper()})")
    else:
        items.append(code.upper())

print(", ".join(items))
PY
  rm -f -- "$tsv_file"
}

chroot_tor_exit_show_json() {
  local distro="$1"
  [[ -f "$(chroot_tor_config_file "$distro")" ]] || {
    printf '{\n  "countries": [],\n  "performance": false,\n  "performance_ignored_countries": [],\n  "strict": false\n}\n'
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
ignored = [str(x).strip().lower() for x in data.get("exit_performance_ignored_countries", []) if str(x).strip()]
strict = bool(data.get("exit_strict"))
performance = bool(data.get("exit_performance"))
print(json.dumps({"countries": countries, "performance": performance, "performance_ignored_countries": ignored, "strict": strict}, indent=2, sort_keys=True))
PY
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
data["schema_version"] = 3
data["exit_strict"] = strict_text == "true"
if data["exit_strict"]:
    data["exit_performance"] = False
with open(dst, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY
  mv -f -- "$tmp" "$config_file"
  chroot_tor_exit_cache_refresh "$distro"
  chroot_tor_targets_invalidate "$distro"
}

chroot_tor_exit_set_performance() {
  local distro="$1"
  local value="$2"
  local performance_bool="false"
  case "${value,,}" in
    1|true|yes|on) performance_bool="true" ;;
    0|false|no|off) performance_bool="false" ;;
    *) chroot_die "performance value must be on|off" ;;
  esac
  chroot_tor_config_ensure_file "$distro"
  chroot_require_python
  local config_file tmp
  config_file="$(chroot_tor_config_file "$distro")"
  tmp="$config_file.$$.tmp"
  "$CHROOT_PYTHON_BIN" - "$config_file" "$tmp" "$performance_bool" <<'PY'
import json
import sys

src, dst, performance_text = sys.argv[1:4]
with open(src, "r", encoding="utf-8") as fh:
    data = json.load(fh)
data["schema_version"] = 3
data["exit_performance"] = performance_text == "true"
if data["exit_performance"]:
    data["exit_strict"] = False
with open(dst, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY
  mv -f -- "$tmp" "$config_file"
  chroot_tor_exit_cache_refresh "$distro"
  chroot_tor_targets_invalidate "$distro"
}

chroot_tor_exit_apply_selection_file() {
  local distro="$1"
  local selection_file="$2"
  [[ -f "$selection_file" ]] || chroot_die "selection file not found: $selection_file"
  chroot_tor_config_ensure_file "$distro"
  chroot_require_python
  local config_file tmp
  config_file="$(chroot_tor_config_file "$distro")"
  tmp="$config_file.$$.tmp"
  "$CHROOT_PYTHON_BIN" - "$config_file" "$selection_file" "$tmp" <<'PY'
import json
import sys

config_path, selection_path, out_path = sys.argv[1:4]
try:
    with open(config_path, "r", encoding="utf-8") as fh:
        config = json.load(fh)
        if not isinstance(config, dict):
            config = {}
except Exception:
    config = {}
try:
    with open(selection_path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
        if not isinstance(data, dict):
            data = {}
except Exception:
    data = {}

codes = [str(x).strip().lower() for x in data.get("selected_codes", []) if str(x).strip()]
if "performance_ignored_codes" in data:
    ignored = [str(x).strip().lower() for x in data.get("performance_ignored_codes", []) if str(x).strip()]
else:
    ignored = [str(x).strip().lower() for x in config.get("exit_performance_ignored_countries", []) if str(x).strip()]
strict = bool(data.get("strict"))
performance = bool(data.get("performance"))
if performance and strict:
    strict = False
if strict and not codes:
    raise SystemExit("strict mode requires at least one selected exit country")

config["exit_countries"] = sorted(set(codes))
config["exit_performance_ignored_countries"] = sorted(set(ignored))
config["schema_version"] = 3
config["exit_strict"] = strict
config["exit_performance"] = performance
with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(config, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY
  mv -f -- "$tmp" "$config_file"
  chroot_tor_exit_cache_refresh "$distro"
  chroot_tor_targets_invalidate "$distro"
}

chroot_tor_exit_set_codes_mode() {
  local distro="$1"
  local mode="$2"
  shift 2 || true
  (( $# > 0 )) || chroot_die "at least one exit country code is required"
  case "$mode" in
    selected|unselected) ;;
    *) chroot_die "invalid exit selection mode: $mode (expected: selected|unselected)" ;;
  esac

  chroot_tor_config_ensure_file "$distro"
  chroot_require_python
  local config_file tmp
  config_file="$(chroot_tor_config_file "$distro")"
  tmp="$config_file.$$.tmp"
  "$CHROOT_PYTHON_BIN" - "$config_file" "$tmp" "$mode" "$@" <<'PY'
import json
import sys

config_path, out_path, mode, *codes = sys.argv[1:]
try:
    with open(config_path, "r", encoding="utf-8") as fh:
        config = json.load(fh)
        if not isinstance(config, dict):
            config = {}
except Exception:
    config = {}

selected = set(str(x).strip().lower() for x in config.get("exit_countries", []) if str(x).strip())
codes = set(str(x).strip().lower() for x in codes if str(x).strip())

if mode == "selected":
    selected.update(codes)
else:
    selected.difference_update(codes)

config["exit_countries"] = sorted(selected)
config["schema_version"] = 3
if config.get("exit_strict") and not config["exit_countries"]:
    raise SystemExit("strict mode requires at least one selected exit country")

with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(config, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY
  mv -f -- "$tmp" "$config_file"
  chroot_tor_exit_cache_refresh "$distro"
  chroot_tor_targets_invalidate "$distro"
}

chroot_tor_exit_set_performance_ignore_codes_mode() {
  local distro="$1"
  local mode="$2"
  shift 2 || true
  (( $# > 0 )) || chroot_die "at least one performance-ignore country code is required"
  case "$mode" in
    ignored|allowed) ;;
    *) chroot_die "invalid performance-ignore mode: $mode (expected: ignored|allowed)" ;;
  esac

  chroot_tor_config_ensure_file "$distro"
  chroot_require_python
  local config_file tmp
  config_file="$(chroot_tor_config_file "$distro")"
  tmp="$config_file.$$.tmp"
  "$CHROOT_PYTHON_BIN" - "$config_file" "$tmp" "$mode" "$@" <<'PY'
import json
import sys

config_path, out_path, mode, *codes = sys.argv[1:]
try:
    with open(config_path, "r", encoding="utf-8") as fh:
        config = json.load(fh)
        if not isinstance(config, dict):
            config = {}
except Exception:
    config = {}

ignored = set(str(x).strip().lower() for x in config.get("exit_performance_ignored_countries", []) if str(x).strip())
codes = set(str(x).strip().lower() for x in codes if str(x).strip())

if mode == "ignored":
    ignored.update(codes)
else:
    ignored.difference_update(codes)

config["exit_performance_ignored_countries"] = sorted(ignored)
config["schema_version"] = 3

with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(config, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY
  mv -f -- "$tmp" "$config_file"
  chroot_tor_exit_cache_refresh "$distro"
  chroot_tor_targets_invalidate "$distro"
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

chroot_tor_exit_performance_ignore_resolved_tsv() {
  local distro="$1"
  local config_file tsv_file
  config_file="$(chroot_tor_config_file "$distro")"
  [[ -f "$config_file" ]] || {
    printf '\t\n'
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

codes = [str(x).strip().lower() for x in data.get("exit_performance_ignored_countries", []) if str(x).strip()]
resolved = []
for code in codes:
    resolved.append(f"{code}:{catalog.get(code, code.upper())}")
print("\t".join([",".join(codes), " | ".join(resolved)]))
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

chroot_tor_exit_performance_ignore_csv() {
  local distro="$1"
  local codes resolved
  IFS=$'\t' read -r codes resolved <<<"$(chroot_tor_exit_performance_ignore_resolved_tsv "$distro")"
  printf '%s\n' "${codes:-}"
}

chroot_tor_exit_performance_enabled() {
  local distro="$1"
  local config_file
  config_file="$(chroot_tor_config_file "$distro")"
  [[ -f "$config_file" ]] || {
    printf '0\n'
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
print("1" if data.get("exit_performance") else "0")
PY
}
