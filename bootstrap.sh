#!/usr/bin/env bash

set -Eeuo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_BIN="$HOME/.local/bin"

mkdir -p "$LOCAL_BIN"
mkdir -p "$HOME/.config"

export PATH="$LOCAL_BIN:$PATH"

log() {
  printf "\n==> %s\n" "$1"
}

has() {
  command -v "$1" >/dev/null 2>&1
}

OS="$(uname -s)"
ARCH="$(uname -m)"

echo "OS:   $OS"
echo "ARCH: $ARCH"

IS_WSL=false
DISTRO=""

if [[ "$OS" == "Linux" ]]; then
  if grep -qi microsoft /proc/version 2>/dev/null; then
    IS_WSL=true
  fi

  if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    DISTRO="${ID:-unknown}"
  fi
fi

echo "Distro: ${DISTRO:-N/A}"
echo "WSL:    $IS_WSL"

install_debian_packages() {
  log "安装Ubuntu/Debian开发环境工具"

  sudo apt update

  sudo apt install -y \
    build-essential \
    git \
    curl \
    wget \
    unzip \
    zip \
    ca-certificates \
    ripgrep \
    fd-find \
    fzf \
    tmux \
    zsh \
    cmake \
    ninja-build \
    clang \
    clangd \
    clang-format \
    python3 \
    python3-venv \
    python3-pip \
    nodejs \
    npm \
    openjdk-21-jdk \
    jq \
    poppler-utils \
    ffmpeg \
    p7zip-full \
    zoxide

  if has fdfind && ! has fd; then
    ln -sf "$(command -v fdfind)" "$LOCAL_BIN/fd"
  fi
}

install_macos_packages() {
  log "安装macOS开发环境工具"
  if ! has brew; then
    log "Installing Homebrew"

    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    if [[ -x /opt/homebrew/bin/brew ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
      eval "$(/usr/local/bin/brew shellenv)"
    fi
  fi

  brew install \
    git \
    curl \
    wget \
    ripgrep \
    fd \
    fzf \
    tmux \
    zsh \
    cmake \
    ninja \
    llvm \
    python \
    node \
    openjdk@21 \
    jq \
    poppler \
    ffmpeg \
    sevenzip \
    zoxide
  export PATH="$(brew --prefix llvm)/bin:$PATH"
  export PATH="$(brew --prefix openjdk@21)/bin:$PATH"
}

install_neovim() {
  if has nvim; then
    log "Neovim 已安装，跳过"
    return
  fi

  log "安装 Neovim"

  if [[ "$OS" == "Darwin" ]]; then
    brew install neovim
    return
  fi

  local nvim_arch

  case "$ARCH" in
  x86_64)
    nvim_arch="x86_64"
    ;;
  aarch64 | arm64)
    nvim_arch="arm64"
    ;;
  *)
    echo "Unsupported Neovim architecture: $ARCH"
    exit 1
    ;;
  esac

  local tmp
  tmp="$(mktemp -d)"

  curl -fL \
    "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${nvim_arch}.tar.gz" \
    -o "$tmp/nvim.tar.gz"

  sudo rm -rf "/opt/nvim-linux-${nvim_arch}"

  sudo tar \
    -C /opt \
    -xzf "$tmp/nvim.tar.gz"

  ln -sf \
    "/opt/nvim-linux-${nvim_arch}/bin/nvim" \
    "$LOCAL_BIN/nvim"

  rm -rf "$tmp"
}

install_starship() {
  if has starship; then
    log "Starship 已安装，跳过"
    return
  fi

  log "安装 Starship"

  curl -sS https://starship.rs/install.sh |
    sh -s -- -y -b "$LOCAL_BIN"
}

install_yazi() {
  if has yazi; then
    log "Yazi 已安装，跳过"
    return
  fi

  log "安装 Yazi"

  if [[ "$OS" == "Darwin" ]]; then
    brew install yazi
    return
  fi

  curl -fsSL \
    https://yazi-rs.github.io/builds/yazi-keyring.gpg |
    sudo tee /usr/share/keyrings/yazi-keyring.gpg >/dev/null

  echo \
    'deb [signed-by=/usr/share/keyrings/yazi-keyring.gpg] https://yazi-rs.github.io/builds/ stable main' |
    sudo tee /etc/apt/sources.list.d/yazi.list >/dev/null

  sudo apt update
  sudo apt install -y yazi
}

install_uv() {
  if has uv; then
    log "uv 已安装，跳过"
    return
  fi

  log "安装 uv"

  curl -LsSf https://astral.sh/uv/install.sh |
    env UV_INSTALL_DIR="$LOCAL_BIN" sh
}

install_tree_sitter() {
  if has tree-sitter; then
    log "tree-sitter CLI 已安装，跳过"
    return
  fi

  log "安装 tree-sitter CLI"

  local platform

  case "$OS-$ARCH" in
  Linux-x86_64)
    platform="linux-x64"
    ;;
  Linux-aarch64 | Linux-arm64)
    platform="linux-arm64"
    ;;
  Darwin-x86_64)
    platform="macos-x64"
    ;;
  Darwin-arm64 | Darwin-aarch64)
    platform="macos-arm64"
    ;;
  *)
    echo "Unsupported tree-sitter platform: $OS-$ARCH"
    exit 1
    ;;
  esac

  local tmp
  tmp="$(mktemp -d)"

  curl -fL \
    "https://github.com/tree-sitter/tree-sitter/releases/latest/download/tree-sitter-cli-${platform}.zip" \
    -o "$tmp/tree-sitter.zip"

  unzip -q "$tmp/tree-sitter.zip" -d "$tmp"

  install \
    -m 755 \
    "$tmp/tree-sitter" \
    "$LOCAL_BIN/tree-sitter"

  rm -rf "$tmp"
}

link_dotfile() {
  local src="$1"
  local dst="$2"

  mkdir -p "$(dirname "$dst")"

  if [[ -L "$dst" ]] &&
    [[ "$(readlink "$dst")" == "$src" ]]; then
    return
  fi

  if [[ -e "$dst" || -L "$dst" ]]; then
    echo "配置已存在，无法链接: $dst"
    echo "请手动删除后重新运行 bootstrap.sh"
    return 1
  fi

  ln -s "$src" "$dst"
}

link_dotfiles() {
  log "链接 dotfiles"

  link_dotfile \
    "$DOTFILES_DIR/zsh/zshrc" \
    "$HOME/.zshrc"

  link_dotfile \
    "$DOTFILES_DIR/tmux/tmux.conf" \
    "$HOME/.tmux.conf"

  link_dotfile \
    "$DOTFILES_DIR/nvim" \
    "$HOME/.config/nvim"

  link_dotfile \
    "$DOTFILES_DIR/starship/starship.toml" \
    "$HOME/.config/starship.toml"

  link_dotfile \
    "$DOTFILES_DIR/yazi" \
    "$HOME/.config/yazi"
  # Rio: macOS / 原生 Linux
  if [[ "$IS_WSL" == "false" ]]; then
    link_dotfile \
      "$DOTFILES_DIR/rio/config.toml" \
      "$HOME/.config/rio/config.toml"
  fi
}

sync_rio_config_wsl() {
  if [[ "$IS_WSL" != "true" ]]; then
    return
  fi

  log "同步 Rio 配置到 Windows"

  local win_localappdata
  local win_rio_dir

  win_localappdata="$(
    powershell.exe -NoProfile -Command \
      '[Environment]::GetFolderPath("LocalApplicationData")' |
      tr -d '\r'
  )"

  win_rio_dir="$(wslpath "$win_localappdata")/rio"

  mkdir -p "$win_rio_dir"

  cp -f \
    "$DOTFILES_DIR/rio/config.toml" \
    "$win_rio_dir/config.toml"
}

setup_shell() {
  if [[ "$OS" == "Darwin" ]]; then
    return
  fi

  local zsh_path
  zsh_path="$(command -v zsh)"

  if [[ "${SHELL:-}" != "$zsh_path" ]]; then
    log "设置 zsh 为默认 shell"
    chsh -s "$zsh_path"
  fi
}

verify() {
  log "检查开发环境"

  local tools=(
    git
    curl
    zsh
    tmux
    nvim
    rg
    fd
    fzf
    zoxide
    starship
    yazi
    uv
    tree-sitter
    clang
    clangd
    cmake
    ninja
    python3
    node
    java
  )

  local failed=false

  for tool in "${tools[@]}"; do
    if has "$tool"; then
      printf "  [OK] %-15s %s\n" "$tool" "$(command -v "$tool")"
    else
      printf "  [!!] %-15s missing\n" "$tool"
      failed=true
    fi
  done

  if "$failed"; then
    echo
    echo "部分工具安装失败。"
    return 1
  fi

  echo
  echo "开发环境安装完成。"
}

install_rio() {
  log "检查 Rio"

  # --------------------------------------------------
  # macOS
  # --------------------------------------------------
  if [[ "$OS" == "Darwin" ]]; then
    if brew list --cask rio >/dev/null 2>&1; then
      log "Rio 已安装"
    else
      log "安装 Rio (macOS)"
      brew install --cask rio
    fi
    return
  fi

  # --------------------------------------------------
  # WSL
  # Rio 是 Windows GUI 程序，因此安装在 Windows Host
  # --------------------------------------------------
  if grep -qi microsoft /proc/version 2>/dev/null; then
    log "安装 Rio (Windows Host via WSL)"

    if ! command -v powershell.exe >/dev/null 2>&1; then
      log "未找到 powershell.exe，跳过 Rio 安装"
      return
    fi

    if powershell.exe -NoProfile -Command \
      'Get-Command rio -ErrorAction SilentlyContinue' \
      >/dev/null 2>&1; then
      log "Rio 已安装"
    else
      powershell.exe -NoProfile -Command \
        'winget install -e --id raphamorim.rio --accept-package-agreements --accept-source-agreements'
    fi

    return
  fi

  # --------------------------------------------------
  # Debian / Ubuntu Linux
  # --------------------------------------------------
  if [[ "$OS" == "Linux" ]] && command -v apt-get >/dev/null 2>&1; then
    if command -v rio >/dev/null 2>&1; then
      log "Rio 已安装"
      return
    fi

    log "安装 Rio (Debian/Ubuntu)"

    local deb_arch
    local backend
    local asset_url
    local tmp_deb

    case "$(uname -m)" in
    x86_64)
      deb_arch="amd64"
      ;;
    aarch64 | arm64)
      deb_arch="arm64"
      ;;
    *)
      log "Rio 不支持当前架构: $(uname -m)"
      return 1
      ;;
    esac

    if [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
      backend="wayland"
    else
      backend="x11"
    fi

    asset_url="$(
      curl -fsSL \
        https://api.github.com/repos/raphamorim/rio/releases/latest |
        jq -r \
          --arg arch "$deb_arch" \
          --arg backend "$backend" \
          '.assets[]
           | select(.name
             | test("rioterm_.*_" + $arch + "_" + $backend + "\\.deb$"))
           | .browser_download_url' |
        head -n 1
    )"

    if [[ -z "$asset_url" ]]; then
      log "没有找到适合当前系统的 Rio .deb"
      return 1
    fi

    tmp_deb="$(mktemp --suffix=.deb)"

    curl -fL "$asset_url" -o "$tmp_deb"
    sudo apt-get install -y "$tmp_deb"

    rm -f "$tmp_deb"

    # 确保 Rio terminfo 可用
    if ! infocmp rio >/dev/null 2>&1; then
      local terminfo
      terminfo="$(mktemp)"

      curl -fsSL \
        https://raw.githubusercontent.com/raphamorim/rio/main/misc/rio.terminfo \
        -o "$terminfo"

      sudo tic -xe xterm-rio,rio "$terminfo"
      rm -f "$terminfo"
    fi
  fi
}

main() {
  case "$OS" in
  Linux)
    case "$DISTRO" in
    ubuntu | debian)
      install_debian_packages
      ;;
    *)
      echo "Unsupported Linux distro: $DISTRO"
      exit 1
      ;;
    esac
    ;;

  Darwin)
    install_macos_packages
    ;;

  *)
    echo "Unsupported system: $OS"
    exit 1
    ;;
  esac

  install_neovim
  install_starship
  install_yazi
  install_uv
  install_tree_sitter
  install_rio

  link_dotfiles
  sync_rio_config_wsl

  setup_shell
  verify
}

main "$@"
