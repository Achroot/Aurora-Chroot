    def execute_command(self, cmd, stdin_data="", back_state=None, interactive=False):

        if back_state is None:
            back_state = self.state
        rendered = " ".join(shlex.quote(part) for part in cmd)
        
        def draw_loader(spinner_char):
            self.draw_running_screen(rendered, spinner_char)

        rc, stdout, stderr, duration, _, merged_output = self.capture_command(
            cmd,
            stdin_data,
            draw_loading_func=draw_loader,
            interactive=interactive,
            log_user_triggered=True,
        )
        self.show_result(
            rendered,
            stdout,
            stderr,
            rc,
            duration,
            back_state=back_state,
            rerun_cmd=cmd,
            rerun_stdin=stdin_data,
            rerun_interactive=interactive,
            start_at_end=bool(interactive or self.last_capture_used_live_output),
            merged_output=merged_output,
        )
