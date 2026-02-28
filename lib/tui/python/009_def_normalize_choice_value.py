def normalize_choice_value(field, value):
    options = field.get("choices", [])
    if not options:
        return value
    option_values = [opt[0] if isinstance(opt, tuple) else opt for opt in options]
    if value in option_values:
        return value
    return option_values[0]


