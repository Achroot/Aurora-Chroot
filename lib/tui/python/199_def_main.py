def main():
    base_dir = sys.argv[1] if len(sys.argv) > 1 else os.getcwd()
    if not os.environ.get("TERM"):
        os.environ["TERM"] = "xterm-256color"

    if not sys.stdin.isatty() or not sys.stdout.isatty():
        try:
            tty_fd = os.open("/dev/tty", os.O_RDWR)
            os.dup2(tty_fd, 0)
            os.dup2(tty_fd, 1)
            os.dup2(tty_fd, 2)
            os.close(tty_fd)
            sys.stdin = open(0, "r", encoding="utf-8", closefd=False)
            sys.stdout = open(1, "w", encoding="utf-8", closefd=False)
            sys.stderr = open(2, "w", encoding="utf-8", closefd=False)
        except Exception:
            pass

    def runner(stdscr):
        app = TuiApp(stdscr, base_dir)
        app.run()

    try:
        curses.wrapper(runner)
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
