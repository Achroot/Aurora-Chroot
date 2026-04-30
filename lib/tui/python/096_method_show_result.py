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
        start_at_end=False,
        merged_output=None,
    ):
        output = merged_output if merged_output is not None else (stdout or "") + (stderr or "")
        if not output.strip():
            output = "(no output)"

        self.result_command = rendered_cmd
        self.result_exit_code = exit_code
        self.result_duration = duration
        self.result_lines = output.splitlines()
        self.result_hscroll = 0
        self.result_back_state = back_state
        self.result_rerun_cmd = rerun_cmd
        self.result_rerun_stdin = rerun_stdin
        self.result_rerun_interactive = bool(rerun_interactive)
        self.result_info_mode = bool(
            isinstance(rerun_cmd, list)
            and len(rerun_cmd) >= 2
            and str(rerun_cmd[1]).strip().lower() == "info"
        )
        self.state = "result"
        if start_at_end:
            height, width = self.stdscr.getmaxyx()
            _content_top, content_height, _footer_lines = self.screen_content_layout(height, width)
            view_height = max(1, content_height - 4)
            self.result_scroll = max(0, len(self.result_lines) - view_height)
        else:
            self.result_scroll = 0

        if exit_code == 0:
            self.status(f"Completed in {duration:.2f}s", "ok")
        else:
            self.status(f"Exited with {exit_code}", "error")
