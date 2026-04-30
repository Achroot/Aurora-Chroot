def choice_label(field, value):
    for opt in field.get("choices", []):
        if isinstance(opt, tuple):
            if value == opt[0]:
                return opt[1]
        elif value == opt:
            return str(opt)
    return str(value)


