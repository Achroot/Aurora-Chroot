    def status(self, message, kind="info"):
        self.status_message = str(message)
        self.status_kind = kind
        self.status_time = time.time()

