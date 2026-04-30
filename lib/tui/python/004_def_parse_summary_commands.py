def parse_summary_commands(text):
    sections = []
    in_commands = False
    for raw in text.splitlines():
        line = raw.strip("\n")
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.lower().startswith("commands"):
            in_commands = True
            continue
        if not in_commands:
            continue
        if stripped.startswith("-"):
            continue
        if stripped.startswith("chroot ") or stripped.startswith("aurora "):
            continue
        cmd = None
        if stripped.startswith("help") or stripped.startswith("doctor"):
            cmd = stripped.split()[0]
        elif line.startswith("  "):
            parts = stripped.split()
            if parts:
                cmd = parts[0]
                if parts[0].startswith("<") and len(parts) > 1:
                    cmd = parts[1]
        if cmd:
            sections.append(
                {
                    "title": cmd,
                    "usage": cmd,
                    "lines": ["Details unavailable in bundled help."],
                    "summary": "Details unavailable in bundled help.",
                }
            )
    if not sections:
        sections.append(
            {
                "title": "help",
                "usage": "help",
                "lines": ["Details unavailable in bundled help."],
                "summary": "Details unavailable in bundled help.",
            }
        )
    return sections

