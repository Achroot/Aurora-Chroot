def wrap_lines(text, width):
    if width <= 4:
        return []
    if text is None:
        return []
    try:
        return textwrap.wrap(
            str(text),
            width=width,
            break_long_words=False,
            replace_whitespace=False,
        )
    except Exception:
        return []


