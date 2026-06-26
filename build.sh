#!/bin/bash

# Si l'utilisateur a oublié de mettre sudo, on redémarre le script avec sudo
if [ "$EUID" -ne 0 ]; then
    echo "Le build nécessite les droits administrateur (sudo). Redémarrage..."
    exec sudo bash "$0" "$@"
fi

set -e

ISO_NAME="arch-custom-iso"
# On récupère le nom de l'utilisateur normal (pas root) pour makepkg
BUILD_USER="${SUDO_USER:-root}"

# ==============================================================================
# LES LISTES DE PAQUETS
# ==============================================================================
EXTRA_PACKAGES=(
    "neovim" "ghostty" "hyprland" "xdg-desktop-portal-hyprland" 
    "git" "yazi" "dolphin" "rofi" "waybar" "wiremix" "impala" 
    "bluetui" "btop" "cava" "fastfetch" "obsidian" "obs-studio" 
    "lazygit" "docker" "docker-buildx" "docker-compose" "lazydocker" 
    "mpv" "prismlauncher" "rust" "chromium" "bat" "base-devel" 
    "cmake" "nodejs" "npm" "pnpm" "python" "python-pip" 
    "curl" "wget" "unzip"
)

AUR_PACKAGES=(
    "visual-studio-code-bin"
    "subtui-bin"
    "localsend-bin"
)

# ==============================================================================
# PROCESSUS DE BUILD
# ==============================================================================

echo "====================================="
echo "   Building Arch Linux ISO"
echo "   Project: $ISO_NAME"
echo "   Build lancé par l'utilisateur: $BUILD_USER"
echo "====================================="

if ! command -v mkarchiso &> /dev/null; then
    echo "[ERROR] archiso is not installed"
    echo "Run: sudo pacman -S archiso"
    exit 1
fi

echo "[1/5] Cleaning previous build..."
rm -rf work out offline_cache

# --- TÉLÉCHARGEMENT DES PAQUETS OFFICIELS ---
echo "[2/5] Downloading Official Packages for offline cache..."
# On utilise /tmp pour éviter tout problème de permissions dans le Home
TMP_CACHE="/tmp/archiso_cache_$$"
mkdir -p "$TMP_CACHE"
sudo pacman -Sy --noconfirm

# On télécharge (-w) sans installer, dans le dossier temporaire
sudo pacman -Sw --noconfirm --cachedir "$TMP_CACHE" "${EXTRA_PACKAGES[@]}" || true

# On crée le vrai dossier de cache et on déplace les paquets
mkdir -p offline_cache
cp "$TMP_CACHE"/*.pkg.tar.zst offline_cache/ 2>/dev/null || true
rm -rf "$TMP_CACHE"

# --- COMPILATION DES PAQUETS AUR ---
echo "[3/5] Building AUR Packages for offline cache..."
mkdir -p aur_build

for pkg in "${AUR_PACKAGES[@]}"; do
    echo " -> Building AUR package: $pkg"
    cd aur_build
    rm -rf "$pkg"
    git clone "https://aur.archlinux.org/${pkg}.git" --depth 1 
    
    # CRUCIAL : On donne les droits à l'utilisateur NORMAL pour que makepkg accepte de tourner
    chown -R "$BUILD_USER":"$BUILD_USER" "$pkg"
    cd "$pkg"
    
    # CRUCIAL : On lance makepkg EN TANT QU'UTILISATEUR NORMAL (pas de -s pour éviter de reboucler sur sudo)
    sudo -u "$BUILD_USER" makepkg -d -f --noconfirm --needed
    
    # On déplace le paquet compilé dans notre cache
    mv *.pkg.tar.zst ../../offline_cache/
    cd ../..
done
rm -rf aur_build

# --- INJECTION DANS L'ISO ---
echo "[4/5] Injecting offline cache into ISO skeleton..."
mkdir -p airootfs/root/offline_cache
cp offline_cache/*.pkg.tar.zst airootfs/root/offline_cache/
rm -rf offline_cache

# --- CRÉATION DE L'ISO ---
echo "[5/5] Building ISO (this will take a while)..."
sudo mkarchiso -v .

if [ -f out/*.iso ]; then
    echo ""
    echo "====================================="
    echo "   Build successful!"
    echo "   ISO located in: out/"
    echo "====================================="
else
    echo "[ERROR] ISO not found in out/"
    exit 1
fi