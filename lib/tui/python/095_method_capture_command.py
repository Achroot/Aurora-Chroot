    def capture_command(self, cmd, stdin_data="", loading_text="Loading...", draw_loading_func=None, interactive=False, log_user_triggered=False, timeout=None, suppress_live_output=False):
        rendered = " ".join(shlex.quote(part) for part in cmd)
        started = time.time()
        preset_stdin_lines = len((stdin_data or "").splitlines())
        max_capture_lines = 20000
        max_display_lines = 2000
        max_line_chars = 262144
        child_env = os.environ.copy()
        child_env["CHROOT_LOG_SOURCE"] = "tui"
        command_name = str(cmd[1] if len(cmd) > 1 else "").strip().lower()
        def is_service_preload_command():
            if str(getattr(self, "active_command", "")).strip().lower() != "service":
                return False
            if log_user_triggered or interactive:
                return False
            parts = [str(part).strip().lower() for part in cmd]
            if len(parts) == 3 and parts[1:] == ["status", "--json"]:
                return True
            if len(parts) >= 5 and parts[2] == "service":
                tail = parts[3:]
                if tail in (["list", "--json"], ["status", "--json"], ["install", "--json"]):
                    return True
                if tail == ["install", "desktop", "--profiles", "--json"]:
                    return True
            return False

        suppress_live_output = bool(suppress_live_output or is_service_preload_command())
        if command_name == "logs":
            child_env["CHROOT_LOG_SKIP"] = "1"
        elif log_user_triggered:
            child_env.pop("CHROOT_LOG_SKIP", None)
        else:
            child_env["CHROOT_LOG_SKIP"] = "1"
        progress_file = ""
        try:
            progress_fd, progress_file = tempfile.mkstemp(prefix="aurora-progress.", suffix=".tsv")
            os.close(progress_fd)
            child_env["CHROOT_PROGRESS_FILE"] = progress_file
        except Exception:
            progress_file = ""

        stdout_lines = deque(maxlen=max_capture_lines)
        stderr_lines = deque(maxlen=max_capture_lines)
        merged_lines = deque(maxlen=max_capture_lines)
        display_lines = deque(maxlen=max_display_lines)
        stdout_current = [""]
        stderr_current = [""]
        merged_current = [""]
        display_current = [""]
        pending_cr = [False]
        pending_cr_is_err = [False]
        process_result = {}
        stream_lock = threading.Lock()
        stream_last_activity = [started]
        used_live_output = bool(interactive)
        post_exit_output_grace = 0.5
        timeout_triggered = [False]
        timeout_kill_sent = [False]

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

        def flush_merged_line():
            merged_lines.append(merged_current[0])
            merged_current[0] = ""

        def clear_current_line(is_err):
            target = stderr_current if is_err else stdout_current
            target[0] = ""
            merged_current[0] = ""
            display_current[0] = ""

        def display_snapshot(limit=None):
            lines = list(display_lines)
            if display_current[0] or not lines:
                lines.append(display_current[0])
            if limit is not None and len(lines) > limit:
                return lines[-limit:]
            return lines

        def human_bytes_text(num):
            try:
                value = float(num)
            except Exception:
                return "unknown"
            if value <= 0:
                return "unknown"
            units = ["B", "K", "M", "G", "T", "P"]
            idx = 0
            while value >= 1024.0 and idx < len(units) - 1:
                value /= 1024.0
                idx += 1
            if idx == 0:
                return f"{int(value)}{units[idx]}"
            if value >= 10:
                return f"{value:.0f}{units[idx]}"
            return f"{value:.1f}{units[idx]}"

        def read_progress_state():
            if not progress_file:
                return None
            try:
                with open(progress_file, "r", encoding="utf-8") as fh:
                    text = fh.read().strip()
            except Exception:
                return None
            if not text:
                return None
            line = text.splitlines()[-1]
            parts = line.split("\t", 4)
            if len(parts) != 5 or parts[0] != "download":
                return None
            try:
                downloaded = int(parts[1] or "0")
            except Exception:
                downloaded = 0
            try:
                total = int(parts[2] or "0")
            except Exception:
                total = 0
            return {
                "downloaded": max(0, downloaded),
                "total": max(0, total),
                "status": str(parts[3] or ""),
                "url": str(parts[4] or ""),
            }

        def progress_summary_text():
            progress = read_progress_state()
            if not progress:
                return ""
            downloaded = int(progress.get("downloaded", 0) or 0)
            total = int(progress.get("total", 0) or 0)
            if total > 0:
                total_text = human_bytes_text(total)
                if downloaded > 0:
                    downloaded_text = human_bytes_text(downloaded)
                    percent = max(0, min(100, int(downloaded * 100 / total)))
                    return f"size={total_text}  progress={downloaded_text}/{total_text} ({percent}%)"
                return f"size={total_text}"
            if downloaded > 0:
                return f"downloaded={human_bytes_text(downloaded)}"
            return ""

        def append_output_char(ch, is_err):
            with stream_lock:
                stream_last_activity[0] = time.time()
                if pending_cr[0]:
                    if ch == '\n':
                        pending_cr[0] = False
                    elif ch == '\r':
                        pending_cr_is_err[0] = is_err
                        return
                    else:
                        clear_current_line(pending_cr_is_err[0])
                        pending_cr[0] = False
                target = stderr_current if is_err else stdout_current
                if ch == '\n':
                    flush_stream_line(is_err)
                    flush_merged_line()
                    flush_display_line()
                elif ch == '\r':
                    pending_cr[0] = True
                    pending_cr_is_err[0] = is_err
                elif ch == '\b':
                    if target[0]:
                        target[0] = target[0][:-1]
                    if merged_current[0]:
                        merged_current[0] = merged_current[0][:-1]
                    if display_current[0]:
                        display_current[0] = display_current[0][:-1]
                else:
                    append_limited(target, ch)
                    append_limited(merged_current, ch)
                    append_limited(display_current, ch)

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

        def terminate_process(p, force=False):
            sig = signal.SIGKILL if force else signal.SIGTERM
            sent = False
            try:
                os.killpg(os.getpgid(p.pid), sig)
                sent = True
            except Exception:
                try:
                    if force:
                        p.kill()
                    else:
                        p.terminate()
                    sent = True
                except Exception:
                    sent = False
            return sent

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
                            env=child_env,
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
                    t_io.join(1.0)
                    try:
                        os.close(master_fd)
                    except OSError:
                        pass
                    if t_io.is_alive():
                        t_io.join(0.2)
                else:
                    p = subprocess.Popen(
                        cmd,
                        stdin=subprocess.PIPE,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        bufsize=0,
                        env=child_env,
                    )

                    process_result["p"] = p

                    if stdin_data:
                        try:
                            p.stdin.write(stdin_data.encode("utf-8", errors="replace"))
                            p.stdin.flush()
                        except Exception:
                            pass
                        p.stdin.close()

                    stream_fds = {}
                    if p.stdout is not None:
                        stdout_fd = p.stdout.fileno()
                        os.set_blocking(stdout_fd, False)
                        stream_fds[stdout_fd] = False
                    if p.stderr is not None:
                        stderr_fd = p.stderr.fileno()
                        os.set_blocking(stderr_fd, False)
                        stream_fds[stderr_fd] = True

                    exit_seen_at = None
                    while stream_fds:
                        ready, _, _ = select.select(list(stream_fds), [], [], 0.1)
                        for fd in ready:
                            try:
                                chunk = os.read(fd, 4096)
                            except BlockingIOError:
                                continue
                            except OSError:
                                chunk = b""

                            if not chunk:
                                stream_fds.pop(fd, None)
                                continue

                            text = chunk.decode("utf-8", errors="replace")
                            is_err = stream_fds.get(fd, False)
                            for ch in text:
                                append_output_char(ch, is_err)

                        if p.poll() is not None:
                            if exit_seen_at is None:
                                exit_seen_at = time.time()
                            idle_for = time.time() - stream_last_activity[0]
                            if idle_for >= post_exit_output_grace and time.time() - exit_seen_at >= post_exit_output_grace:
                                break

                    for stream in (p.stdout, p.stderr):
                        try:
                            if stream is not None:
                                stream.close()
                        except Exception:
                            pass
                    p.wait()

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
        live_output_scroll = 0
        live_output_hscroll = 0
        live_follow_tail = True
        current_live_lines = []
        current_live_height = 1
        current_live_width = 1

        def live_output_max_hscroll(lines, visible_width):
            visible_width = max(1, int(visible_width))
            return max(0, max((len(str(line).replace("\t", "    ")) for line in lines), default=0) - visible_width)

        def live_output_view(lines, visible_height, visible_width):
            nonlocal live_output_scroll, live_output_hscroll
            visible_height = max(1, int(visible_height))
            visible_width = max(1, int(visible_width))
            max_scroll = max(0, len(lines) - visible_height)
            if live_follow_tail:
                live_output_scroll = max_scroll
            else:
                live_output_scroll = max(0, min(live_output_scroll, max_scroll))
            live_output_hscroll = max(
                0,
                min(live_output_hscroll, live_output_max_hscroll(lines, visible_width)),
            )
            return live_output_scroll, live_output_hscroll

        def scroll_live_output(lines, visible_height, delta, page=False):
            nonlocal live_output_scroll, live_follow_tail
            visible_height = max(1, int(visible_height))
            step = visible_height if page else 1
            max_scroll = max(0, len(lines) - visible_height)
            live_output_scroll = max(0, min(max_scroll, live_output_scroll + (delta * step)))
            live_follow_tail = live_output_scroll >= max_scroll

        def pan_live_output(lines, visible_width, delta):
            nonlocal live_output_hscroll
            max_hscroll = live_output_max_hscroll(lines, visible_width)
            live_output_hscroll = max(
                0,
                min(max_hscroll, live_output_hscroll + (delta * self.hscroll_step())),
            )

        def jump_live_output(lines, visible_height, to_end=False):
            nonlocal live_output_scroll, live_follow_tail
            max_scroll = max(0, len(lines) - max(1, int(visible_height)))
            live_output_scroll = max_scroll if to_end else 0
            live_follow_tail = bool(to_end)

        def handle_live_mouse(lines, visible_height, visible_width):
            button4 = getattr(curses, "BUTTON4_PRESSED", 0x80000)
            button5 = getattr(curses, "BUTTON5_PRESSED", 0x200000)
            try:
                _mouse_id, _x, _y, _z, bstate = curses.getmouse()
            except Exception:
                return True
            if bstate & button4:
                scroll_live_output(lines, visible_height, -1)
                return True
            if bstate & button5:
                scroll_live_output(lines, visible_height, 1)
                return True
            return True

        def handle_live_navigation_key(key, lines, visible_height, visible_width, allow_letters=False):
            if key == curses.KEY_MOUSE:
                return handle_live_mouse(lines, visible_height, visible_width)
            if key == curses.KEY_UP or (allow_letters and key in (ord("k"),)):
                scroll_live_output(lines, visible_height, -1)
                return True
            if key == curses.KEY_DOWN or (allow_letters and key in (ord("j"),)):
                scroll_live_output(lines, visible_height, 1)
                return True
            if key == curses.KEY_PPAGE:
                scroll_live_output(lines, visible_height, -1, page=True)
                return True
            if key == curses.KEY_NPAGE:
                scroll_live_output(lines, visible_height, 1, page=True)
                return True
            if key == curses.KEY_HOME:
                jump_live_output(lines, visible_height, to_end=False)
                return True
            if key == curses.KEY_END:
                jump_live_output(lines, visible_height, to_end=True)
                return True
            if key == curses.KEY_LEFT or (allow_letters and key in (ord("h"), ord("<"))):
                pan_live_output(lines, visible_width, -1)
                return True
            if key == curses.KEY_RIGHT or (allow_letters and key in (ord("l"), ord(">"))):
                pan_live_output(lines, visible_width, 1)
                return True
            return False

        def is_live_navigation_key(key, allow_letters=False):
            if key in (
                curses.KEY_MOUSE,
                curses.KEY_UP,
                curses.KEY_DOWN,
                curses.KEY_PPAGE,
                curses.KEY_NPAGE,
                curses.KEY_HOME,
                curses.KEY_END,
                curses.KEY_LEFT,
                curses.KEY_RIGHT,
            ):
                return True
            if allow_letters and key in (ord("h"), ord("j"), ord("k"), ord("l"), ord("<"), ord(">")):
                return True
            return False

        self.stdscr.nodelay(True)
        if interactive:
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
                if timeout is not None and elapsed >= float(timeout):
                    timeout_triggered[0] = True
                    if "p" in process_result:
                        p = process_result["p"]
                        if elapsed >= float(timeout) + 1.0:
                            if not timeout_kill_sent[0]:
                                terminate_process(p, force=True)
                                timeout_kill_sent[0] = True
                        else:
                            terminate_process(p, force=False)
                if interactive:
                    used_live_output = True
                    height, width = self.stdscr.getmaxyx()
                    self.stdscr.erase()
                    footer_entries = ["Live exec running. Wait for completion to return to results."]
                    if self.screen_too_small(height, width, footer_entries=footer_entries):
                        self.draw_too_small(height, width)
                    else:
                        self.draw_header(height, width)
                        content_top, content_height, footer_lines = self.screen_content_layout(height, width, footer_entries=footer_entries)
                        footer_border_y = height - len(footer_lines) - 1
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
                        progress_text = progress_summary_text()
                        status_parts = [f"elapsed={elapsed:.1f}s"]
                        if progress_text:
                            status_parts.append(progress_text)
                        if preset_stdin_lines:
                            status_parts.append(f"preset-stdin={preset_stdin_lines} line(s)")
                        addstr_clipped(
                            self.stdscr,
                            content_top + 2,
                            2,
                            "  ".join(status_parts),
                            width - 5,
                            self.color(3),
                        )

                        output_top = content_top + 3
                        output_height = max(3, content_height - 12)
                        with stream_lock:
                            live_lines = display_snapshot()
                            snapshot_lines = live_lines[-max(24, output_height + 4):]

                        output_width = max(1, width - 5)
                        start_idx, hscroll = live_output_view(live_lines, output_height, output_width)
                        current_live_lines = live_lines
                        current_live_height = output_height
                        current_live_width = output_width
                        for i in range(output_height):
                            line_idx = start_idx + i
                            if line_idx >= len(live_lines):
                                break
                            line = live_lines[line_idx].replace("\t", "    ")
                            if hscroll > 0:
                                line = line[hscroll:]
                            color = self.color(0)
                            line_lower = line.lower()
                            if "error" in line_lower or "fail" in line_lower:
                                color = self.color(5)
                            elif "warn" in line_lower:
                                color = self.color(2)
                            elif "success" in line_lower or "ok" in line_lower:
                                color = self.color(3)
                            addstr_clipped(self.stdscr, output_top + i, 2, line, output_width, color)

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
                        stdin_y = input_sep_y + 3
                        help_y = input_sep_y + 4
                        notice_y = input_sep_y + 5

                        if state_y < footer_border_y:
                            addstr_clipped(self.stdscr, state_y, 2, state_msg, width - 5, state_attr)
                        if prompt_y < footer_border_y:
                            if detected_prompt:
                                addstr_clipped(self.stdscr, prompt_y, 2, f"Prompt: {detected_prompt}", width - 5, self.color(6))
                            elif expected_hint:
                                addstr_clipped(self.stdscr, prompt_y, 2, expected_hint, width - 5, self.color(2))

                        prompt = "stdin> "
                        text = "".join(input_buffer)
                        display_w = max(10, width - len(prompt) - 6)
                        if len(text) > display_w:
                            text = text[-display_w:]
                        if stdin_y < footer_border_y:
                            addstr_clipped(self.stdscr, stdin_y, 2, prompt + text, width - 5, self.color(1, curses.A_BOLD))
                        if help_y < footer_border_y:
                            addstr_clipped(
                                self.stdscr,
                                help_y,
                                2,
                                "Enter: send line  Backspace: edit  Ctrl-D: close stdin  Ctrl-C: stop",
                                width - 5,
                                self.color(3),
                            )
                        if live_notice and notice_y < footer_border_y:
                            addstr_clipped(self.stdscr, notice_y, 2, live_notice, width - 5, self.color(2))

                        self.draw_footer_lines(height, width, footer_lines)
                elif elapsed < 5.0 or suppress_live_output:
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
                    footer_entries = ["Command running... output updates live."]
                    if self.screen_too_small(height, width, footer_entries=footer_entries):
                        self.draw_too_small(height, width)
                    else:
                        self.draw_header(height, width)
                        content_top, content_height, footer_lines = self.screen_content_layout(height, width, footer_entries=footer_entries)
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
                        progress_text = progress_summary_text()
                        status_line = f"elapsed={elapsed:.1f}s"
                        if progress_text:
                            status_line += f"  {progress_text}"
                        addstr_clipped(self.stdscr, content_top + 2, 2, status_line, width - 5, self.color(3))

                        out_h = max(3, content_height - 5)
                        with stream_lock:
                            live_lines = display_snapshot()
                        output_width = max(1, width - 5)
                        start_idx, hscroll = live_output_view(live_lines, out_h, output_width)
                        current_live_lines = live_lines
                        current_live_height = out_h
                        current_live_width = output_width
                        for i in range(out_h):
                            line_idx = start_idx + i
                            if line_idx < len(live_lines):
                                line = live_lines[line_idx].replace("\t", "    ")
                                if hscroll > 0:
                                    line = line[hscroll:]
                                color = self.color(0)
                                line_lower = line.lower()
                                if "error" in line_lower or "fail" in line_lower:
                                    color = self.color(5)
                                elif "warn" in line_lower:
                                    color = self.color(2)
                                elif "success" in line_lower or "ok" in line_lower:
                                    color = self.color(3)
                                addstr_clipped(self.stdscr, content_top + 3 + i, 2, line, output_width, color)

                        self.draw_footer_lines(height, width, footer_lines)

                self.stdscr.refresh()

                if interactive:
                    if sigint_requested[0] and "p" in process_result:
                        sigint_requested[0] = False
                        p = process_result["p"]
                        master_fd = process_result.get("master_fd")
                        live_notice = send_ctrl_c_interrupt(p, master_fd)
                    try:
                        ch = self.stdscr.getch()
                        if ch != curses.ERR:
                            if is_live_navigation_key(ch, allow_letters=False):
                                pass
                            elif "p" in process_result:
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
                else:
                    try:
                        ch = self.stdscr.getch()
                        if ch != curses.ERR and is_live_navigation_key(ch, allow_letters=True):
                            pass
                    except Exception:
                        pass

                idx = (idx + 1) % len(spinner)
                t.join(0.1)
        finally:
            self.stdscr.nodelay(False)
            if interactive:
                if previous_sigint_handler is not None:
                    try:
                        signal.signal(signal.SIGINT, previous_sigint_handler)
                    except Exception:
                        pass
            if progress_file:
                try:
                    os.unlink(progress_file)
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
            if merged_current[0]:
                merged_lines.append(merged_current[0])
                merged_current[0] = ""
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
        merged_output = "\n".join(list(merged_lines))

        if timeout_triggered[0]:
            rc = 124
            timeout_text = "command timed out"
            stderr = ((stderr + "\n") if stderr else "") + timeout_text

        duration = time.time() - started
        self.last_capture_used_live_output = used_live_output
        return rc, stdout, stderr, duration, rendered, merged_output
