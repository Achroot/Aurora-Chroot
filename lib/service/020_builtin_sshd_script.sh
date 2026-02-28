chroot_service_builtin_sshd_script_content() {
  cat <<'EOF'
#!/bin/sh
set -eu
install -d -m 755 /run/sshd
install -d -m 755 /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/aurora.conf <<'EOF2'
Port 2222
ListenAddress 0.0.0.0
PasswordAuthentication yes
PubkeyAuthentication yes
PermitRootLogin yes
EOF2
rm -f /etc/ssh/sshd_config.d/99-aurora-root.conf
if [ -f /etc/ssh/sshd_config ]; then
  if ! awk '
    {
      line=$0
      sub(/[[:space:]]*#.*/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (tolower(line) == "include /etc/ssh/sshd_config.d/*.conf") {
        found=1
      }
    }
    END {exit found ? 0 : 1}
  ' /etc/ssh/sshd_config >/dev/null 2>&1; then
    printf '\nInclude /etc/ssh/sshd_config.d/*.conf\n' >> /etc/ssh/sshd_config
  fi
fi
if ! ls /etc/ssh/ssh_host_*_key >/dev/null 2>&1; then
  ssh-keygen -A
fi

# Ensure stale/manual sshd listeners do not block the managed service port.
if command -v pkill >/dev/null 2>&1; then
  pkill -TERM -x sshd 2>/dev/null || true
  i=0
  while pgrep -x sshd >/dev/null 2>&1 && [ "$i" -lt 20 ]; do
    i=$((i + 1))
    sleep 0.1
  done
  pkill -KILL -x sshd 2>/dev/null || true
else
  pids="$(ps -eo pid=,comm= 2>/dev/null | awk '$2=="sshd"{print $1}')"
  if [ -n "$pids" ]; then
    # shellcheck disable=SC2086
    kill -TERM $pids 2>/dev/null || true
    sleep 0.2
    # shellcheck disable=SC2086
    kill -KILL $pids 2>/dev/null || true
  fi
fi

rm -f /run/sshd.pid 2>/dev/null || true
SSHD_BIN="$(command -v sshd 2>/dev/null || true)"
if [ -z "$SSHD_BIN" ]; then
  echo "sshd: sshd not found inside distro. Install openssh first." >&2
  exit 1
fi
exec "$SSHD_BIN" -D -e -f /etc/ssh/sshd_config
EOF
}
