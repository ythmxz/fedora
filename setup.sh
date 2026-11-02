#!/usr/bin/env bash

# ==============================================================================
# Script de Configuração Pós-Instalação - Fedora Everything
# ==============================================================================

set -eo pipefail

# 1. Checagens Iniciais e Credenciais
# ------------------------------------------------------------------------------
if [ "$EUID" -eq 0 ]; then
    echo "Erro: Não execute este script como root ou sudo!"
    echo "Execute como usuário normal: ./setup.sh"
    exit 1
fi

echo "==> Solicitando credenciais sudo..."
sudo -v

# Mantém o sudo ativo em background enquanto o script rodar
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_KEEP_ALIVE_PID=$!
trap 'kill "$SUDO_KEEP_ALIVE_PID" 2>/dev/null || true' EXIT

# 2. Criação dos Diretórios do Usuário (incluindo Projects)
# ------------------------------------------------------------------------------
echo "==> Configurando diretórios padrão do usuário..."
sudo dnf install -y xdg-user-dirs
xdg-user-dirs-update
mkdir -p "$HOME/Projects"

# 3. Otimização do DNF
# ------------------------------------------------------------------------------
echo "==> Configurando otimizações do DNF..."
sudo mkdir -p /etc/dnf
sudo tee /etc/dnf/dnf.conf > /dev/null << 'EOF'
[main]
defaultyes=True
max_parallel_downloads=10
skip_unavailable=True
fastestmirror=True
EOF

echo "==> Atualizando repositórios e sistema..."
sudo dnf update -y --refresh

# 4. Repositórios Extras e Codecs Multimídia
# ------------------------------------------------------------------------------
echo "==> Habilitando RPM Fusion e repositórios de codecs..."
sudo dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"

sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1
sudo dnf install -y rpmfusion-\*-appstream-data

echo "==> Configurando codecs e aceleração de vídeo..."
sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
sudo dnf install -y @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
sudo dnf install -y mesa-va-drivers-freeworld

# 5. Habilitação de Repositórios de Terceiros e COPRs
# ------------------------------------------------------------------------------
echo "==> Configurando repositórios de terceiros (Docker, COPR, ArtCraft)..."

# Repositório Oficial do Docker
sudo dnf config-manager addrepo --from-repofile https://download.docker.com/linux/fedora/docker-ce.repo

# ArtCraft
sudo dnf config-manager addrepo --from-repofile=https://getartcraft.com/rpm/artcraft.repo

# COPRs
sudo dnf copr enable -y lihaohong/yazi
sudo dnf copr enable -y imput/helium

# 6. Listas de Pacotes do Sistema (DNF)
# ------------------------------------------------------------------------------
echo "==> Definindo pacotes para instalação..."

PACKAGES_BASE=(
    # Conectividade e Rede
    NetworkManager-wifi
    wget
    bind-utils
    tailscale
    syncthing

    # Hardware e Armazenamento
    pciutils
    usbutils
    dosfstools
    lsof
    timeshift

    # Utilitários de Arquivos e Sistema
    unzip
    zip
    tar
    zstd
    git
    jq
    duf
    gh
)

PACKAGES_DEV=(
    # C / C++
    gcc
    gcc-c++
    clang
    clang-tools-extra
    gdb
    cmake
    make
    ninja-build
    pkgconf-pkg-config

    # Python
    python3-devel
    python3-pip
    pipx

    # Java (OpenJDK)
    java-latest-openjdk-devel

    # Lua
    lua
    luarocks

    # Web Development (Node.js & pnpm)
    nodejs
    npm
    pnpm

    # Banco de Dados (PostgreSQL)
    postgresql-server
    postgresql-contrib

    # Docker
    docker-ce
    docker-ce-cli
    containerd.io
    docker-buildx-plugin
    docker-compose-plugin
)

PACKAGES_CLI=(
    zsh
    nano
    zoxide
    fzf
    ripgrep
    eza
    bat
    stow
    fastfetch
    tldr
    fd-find
    helix
    pass
    cmatrix
    cbonsai
    cava
    yazi
)

PACKAGES_DESKTOP=(
    # Áudio, Vídeo e Imagem
    vlc
    obs-studio
    loupe
    snapshot
    gnome-calculator
    gnome-font-viewer

    # Jogos e Emulação
    steam
    retroarch

    # Utilitários de Desktop
    papirus-icon-theme
    qbittorrent
    kdeconnectd
    adw-gtk3-theme
    qt6ct
    flatpak

    # Fontes
    jetbrains-mono-fonts-all
    jetbrainsmono-nerd-fonts

    # Softwares de repositórios adicionados
    artcraft-launcher
    helium-bin
)

echo "==> Instalando pacotes DNF agrupados..."
sudo dnf install -y \
    "${PACKAGES_BASE[@]}" \
    "${PACKAGES_DEV[@]}" \
    "${PACKAGES_CLI[@]}" \
    "${PACKAGES_DESKTOP[@]}"

# 7. RPMs Externos Diretos
# ------------------------------------------------------------------------------
echo "==> Instalando pacotes RPM externos..."

# Vesktop
sudo dnf install -y https://vencord.dev/download/vesktop/amd64/rpm

# DBeaver Community
sudo dnf install -y https://dbeaver.io/files/dbeaver-ce-latest-stable.x86_64.rpm

# GodotHub (busca da release mais recente do GitHub)
echo "Baixando e instalando GodotHub..."
GODOTHUB_RPM_URL=$(curl -s https://api.github.com/repos/RykoTheDev/GodotHub/releases/latest \
    | grep "browser_download_url.*linux-x86_64\.rpm" \
    | cut -d '"' -f 4 || true)

if [ -n "$GODOTHUB_RPM_URL" ]; then
    sudo dnf install -y "$GODOTHUB_RPM_URL"
else
    echo "Aviso: Não foi possível obter o RPM do GodotHub automaticamente."
fi

# 8. Pós-Instalação: Serviços, Shell e Cache do Sistema
# ------------------------------------------------------------------------------
echo "==> Executando configurações pós-instalação de serviços e sistema..."

# Docker: habilita o serviço e adiciona usuário ao grupo
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"

# PostgreSQL: inicializa o cluster de banco de dados e habilita o serviço
if [ ! -f /var/lib/pgsql/data/PG_VERSION ]; then
    echo "Inicializando cluster do PostgreSQL..."
    sudo postgresql-setup --initdb
fi
sudo systemctl enable --now postgresql

# Tailscale: habilita o daemon
sudo systemctl enable tailscaled.service

# Zsh: define como shell padrão caso ainda não seja
ZSH_PATH=$(which zsh || true)
if [ -n "$ZSH_PATH" ] && [ "$SHELL" != "$ZSH_PATH" ]; then
    echo "Definindo Zsh como shell padrão para o usuário $USER..."
    sudo chsh -s "$ZSH_PATH" "$USER"
fi

# Configuração do Git
echo "==> Configurando Git..."
git config --global init.defaultBranch main

CURRENT_GIT_NAME=$(git config --global user.name || true)
CURRENT_GIT_EMAIL=$(git config --global user.email || true)

# Lê de /dev/tty para funcionar mesmo se o script for executado via curl | bash
if [ -e /dev/tty ]; then
    if [ -z "$CURRENT_GIT_NAME" ]; then
        read -r -p "Digite seu nome para o Git (ou pressione Enter para pular): " INPUT_GIT_NAME </dev/tty
        if [ -n "$INPUT_GIT_NAME" ]; then
            git config --global user.name "$INPUT_GIT_NAME"
        fi
    fi

    if [ -z "$CURRENT_GIT_EMAIL" ]; then
        read -r -p "Digite seu e-mail para o Git (ou pressione Enter para pular): " INPUT_GIT_EMAIL </dev/tty
        if [ -n "$INPUT_GIT_EMAIL" ]; then
            git config --global user.email "$INPUT_GIT_EMAIL"
        fi
    fi
fi

# Criação e inicialização de configurações de CLI (Fastfetch, Helix, Yazi)
echo "==> Inicializando diretórios e arquivos de configuração em ~/.config..."

# Fastfetch: gera config.jsonc oficial caso não exista
if command -v fastfetch &>/dev/null && [ ! -f "$HOME/.config/fastfetch/config.jsonc" ]; then
    echo "Gerando configuração padrão do Fastfetch..."
    fastfetch --gen-config
fi

# Helix
mkdir -p "$HOME/.config/helix"
if [ ! -f "$HOME/.config/helix/config.toml" ]; then
    touch "$HOME/.config/helix/config.toml"
fi

# Yazi
mkdir -p "$HOME/.config/yazi"
if [ ! -f "$HOME/.config/yazi/yazi.toml" ]; then
    touch "$HOME/.config/yazi/yazi.toml"
fi

# Starship
if [ ! -f "$HOME/.config/starship.toml" ]; then
    touch "$HOME/.config/starship.toml"
fi

# Instalação do Tema de Cursores Notwaita (extraído para /usr/share/icons)
echo "==> Baixando e instalando pacote de cursores Notwaita..."
NOTWAITA_URL=$(curl -s https://api.github.com/repos/ful1e5/notwaita-cursor/releases/latest \
    | grep "browser_download_url.*Notwaita\.tar\.xz" \
    | cut -d '"' -f 4 || true)

if [ -n "$NOTWAITA_URL" ]; then
    sudo mkdir -p /usr/share/icons
    curl -fL "$NOTWAITA_URL" | sudo tar -xJf - -C /usr/share/icons
else
    echo "Aviso: Não foi possível baixar o pacote de cursores Notwaita."
fi

# Atualiza cache de fontes para JetBrains Mono e Nerd Font ficarem prontas
fc-cache -f

# 9. Instaladores de Linguagens e Ferramentas (User-level)
# ------------------------------------------------------------------------------
echo "==> Instalando Rust (via rustup modo não-interativo)..."
if ! command -v rustup &>/dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi

echo "==> Instalando Starship Prompt..."
curl -sS https://starship.rs/install.sh | sh -s -- --yes

echo "==> Instalando Zed Editor..."
curl -f https://zed.dev/install.sh | sh

# 10. Flatpaks
# ------------------------------------------------------------------------------
echo "==> Configurando Flatpak e Flathub..."
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

echo "==> Instalando aplicativos Flatpak..."
flatpak install -y flathub com.spotify.Client
flatpak install -y flathub com.getpostman.Postman

# 11. AppImages (AppManager primeiro com execução; demais para gerenciamento)
# ------------------------------------------------------------------------------
echo "==> Baixando AppImages para ~/Applications..."
APPIMAGE_DIR="$HOME/Applications"
mkdir -p "$APPIMAGE_DIR"

# 1º: AppManager (único que recebe permissão de execução diretamente pelo script)
echo "Baixando AppManager..."
APPMANAGER_URL=$(curl -s https://api.github.com/repos/kem-a/AppManager/releases/latest \
    | grep "browser_download_url.*anylinux-x86_64\.AppImage" \
    | cut -d '"' -f 4 || true)
if [ -n "$APPMANAGER_URL" ]; then
    curl -fL "$APPMANAGER_URL" -o "$APPIMAGE_DIR/AppManager.AppImage"
    chmod +x "$APPIMAGE_DIR/AppManager.AppImage"
fi

# 2º: Zen Browser (sem chmod +x, instalado/gerenciado via AppManager)
echo "Baixando Zen Browser..."
curl -fL "https://github.com/zen-browser/desktop/releases/latest/download/zen-x86_64.AppImage" \
    -o "$APPIMAGE_DIR/zen.AppImage"

# 3º: Obsidian (sem chmod +x, instalado/gerenciado via AppManager)
echo "Baixando Obsidian..."
OBSIDIAN_URL=$(curl -s https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest \
    | grep "browser_download_url.*Obsidian-.*\.AppImage" \
    | grep -v "arm64" \
    | head -n 1 \
    | cut -d '"' -f 4 || true)
if [ -n "$OBSIDIAN_URL" ]; then
    curl -fL "$OBSIDIAN_URL" -o "$APPIMAGE_DIR/Obsidian.AppImage"
fi

# 12. Customizações Finais do Ambiente (Dux)
# ------------------------------------------------------------------------------
echo "==> Instalando Dux..."
curl -fsSL https://install.duxlabs.dev | sh -s -- -c niri -t ghostty --all-features -y

echo "=============================================================================="
echo "Configuração concluída com sucesso!"
echo "Recomenda-se reiniciar o sistema para aplicar todas as mudanças (grupos e shell)."
echo "=============================================================================="
