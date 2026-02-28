    def show_result(
        self,
        rendered_cmd,
        stdout,
        stderr,
        exit_code,
        duration,
        back_state="menu",
        rerun_cmd=None,
        rerun_stdin="",
        rerun_interactive=False,
    ):
        output = (stdout or "") + (stderr or "")
        if not output.strip():
            output = "(no output)"

        self.result_command = rendered_cmd
        self.result_exit_code = exit_code
        self.result_duration = duration
        self.result_lines = output.splitlines()
        self.result_scroll = 0
        self.result_hscroll = 0
        self.result_back_state = back_state
        self.result_rerun_cmd = rerun_cmd
        self.result_rerun_stdin = rerun_stdin
        self.result_rerun_interactive = bool(rerun_interactive)
        self.state = "result"

        if exit_code == 0:
            self.status(f"Completed in {duration:.2f}s", "ok")
        else:
            self.status(f"Exited with {exit_code}", "error")


