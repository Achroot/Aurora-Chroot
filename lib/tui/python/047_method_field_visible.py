    def field_visible(self, field):
        def condition_matches(condition):
            current = self.form_values.get(condition.get("id"))
            expected = condition.get("equals")
            if isinstance(expected, (list, tuple, set)):
                return current in expected
            return current == expected

        show_if = field.get("show_if")
        if show_if:
            if isinstance(show_if, dict) and "all" in show_if:
                if not all(condition_matches(condition) for condition in show_if.get("all", [])):
                    return False
            elif not condition_matches(show_if):
                return False
        show_if_not = field.get("show_if_not")
        if show_if_not:
            current = self.form_values.get(show_if_not.get("id"))
            blocked = show_if_not.get("equals")
            if isinstance(blocked, (list, tuple, set)):
                if current in blocked:
                    return False
            elif current == blocked:
                return False
        return True
