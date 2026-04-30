def parse_help(text):
    sections = []
    current = None
    for raw in text.splitlines():
        line = raw.rstrip("\n")
        match = re.match(r"^### `(.+?)`", line)
        if match:
            if current:
                sections.append(current)
            raw_title = match.group(1).strip()
            parts = raw_title.split()
            name = parts[0] if parts else "help"
            if parts and parts[0].startswith("<") and len(parts) > 1:
                name = parts[1]
            current = {
                "title": name,
                "usage": raw_title,
                "lines": [],
                "summary": "",
            }
            continue
        if current:
            current["lines"].append(line)
    if current:
        sections.append(current)
    if not sections:
        sections = parse_summary_commands(text)

    for section in sections:
        summary = ""
        for line in section.get("lines", []):
            stripped = line.strip()
            if not stripped or stripped.startswith("-") or stripped.endswith(":"):
                continue
            summary = stripped
            break
        section["summary"] = summary or "Details are available in the bundled help text."
    return sections
