    def stdin_payload(self):
        text = self.read_text("stdin_reply")
        return (text + "\n") if text else ""

