    def capture_command(self, cmd, stdin_data="", loading_text="Loading...", draw_loading_func=None, interactive=False):
        rendered = " ".join(shlex.quote(part) for part in cmd)
        started = time.time()
        preset_stdin_lines = len((stdin_data or "").splitlines())
        max_capture_lines = 4000
        max_display_lines = 2000
        max_line_chars = 8192

        stdout_lines = deque(maxlen=max_capture_lines)
        stderr_lines = deque(maxlen=max_capture_lines)
        display_lines = deque(maxlen=max_display_lines)
        stdout_current = [""]
        stderr_current = [""]
        display_current = [""]
        process_result = {}
        stream_lock = threading.Lock()
        stream_last_activity = [started]
        used_live_output = bool(interactive)

        def append_limited(buf, ch):
            buf[0] += ch
            if len(buf[0]) > max_line_chars:
                buf[0] = buf[0][-max_line_chars:]

        def flush_stream_line(is_err):
            if is_err:
                stderr_lines.append(stderr_current[0])
                stderr_current[0] = ""
            else:
                stdout_lines.append(stdout_current[0])
                stdout_current[0] = ""

        def flush_display_line():
            display_lines.append(display_current[0])
            display_current[0] = ""

        def display_snapshot(limit=None):
            lines = list(display_lines)
            if display_current[0] or not lines:
                lines.append(display_current[0])
            if limit is not None and len(lines) > limit:
                return lines[-limit:]
            return lines

        def append_output_char(ch, is_err):
            with stream_lock:
                stream_last_activity[0] = time.time()
                target = stderr_current if is_err else stdout_current
                if ch == '\n':
                    flush_stream_line(is_err)
                    flush_display_line()
                elif ch == '\r':
                    pass
                elif ch == '\b':
                    if target[0]:
                        target[0] = target[0][:-1]
                    if display_current[0]:
                        display_current[0] = display_current[0][:-1]
                else:
                    append_limited(target, ch)
                    append_limited(display_current, ch)

        def read_stream(stream, is_err):
            try:
                while True:
                    ch = stream.read(1)
                    if not ch:
                        break
                    append_output_char(ch, is_err)
            except Exception:
                pass

        def read_pty(master_fd):
            try:
                while True:
                    ready, _, _ = select.select([master_fd], [], [], 0.25)
                    if not ready:
                        continue
                    chunk = os.read(master_fd, 1024)
                    if not chunk:
                        break
                    text = chunk.decode("utf-8", errors="replace")
                    for ch in text:
                        append_output_char(ch, False)
            except Exception:
                pass

        def infer_expected_input(prompt_text):
            merged = str(prompt_text or "").lower()
            if "(y/n" in merged or " y/n" in merged or "(yes/no" in merged or " yes/no" in merged:
                return "Expected input: y or n"
            if "password" in merged:
                return "Expected input: password text"
            if "press enter" in merged or "hit enter" in merged:
                return "Expected input: press Enter"
            quoted = re.search(r"""['\"]([^'\"]{1,40})['\"]""", str(prompt_text or ""))
            if quoted:
                literal = quoted.group(1).strip()
                if literal:
                    return f"Expected input: {literal}"
            explicit = re.search(
                r"\b(?:token|code|passphrase|word)\b\s*(?:is|=|:)?\s*([A-Za-z0-9._-]{2,40})\b",
                merged,
            )
            if explicit:
                return f"Expected input: {explicit.group(1)}"
            enter_to = re.search(r"\benter\s+([A-Za-z0-9._-]{2,40})\s+to\b", merged)
            if enter_to:
                return f"Expected input: {enter_to.group(1)}"
            return ""

        def detect_input_state(lines, idle_for, stdin_open):
            if not stdin_open:
                return ("closed", "STDIN is closed; process cannot receive more input.", "", "")

            last_text = ""
            for raw in reversed(lines):
                text = str(raw).strip()
                if text:
                    last_text = text
                    break

            lowered = last_text.lower()
            looks_prompt = bool(last_text) and (
                last_text.endswith("?")
                or last_text.endswith(":")
                or last_text.endswith("):")
                or "(y/n" in lowered
                or "(yes/no" in lowered
                or "continue" in lowered
                or "password" in lowered
                or "prompt" in lowered
                or "enter " in lowered
            )

            prompt_text = last_text
            if not looks_prompt:
                for raw in reversed(lines):
                    text = str(raw).strip()
                    if not text:
                        continue
                    ltext = text.lower()
                    if "(y/n" in ltext or "(yes/no" in ltext or "continue?" in ltext or "password" in ltext:
                        prompt_text = text
                        looks_prompt = True
                        break

            expected_hint = infer_expected_input(prompt_text)

            if looks_prompt and idle_for >= 0.6:
                return ("needs_input", f"Input requested (idle {idle_for:.1f}s).", prompt_text, expected_hint)
            if idle_for >= 2.5:
                return ("likely_wait", f"No new output for {idle_for:.1f}s; process may be waiting for input.", prompt_text, expected_hint)
            return ("running", "Running. Type input below and press Enter to send a line.", prompt_text, expected_hint)

        def send_ctrl_c_interrupt(p, master_fd):
            sent_pty_interrupt = False
            sent_signal_interrupt = False
            if master_fd is not None:
                try:
                    os.write(master_fd, b"\x03")
                    sent_pty_interrupt = True
                except Exception:
                    sent_pty_interrupt = False
            try:
                os.killpg(os.getpgid(p.pid), signal.SIGINT)
                sent_signal_interrupt = True
            except Exception:
                try:
                    p.send_signal(signal.SIGINT)
                    sent_signal_interrupt = True
                except Exception:
                    sent_signal_interrupt = False
            if sent_pty_interrupt and sent_signal_interrupt:
                return "Sent Ctrl-C to stdin and process group."
            if sent_pty_interrupt or sent_signal_interrupt:
                return "Sent Ctrl-C interrupt."
            return "Could not send Ctrl-C (process may have exited)."

        def worker():
            try:
                if interactive:
                    master_fd, slave_fd = pty.openpty()
                    try:
                        p = subprocess.Popen(
                            cmd,
                            stdin=slave_fd,
                            stdout=slave_fd,
                            stderr=slave_fd,
                            close_fds=True,
                        )
                    finally:
                        try:
                            os.close(slave_fd)
                        except OSError:
                            pass

                    process_result["p"] = p
                    process_result["master_fd"] = master_fd

                    if stdin_data:
                        try:
                            os.write(master_fd, stdin_data.encode("utf-8", errors="replace"))
                        except Exception:
                            pass

                    t_io = threading.Thread(target=read_pty, args=(master_fd,))
                    t_io.daemon = True
                    t_io.start()

                    p.wait()
                    try:
                        os.close(master_fd)
                    except OSError:
                        pass
                    t_io.join()
                else:
                    p = subprocess.Popen(
                        cmd,
                        stdin=subprocess.PIPE,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        text=True,
                        bufsize=1,
                    )

                    process_result["p"] = p

                    if stdin_data:
                        try:
                            p.stdin.write(stdin_data)
                            p.stdin.flush()
                        except Exception:
                            pass
                        p.stdin.close()

                    t_out = threading.Thread(target=read_stream, args=(p.stdout, False))
                    t_err = threading.Thread(target=read_stream, args=(p.stderr, True))
                    t_out.daemon = True
                    t_err.daemon = True
                    t_out.start()
                    t_err.start()

                    p.wait()
                    t_out.join()
                    t_err.join()

                process_result["rc"] = p.returncode
            except Exception as e:
                process_result["error"] = e

        t = threading.Thread(target=worker)
        t.daemon = True
        t.start()

        spinner = "|/-\\"
        idx = 0
        input_buffer = []
        live_notice = ""
        sigint_requested = [False]
        previous_sigint_handler = None

        if interactive:
            self.stdscr.nodelay(True)
            def mark_sigint(_signum, _frame):
                sigint_requested[0] = True
            try:
                previous_sigint_handler = signal.getsignal(signal.SIGINT)
                signal.signal(signal.SIGINT, mark_sigint)
            except Exception:
                previous_sigint_handler = None

        try:
            while t.is_alive():
                elapsed = time.time() - started
                if interactive:
                    used_live_output = True
                    height, width = self.stdscr.getmaxyx()
                    self.stdscr.erase()
                    if height < 14 or width < 54:
                        self.draw_too_small(height, width)
                    else:
                        self.draw_header(height, width)
                        content_top = 2
                        content_height = height - content_top - 3
                        draw_box(
                            self.stdscr,
                            content_top,
                            0,
                            content_height,
                            width - 1,
                            f"EXEC LIVE {spinner[idx]}",
                            self.color(4),
                            self.color(1, curses.A_BOLD),
                        )
                        addstr_clipped(self.stdscr, content_top + 1, 2, f"$ {rendered}", width - 5, self.color(6, curses.A_BOLD))
                        addstr_clipped(
                            self.stdscr,
                            content_top + 2,
                            2,
                            f"elapsed={elapsed:.1f}s  preset-stdin={preset_stdin_lines} line(s)  Ctrl-D: close stdin  Ctrl-C: stop",
                            width - 5,
                            self.color(3),
                        )

                        output_top = content_top + 3
                        output_height = max(3, content_height - 12)
                        with stream_lock:
                            live_lines = display_snapshot()
                            snapshot_lines = live_lines[-max(24, output_height + 4):]

                        start_idx = max(0, len(live_lines) - output_height)
                        for i in range(output_height):
                            line_idx = start_idx + i
                            if line_idx >= len(live_lines):
                                break
                            line = live_lines[line_idx].replace("\t", "    ")
                            color = self.color(0)
                            line_lower = line.lower()
                            if "error" in line_lower or "fail" in line_lower:
                                color = self.color(5)
                            elif "warn" in line_lower:
                                color = self.color(2)
                            elif "success" in line_lower or "ok" in line_lower:
                                color = self.color(3)
                            addstr_clipped(self.stdscr, output_top + i, 2, line, width - 5, color)

                        input_sep_y = output_top + output_height
                        addstr_safe(self.stdscr, input_sep_y, 1, "-" * max(1, width - 3), self.color(4))

                        p = process_result.get("p")
                        master_fd = process_result.get("master_fd")
                        stdin_open = bool((master_fd is not None) or (p and p.stdin and not p.stdin.closed))
                        idle_for = max(0.0, time.time() - stream_last_activity[0])
                        state_kind, state_msg, detected_prompt, expected_hint = detect_input_state(snapshot_lines, idle_for, stdin_open)
                        state_attr = self.color(3, curses.A_BOLD)
                        if state_kind in ("needs_input", "likely_wait"):
                            state_attr = self.color(2, curses.A_BOLD)
                        elif state_kind == "closed":
                            state_attr = self.color(5, curses.A_BOLD)

                        state_y = input_sep_y + 1
                        prompt_y = input_sep_y + 2
                        expected_y = input_sep_y + 3
                        stdin_y = input_sep_y + 4
                        help_y = input_sep_y + 5
                        notice_y = input_sep_y + 6

                        if state_y < height - 2:
                            addstr_clipped(self.stdscr, state_y, 2, state_msg, width - 5, state_attr)
                        if prompt_y < height - 2:
                            if detected_prompt:
                                addstr_clipped(self.stdscr, prompt_y, 2, f"Prompt: {detected_prompt}", width - 5, self.color(6))
                            else:
                                addstr_clipped(self.stdscr, prompt_y, 2, "Prompt: <not detected>", width - 5, self.color(6))
                        if expected_y < height - 2:
                            hint_text = expected_hint if expected_hint else "Expected input: <unknown, check prompt above>"
                            addstr_clipped(self.stdscr, expected_y, 2, hint_text, width - 5, self.color(2))

                        prompt = "stdin> "
                        text = "".join(input_buffer)
                        display_w = max(10, width - len(prompt) - 6)
                        if len(text) > display_w:
                            text = text[-display_w:]
                        if stdin_y < height - 2:
                            addstr_clipped(self.stdscr, stdin_y, 2, prompt + text, width - 5, self.color(1, curses.A_BOLD))
                        if help_y < height - 2:
                            addstr_clipped(
                                self.stdscr,
                                help_y,
                                2,
                                "Enter: send line  Backspace: edit",
                                width - 5,
                                self.color(3),
                            )
                        if live_notice and notice_y < height - 2:
                            addstr_clipped(self.stdscr, notice_y, 2, live_notice, width - 5, self.color(2))

                        addstr_safe(self.stdscr, height - 2, 0, "+" + "-" * (width - 2) + "+", self.color(4))
                        addstr_clipped(self.stdscr, height - 1, 1, "Live exec running. Wait for completion to return to results.", width - 2, self.color(3))
                elif elapsed < 5.0:
                    if draw_loading_func:
                        draw_loading_func(spinner[idx])
                    else:
                        height, width = self.draw_current_state()
                        if height >= 14 and width >= 54:
                            self.draw_loading_box(
                                f"{loading_text} {spinner[idx]}", height, width
                            )
                else:
                    used_live_output = True
                    height, width = self.stdscr.getmaxyx()
                    self.stdscr.erase()
                    if height < 14 or width < 54:
                        self.draw_too_small(height, width)
                    else:
                        self.draw_header(height, width)
                        content_top = 2
                        content_height = height - content_top - 3
                        draw_box(
                            self.stdscr,
                            content_top,
                            0,
                            content_height,
                            width - 1,
                            f"RUNNING {spinner[idx]}",
                            self.color(4),
                            self.color(2, curses.A_BOLD),
                        )
                        addstr_clipped(self.stdscr, content_top + 1, 2, f"$ {rendered}", width - 5, self.color(6, curses.A_BOLD))
                        addstr_clipped(self.stdscr, content_top + 2, 2, f"elapsed={elapsed:.1f}s", width - 5, self.color(3))

                        out_h = max(3, content_height - 5)
                        with stream_lock:
                            live_lines = display_snapshot()
                        start_idx = max(0, len(live_lines) - out_h)
                        for i in range(out_h):
                            line_idx = start_idx + i
                            if line_idx < len(live_lines):
                                line = live_lines[line_idx].replace("\t", "    ")
                                color = self.color(0)
                                line_lower = line.lower()
                                if "error" in line_lower or "fail" in line_lower:
                                    color = self.color(5)
                                elif "warn" in line_lower:
                                    color = self.color(2)
                                elif "success" in line_lower or "ok" in line_lower:
                                    color = self.color(3)
                                addstr_clipped(self.stdscr, content_top + 3 + i, 2, line, width - 5, color)

                        addstr_safe(self.stdscr, height - 2, 0, "+" + "-" * (width - 2) + "+", self.color(4))
                        addstr_clipped(self.stdscr, height - 1, 1, "Command running... output updates live.", width - 2, self.color(3))

                self.stdscr.refresh()

                if interactive:
                    if sigint_requested[0] and "p" in process_result:
                        sigint_requested[0] = False
                        p = process_result["p"]
                        master_fd = process_result.get("master_fd")
                        live_notice = send_ctrl_c_interrupt(p, master_fd)
                    try:
                        ch = self.stdscr.getch()
                        if ch != curses.ERR and "p" in process_result:
                            p = process_result["p"]
                            master_fd = process_result.get("master_fd")
                            if ch in (3,):
                                live_notice = send_ctrl_c_interrupt(p, master_fd)
                            elif ch in (4,):
                                if master_fd is not None:
                                    try:
                                        os.write(master_fd, b"\x04")
                                        live_notice = "Sent EOF (Ctrl-D)."
                                    except Exception:
                                        live_notice = "Could not send EOF (process may have exited)."
                                elif p.stdin and not p.stdin.closed:
                                    p.stdin.close()
                                    live_notice = "STDIN closed (EOF sent)."
                            elif ch in (curses.KEY_BACKSPACE, 127, 8):
                                if input_buffer:
                                    input_buffer.pop()
                            elif ch in (10, 13, curses.KEY_ENTER):
                                try:
                                    line = "".join(input_buffer)
                                    if master_fd is not None:
                                        os.write(master_fd, (line + "\n").encode("utf-8", errors="replace"))
                                    elif p.stdin and not p.stdin.closed:
                                        p.stdin.write(line + "\n")
                                        p.stdin.flush()
                                    live_notice = "Sent one line to STDIN."
                                except Exception:
                                    live_notice = "Could not write to STDIN (process may have exited)."
                                input_buffer = []
                            elif ch == 9:
                                input_buffer.append("    ")
                            elif 32 <= ch <= 126:
                                input_buffer.append(chr(ch))
                    except Exception:
                        pass

                idx = (idx + 1) % len(spinner)
                t.join(0.1)
        finally:
            if interactive:
                self.stdscr.nodelay(False)
                if previous_sigint_handler is not None:
                    try:
                        signal.signal(signal.SIGINT, previous_sigint_handler)
                    except Exception:
                        pass

        curses.flushinp()
        with stream_lock:
            if stdout_current[0]:
                stdout_lines.append(stdout_current[0])
                stdout_current[0] = ""
            if stderr_current[0]:
                stderr_lines.append(stderr_current[0])
                stderr_current[0] = ""
            if display_current[0]:
                display_lines.append(display_current[0])
                display_current[0] = ""

        if "error" in process_result:
            res = process_result["error"]
            if isinstance(res, FileNotFoundError):
                rc = 127
                stdout = ""
                stderr = f"Runner not found: {self.runner}"
            else:
                rc = 1
                stdout = ""
                stderr = f"Execution error: {res}"
        else:
            rc = process_result.get("rc", 1)
            stdout = "\n".join(list(stdout_lines))
            stderr = "\n".join(list(stderr_lines))

        duration = time.time() - started
        self.last_capture_used_live_output = used_live_output
        return rc, stdout, stderr, duration, rendered
