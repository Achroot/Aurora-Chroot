chroot_service_builtin_zsh_script_content() {
  cat <<'EOF'
#!/usr/bin/env bash
# Unified idempotent Zsh setup for root (Arch Linux / Ubuntu)

set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: Run this script as root inside the distro."
  exit 1
fi

# --- Detect distro type ---
# Accepts type from caller (external rootfs detection); falls back to package manager check.
DISTRO_TYPE="${1:-}"
if [[ -z "$DISTRO_TYPE" ]]; then
  if command -v pacman >/dev/null 2>&1; then
    DISTRO_TYPE="arch"
  elif command -v apt >/dev/null 2>&1; then
    DISTRO_TYPE="ubuntu"
  fi
fi

if [[ "$DISTRO_TYPE" != "arch" && "$DISTRO_TYPE" != "ubuntu" ]]; then
  echo "ERROR: Could not detect a supported distro (got '${DISTRO_TYPE:-none}')."
  echo "       Zsh setup only supports Arch Linux (pacman) and Ubuntu (apt)."
  exit 1
fi

case "$DISTRO_TYPE" in
  arch)
    BLOCK_TAG="ZSH-A"
    FD_COMMENT="Debian/Ubuntu compatibility fallback"
    ;;
  ubuntu)
    BLOCK_TAG="ZSH-U"
    FD_COMMENT="Debian/Ubuntu fd compatibility"
    ;;
esac

TOTAL_STEPS=8
STEP=0
next_step() {
  STEP=$((STEP + 1))
  echo "[$STEP/$TOTAL_STEPS] $1"
}

# --- 1. Install packages ---
case "$DISTRO_TYPE" in
  arch)
    next_step "Syncing packages and installing dependencies..."
    pacman -Sy --noconfirm --needed archlinux-keyring
    pacman -Syu --noconfirm
    pacman -S --noconfirm --needed zsh git fzf fd
    ;;
  ubuntu)
    next_step "Installing dependencies..."
    export DEBIAN_FRONTEND=noninteractive
    apt update
    apt upgrade -y
    apt install -y zsh git fzf fd-find
    ;;
esac

# --- 2. zsh-autocomplete plugin ---
next_step "Setting up zsh-autocomplete..."
AUTOCOMPLETE_DIR="/root/.zsh-autocomplete"
if [[ -d "${AUTOCOMPLETE_DIR}/.git" ]]; then
  git -C "${AUTOCOMPLETE_DIR}" fetch --depth 1 origin
  git -C "${AUTOCOMPLETE_DIR}" reset --hard origin/HEAD
else
  rm -rf "${AUTOCOMPLETE_DIR}"
  git clone --depth 1 https://github.com/marlonrichert/zsh-autocomplete.git "${AUTOCOMPLETE_DIR}"
fi

# --- 3. zsh-autosuggestions plugin ---
next_step "Setting up zsh-autosuggestions..."
AUTOSUGGESTIONS_DIR="/root/.zsh-autosuggestions"
if [[ -d "${AUTOSUGGESTIONS_DIR}/.git" ]]; then
  git -C "${AUTOSUGGESTIONS_DIR}" fetch --depth 1 origin
  git -C "${AUTOSUGGESTIONS_DIR}" reset --hard origin/HEAD
else
  rm -rf "${AUTOSUGGESTIONS_DIR}"
  git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions "${AUTOSUGGESTIONS_DIR}"
fi

# --- 4. Managed .zshrc block ---
next_step "Appending managed Zsh block into /root/.zshrc (no overwrite)..."
touch /root/.zshrc
if ! grep -q "### ${BLOCK_TAG} ZSHRC BLOCK START ###" /root/.zshrc; then
if [[ -s /root/.zshrc ]] && [[ "$(tail -c1 /root/.zshrc 2>/dev/null || true)" != $'\n' ]]; then
  echo >> /root/.zshrc
fi
cat >> /root/.zshrc <<ZSHRC
### ${BLOCK_TAG} ZSHRC BLOCK START ###
# Source aliases and environment from bashrc (if present)
[[ -f ~/.bashrc ]] && . ~/.bashrc

# Plugin: zsh-autocomplete
[[ -f ~/.zsh-autocomplete/zsh-autocomplete.plugin.zsh ]] && source ~/.zsh-autocomplete/zsh-autocomplete.plugin.zsh

# Plugin: zsh-autosuggestions
ZSH_AUTOSUGGEST_STRATEGY=(history)
[[ -f ~/.zsh-autosuggestions/zsh-autosuggestions.zsh ]] && source ~/.zsh-autosuggestions/zsh-autosuggestions.zsh

# Keep history intentionally small
HISTFILE=~/.zsh_history
HISTSIZE=50
SAVEHIST=50
setopt APPEND_HISTORY
setopt HIST_IGNORE_ALL_DUPS

# --- 1. Fix Prompt ---
PROMPT='%F{cyan}%~%f %F{yellow}%#%f '

# --- 2. Visibility & Completion ---
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' special-dirs true
zstyle ':completion:*' ignore-parents parent pwd
setopt GLOB_DOTS

# --- 3. Horizontal Autocomplete ---
zstyle ':autocomplete:*' list-lines 5
setopt LIST_PACKED

# --- 4. Arrow Keys & ESC to exit menu ---
zmodload zsh/complist
bindkey -M menuselect '\e[A' up-line-or-history
bindkey -M menuselect '\e[B' down-line-or-history
bindkey -M menuselect '\e[C' forward-char
bindkey -M menuselect '\e[D' backward-char
bindkey -M menuselect '\e' send-break

# Accept ghost suggestion with right arrow
if (( \$+widgets[autosuggest-accept] )); then
  bindkey '^[[C' autosuggest-accept
  [[ -n \${terminfo[kcuf1]-} ]] && bindkey "\${terminfo[kcuf1]}" autosuggest-accept
fi

# Ensure Tab enters the menu selection immediately
setopt MENU_COMPLETE
setopt AUTO_PARAM_SLASH
unsetopt AUTO_REMOVE_SLASH

# ${FD_COMMENT}
if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
  alias fd='fdfind'
fi

# Quick parent directory jumps
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
### ${BLOCK_TAG} ZSHRC BLOCK END ###
ZSHRC
fi
chmod 600 /root/.zshrc

# --- 5. Patch .bashrc for Zsh compatibility ---
next_step "Patching /root/.bashrc for Zsh compatibility..."
if [[ -f /root/.bashrc ]]; then
  sed -i 's/^shopt -s histappend$/[[ -n "$BASH_VERSION" ]] \&\& shopt -s histappend/' /root/.bashrc
  sed -i 's/^shopt -s checkwinsize$/[[ -n "$BASH_VERSION" ]] \&\& shopt -s checkwinsize/' /root/.bashrc
fi

# --- 6. Bash login hands off to zsh ---
next_step "Ensuring bash login hands off to zsh..."
BASH_PROFILE=/root/.bash_profile
touch "${BASH_PROFILE}"
if ! grep -q "### ${BLOCK_TAG} HANDOFF START ###" "${BASH_PROFILE}"; then
  cat >> "${BASH_PROFILE}" <<BASHPROFILE
### ${BLOCK_TAG} HANDOFF START ###
if [[ -n "\${PS1:-}" && -z "\${ZSH_VERSION:-}" && -x /usr/bin/zsh ]]; then
  exec /usr/bin/zsh -l
fi
### ${BLOCK_TAG} HANDOFF END ###
BASHPROFILE
fi
chmod 600 "${BASH_PROFILE}"

# --- 7. Set root login shell ---
next_step "Setting root login shell to /usr/bin/zsh..."
if [[ -f /etc/shells ]] && ! grep -qx '/usr/bin/zsh' /etc/shells; then
  echo '/usr/bin/zsh' >> /etc/shells
fi
if command -v usermod >/dev/null 2>&1; then
  usermod -s /usr/bin/zsh root
else
  sed -i 's|^\(root:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:\).*$|\1/usr/bin/zsh|' /etc/passwd
fi

# --- 8. Verify ---
next_step "Verifying setup..."
if [[ ! -x /usr/bin/zsh ]]; then
  echo "ERROR: /usr/bin/zsh is missing after install."
  exit 1
fi
if ! grep -q '^root:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:/usr/bin/zsh$' /etc/passwd; then
  echo "ERROR: root shell was not updated in /etc/passwd."
  exit 1
fi
if ! grep -q "### ${BLOCK_TAG} HANDOFF START ###" /root/.bash_profile; then
  echo "ERROR: /root/.bash_profile zsh handoff block is missing."
  exit 1
fi

echo ""
echo "SUCCESS: Zsh setup complete for ${DISTRO_TYPE}."
echo "Restart Termux / re-login for changes to take effect."
EOF
}
