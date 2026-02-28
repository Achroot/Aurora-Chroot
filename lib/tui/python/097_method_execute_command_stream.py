    def execute_command_stream(self, cmd, stdin_data="", back_state=None):
        self.execute_command(cmd, stdin_data=stdin_data, back_state=back_state, interactive=False)

