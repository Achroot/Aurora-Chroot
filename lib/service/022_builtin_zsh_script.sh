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

remove_managed_block() {
  local target_file="$1" block_start="$2" block_end="$3"
  [[ -f "$target_file" ]] || return 0
  grep -qF "$block_start" "$target_file" || return 0

  awk -v start="$block_start" -v end="$block_end" '
    $0 == start { skip=1; next }
    $0 == end { skip=0; next }
    skip != 1 { print }
  ' "$target_file" > "${target_file}.tmp"
  mv "${target_file}.tmp" "$target_file"
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
next_step "Refreshing managed Zsh block in /root/.zshrc..."
touch /root/.zshrc
remove_managed_block /root/.zshrc "### ${BLOCK_TAG} ZSHRC BLOCK START ###" "### ${BLOCK_TAG} ZSHRC BLOCK END ###"
if [[ -s /root/.zshrc ]] && [[ "$(tail -c1 /root/.zshrc 2>/dev/null || true)" != $'\n' ]]; then
  echo >> /root/.zshrc
fi
cat >> /root/.zshrc <<ZSHRC
### ${BLOCK_TAG} ZSHRC BLOCK START ###
# Source aliases and environment from bashrc (if present)
if [[ -f ~/.bashrc ]]; then
  # Minimal shim for common distro bashrc defaults when sourced from Zsh.
  shopt() {
    local mode="\${1:-}" opt=""
    shift || true
    case "\$mode" in
      -s)
        for opt in "\$@"; do
          case "\$opt" in
            histappend) setopt APPEND_HISTORY ;;
            checkwinsize) ;;
          esac
        done
        return 0
        ;;
      -u)
        return 0
        ;;
      -oq)
        [[ "\${1:-}" == "posix" ]] && return 0
        return 1
        ;;
      *)
        return 0
        ;;
    esac
  }
  . ~/.bashrc
  unfunction shopt 2>/dev/null || true
fi

# Plugin: zsh-autocomplete
[[ -f ~/.zsh-autocomplete/zsh-autocomplete.plugin.zsh ]] && source ~/.zsh-autocomplete/zsh-autocomplete.plugin.zsh

# Plugin: zsh-autosuggestions
ZSH_AUTOSUGGEST_STRATEGY=(history)
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=244'
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=50
[[ -f ~/.zsh-autosuggestions/zsh-autosuggestions.zsh ]] && source ~/.zsh-autosuggestions/zsh-autosuggestions.zsh

# Keep history intentionally small
HISTFILE=~/.zsh_history
HISTSIZE=50
SAVEHIST=50
setopt APPEND_HISTORY
setopt HIST_IGNORE_ALL_DUPS
setopt INTERACTIVE_COMMENTS
unsetopt BEEP

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

# Keep Right Arrow on forward-char so autosuggestions work at EOL
# while still allowing normal cursor movement inside the buffer.
bindkey '^[[C' forward-char
bindkey '^[OC' forward-char
[[ -n \${terminfo[kcuf1]-} ]] && bindkey "\${terminfo[kcuf1]}" forward-char

# Common editing key fallbacks across Termux/mobile terminal sequences.
bindkey '^[[H' beginning-of-line
bindkey '^[OH' beginning-of-line
[[ -n \${terminfo[khome]-} ]] && bindkey "\${terminfo[khome]}" beginning-of-line
bindkey '^[[F' end-of-line
bindkey '^[OF' end-of-line
[[ -n \${terminfo[kend]-} ]] && bindkey "\${terminfo[kend]}" end-of-line
[[ -n \${terminfo[kdch1]-} ]] && bindkey "\${terminfo[kdch1]}" delete-char
[[ -n \${terminfo[kbs]-} ]] && bindkey "\${terminfo[kbs]}" backward-delete-char

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
chmod 600 /root/.zshrc

# --- 5. Patch .bashrc for Zsh compatibility ---
next_step "Patching /root/.bashrc for Zsh compatibility..."
if [[ -f /root/.bashrc ]]; then
  sed -i 's/^shopt -s histappend$/[[ -n "$BASH_VERSION" ]] \&\& shopt -s histappend/' /root/.bashrc
  sed -i 's/^shopt -s checkwinsize$/[[ -n "$BASH_VERSION" ]] \&\& shopt -s checkwinsize/' /root/.bashrc
fi

# --- 6. Direct zsh login profile ---
next_step "Updating Zsh login profile and removing legacy bash handoff..."
ZPROFILE=/root/.zprofile
touch "${ZPROFILE}"
remove_managed_block "${ZPROFILE}" "### ${BLOCK_TAG} ZPROFILE BLOCK START ###" "### ${BLOCK_TAG} ZPROFILE BLOCK END ###"
if [[ -s "${ZPROFILE}" ]] && [[ "$(tail -c1 "${ZPROFILE}" 2>/dev/null || true)" != $'\n' ]]; then
  echo >> "${ZPROFILE}"
fi
cat >> "${ZPROFILE}" <<ZPROFILE
### ${BLOCK_TAG} ZPROFILE BLOCK START ###
# Keep common per-user executables available in Zsh login shells.
if [[ -d "\$HOME/.local/bin" ]]; then
  case ":\$PATH:" in
    *":\$HOME/.local/bin:"*) ;;
    *) export PATH="\$HOME/.local/bin:\$PATH" ;;
  esac
fi
### ${BLOCK_TAG} ZPROFILE BLOCK END ###
ZPROFILE
chmod 600 "${ZPROFILE}"

BASH_PROFILE=/root/.bash_profile
if [[ -f "${BASH_PROFILE}" ]] && grep -q "### ${BLOCK_TAG} HANDOFF START ###" "${BASH_PROFILE}"; then
  awk -v start="### ${BLOCK_TAG} HANDOFF START ###" -v end="### ${BLOCK_TAG} HANDOFF END ###" '
    $0 == start { skip=1; next }
    $0 == end { skip=0; next }
    skip != 1 { print }
  ' "${BASH_PROFILE}" > "${BASH_PROFILE}.tmp"
  mv "${BASH_PROFILE}.tmp" "${BASH_PROFILE}"
fi
[[ -f "${BASH_PROFILE}" ]] && chmod 600 "${BASH_PROFILE}"

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
if ! grep -q "### ${BLOCK_TAG} ZPROFILE BLOCK START ###" /root/.zprofile; then
  echo "ERROR: /root/.zprofile managed block is missing."
  exit 1
fi
if [[ -f /root/.bash_profile ]] && grep -q "### ${BLOCK_TAG} HANDOFF START ###" /root/.bash_profile; then
  echo "ERROR: legacy /root/.bash_profile handoff block is still present."
  exit 1
fi

echo ""
echo "SUCCESS: Zsh setup complete for ${DISTRO_TYPE}."
echo "Restart Termux / re-login for changes to take effect."
EOF
}
