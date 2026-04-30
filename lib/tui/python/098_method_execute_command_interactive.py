    def execute_command_interactive(self, cmd, back_state=None):
        if back_state is None:
            back_state = self.state

        curses.endwin()
        print(f"\n\rRunning: {' '.join(shlex.quote(p) for p in cmd)}\n\r")
        started = time.time()
        child_env = os.environ.copy()
        child_env["CHROOT_LOG_SOURCE"] = "tui"
        command_name = str(cmd[1] if len(cmd) > 1 else "").strip().lower()
        if command_name == "logs":
            child_env["CHROOT_LOG_SKIP"] = "1"
        else:
            child_env.pop("CHROOT_LOG_SKIP", None)
        try:
            completed = subprocess.run(cmd, env=child_env)
            rc = completed.returncode
        except Exception as exc:
            print(f"Error: {exc}")
            rc = 1

        duration = time.time() - started
        if rc != 0:
            print(f"\n\rCommand exited with {rc} (duration: {duration:.2f}s). Press Enter to return to TUI...\n\r")
            try:
                input()
            except:
                pass

        self.stdscr.clear()
        self.stdscr.refresh()
        curses.flushinp()
        self.state = back_state
        if rc == 0:
            self.status(f"Completed in {duration:.2f}s", "ok")
        else:
            self.status(f"Exited with {rc}", "error")
