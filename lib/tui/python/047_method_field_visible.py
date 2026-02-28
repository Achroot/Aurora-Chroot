    def field_visible(self, field):
        show_if = field.get("show_if")
        if show_if:
            current = self.form_values.get(show_if.get("id"))
            expected = show_if.get("equals")
            if isinstance(expected, (list, tuple, set)):
                if current not in expected:
                    return False
            elif current != expected:
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

