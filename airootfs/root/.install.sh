#!/usr/bin/env bash
set -euo pipefail

# ==========================================
# UI SYSTEM
# ==========================================
declare -A GRID_DATA
GRID_NUM_PAGES=0

grid_menu() {
    local -n items=$1        
    local page=$2            
    local max_cols=$3
    local max_rows=$4
    local data_page=0
    local item_number=0
    local max_cols_data
    local line

    GRID_DATA=()
    GRID_NUM_PAGES=0

    while (( item_number < ${#items[@]} )); do
        max_cols_data=1
        for (( line=0; line<max_rows; line++ )); do
            if (( item_number >= ${#items[@]} )); then break; fi
            local key="P${data_page}L${line}"
            if [[ ! -v GRID_DATA[$key] ]]; then GRID_DATA[$key]=""; fi

            local index=$(( item_number + max_rows - line ))
            if (( index >= ${#items[@]} )); then index=$(( ${#items[@]} - 1 ))
            elif (( index < 0 )); then index=$(( ${#items[@]} + index ))
                (( index < 0 )) && index=0
            fi

            local index_str; printf -v index_str "%d" "$index"
            local item_num_plus1=$(( item_number + 1 ))
            local item_num_str; printf -v item_num_str "%d" "$item_num_plus1"
            local spaces_needed=$(( ${#index_str} - ${#item_num_str} ))
            if (( spaces_needed < 0 )); then spaces_needed=0; fi
            local spaces; printf -v spaces "%*s" "$spaces_needed" ""
            local item="${items[$item_number]}"
            local add="${spaces}${item_num_plus1}) ${item}"

            local current_line="${GRID_DATA[$key]}"
            if (( ${#current_line} + ${#add} > max_cols )); then
                data_page=$(( data_page + 1 ))
                break
            fi
            GRID_DATA[$key]="${current_line}${add}"
            local len_item_plus2=$(( ${#item} + 2 ))
            max_cols_data=$(( max_cols_data > len_item_plus2 ? max_cols_data : len_item_plus2 ))
            item_number=$(( item_number + 1 ))
        done

        for (( line=0; line<max_rows; line++ )); do
            local key="P${data_page}L${line}"
            if [[ ! -v GRID_DATA[$key] ]]; then continue; fi
            local idx=$(( item_number - (max_rows - line) ))
            if (( idx < 0 )); then idx=$(( ${#items[@]} + idx ))
                (( idx < 0 )) && idx=0
            elif (( idx >= ${#items[@]} )); then idx=$(( ${#items[@]} - 1 ))
            fi
            local item="${items[$idx]}"
            local pad=$(( max_cols_data - ${#item} ))
            if (( pad < 0 )); then pad=0; fi
            local spaces_pad; printf -v spaces_pad "%*s" "$pad" ""
            GRID_DATA[$key]="${GRID_DATA[$key]}${spaces_pad}"
        done
    done
    GRID_NUM_PAGES=$(( data_page + 1 ))
}

print_grid_menu() {
    local page=$1
    local found=0
    local key
    for key in "${!GRID_DATA[@]}"; do
        if [[ $key == P${page}L* ]]; then found=1; break; fi
    done
    if (( found == 0 )); then echo "Page $(( page + 1 )) does not exist."; return; fi

    echo ""
    echo "Page $(( page + 1 )) of $GRID_NUM_PAGES"
    echo ""
    for key in $(printf "%s\n" "${!GRID_DATA[@]}" | grep "^P${page}L" | sort -t 'L' -k2 -n); do
        echo "${GRID_DATA[$key]}"
    done
}

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

# ==========================================
# SYSTEM LOGIC
# ==========================================

cleanup_install_disk() {
    local disk="$1"
    [[ -z "$disk" || ! -b "$disk" ]] && return 1
    echo "Cleaning up disk: $disk"
    findmnt -R /mnt >/dev/null && umount -R /mnt || true
    while read -r dev; do
        [[ -b "$dev" ]] || continue
        swapoff "$dev" 2>/dev/null || true
        while read -r target; do [[ -n "$target" ]] && umount "$target" 2>/dev/null; done < <(findmnt -rn -S "$dev" -o TARGET 2>/dev/null)
    done < <(lsblk -rnpo PATH "$disk" 2>/dev/null)
    while read -r dev type; do
        [[ "$type" == "disk" || "$type" == "part" || "$type" == "crypt" ]] || continue
        while read -r vg; do [[ -n "$vg" ]] && vgchange -an "$vg" 2>/dev/null; done < <(pvs --noheadings -o vg_name "$dev" 2>/dev/null | awk '{$1=$1; print}' | sort -u)
    done < <(lsblk -rnpo PATH,TYPE "$disk" 2>/dev/null)
    while read -r dev type; do [[ "$type" == "crypt" ]] && cryptsetup close "$dev" 2>/dev/null; done < <(lsblk -rnpo PATH,TYPE "$disk" 2>/dev/null)
    blockdev --flushbufs "$disk" 2>/dev/null || true
    partprobe "$disk" 2>/dev/null || true
    udevadm settle 2>/dev/null || true
}

install_base_system() {
    pacman-key --init
    pacman-key --populate archlinux
    pacman -Sy --noconfirm

    local disk
    disk=$(grep -o '"device": *"[^"]*"' user_configuration.json | head -1 | cut -d'"' -f4)
    cleanup_install_disk "$disk"

    archinstall --config user_configuration.json --creds user_credentials.json --silent --skip-ntp --skip-wkd --skip-wifi-check

    mkdir -p /mnt/etc/sudoers.d
    echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > /mnt/etc/sudoers.d/99-installer
    chmod 440 /mnt/etc/sudoers.d/99-installer
}

# ==========================================
# CONFIGURATOR
# ==========================================

run_configurator() {
    # --- 1. KEYBOARD ---
    KB_LAYOUT=("us" "fr" "de" "uk" "es" "it" "pt-latin1" "br-abnt2" "dvorak" "colemak" "ru" "jp106")
    PAGE=1
    COLS=$(( $(tput cols) - 10 ))
    ROWS=$(( $(tput lines) - 10 ))

    grid_menu KB_LAYOUT "$PAGE" "$COLS" "$ROWS"

    while true; do
        clear
        echo "=== SELECT KEYBOARD LAYOUT ==="
        print_grid_menu $(( PAGE - 1 ))
        echo -e "\n[n] Next | [p] Prev | [q] Quit"
        read -rp "Entrée (n/p ou nombre) : " input

        if [[ "$input" == "q" ]]; then exit 1; fi
        if [[ "$input" =~ ^[0-9]+$ ]]; then
            PAGE="$input"
            break
        elif [[ "$input" == "n" ]]; then
            if (( PAGE < GRID_NUM_PAGES )); then PAGE=$(( PAGE + 1 )); fi
        elif [[ "$input" == "p" ]]; then
            if (( PAGE > 1 )); then PAGE=$(( PAGE - 1 )); fi
        fi
    done
    keyboard="${KB_LAYOUT[$((PAGE - 1))]}"
    [[ $(tty 2>/dev/null) == "/dev/tty"* ]] && loadkeys "$keyboard" 2>/dev/null || true

    # --- 2. USER ---
    while true; do
        clear; read -rp "Username: " username
        [[ "$username" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] && break
    done
    while true; do
        clear; read -rsp "Password: " password; echo
        read -rsp "Confirm: " password_confirmation; echo
        [[ -n "$password" && "$password" == "$password_confirmation" ]] && break
    done
    password_hash=$(printf '%s' "$password" | openssl passwd -6 -stdin)
    clear; read -rp "Hostname [archlinux]: " hostname
    [[ -z "$hostname" ]] && hostname="archlinux"

    # --- 3. TIMEZONE ---
    clear; echo "Loading timezones..."
    mapfile -t TIMEZONES < <(timedatectl list-timezones)
    PAGE=1
    COLS=$(( $(tput cols) - 10 ))
    ROWS=$(( $(tput lines) - 10 ))

    grid_menu TIMEZONES "$PAGE" "$COLS" "$ROWS"

    while true; do
        clear
        echo "=== SELECT TIMEZONE ==="
        print_grid_menu $(( PAGE - 1 ))
        echo -e "\n[n] Next | [p] Prev | [q] Quit"
        read -rp "Entrée (n/p ou nombre) : " input

        if [[ "$input" == "q" ]]; then exit 1; fi
        if [[ "$input" =~ ^[0-9]+$ ]]; then
            PAGE="$input"
            break
        elif [[ "$input" == "n" ]]; then
            if (( PAGE < GRID_NUM_PAGES )); then PAGE=$(( PAGE + 1 )); fi
        elif [[ "$input" == "p" ]]; then
            if (( PAGE > 1 )); then PAGE=$(( PAGE - 1 )); fi
        fi
    done
    timezone="${TIMEZONES[$((PAGE - 1))]}"

    # --- 4. DISK ---
    clear
    local boot_source exclude_disk
    boot_source=$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null || true)
    local device_b
    device_b=$(readlink -f "$boot_source" 2>/dev/null || echo "")
    while [[ -n "$device_b" ]]; do
        local parent_b
        parent_b=$(lsblk -dno PKNAME "$device_b" 2>/dev/null | tail -n1)
        [[ -z "$parent_b" ]] && break; device_b="/dev/$parent_b"
    done
    [[ $(lsblk -dno TYPE "$device_b" 2>/dev/null) == "disk" ]] && exclude_disk="$device_b"

    DISKS=()
    mapfile -t available_disks < <(lsblk -dpno NAME,TYPE | awk '$2=="disk"{print $1}' | grep -E '/dev/(sd|hd|vd|nvme|mmcblk|xv)' | { [[ -n "${exclude_disk:-}" ]] && grep -Fvx "$exclude_disk" || cat; })
    for dev in "${available_disks[@]}"; do
        local size; size=$(lsblk -dno SIZE "$dev" 2>/dev/null) || true
        local model; model=$(lsblk -dno MODEL "$dev" 2>/dev/null | sed 's/ *$//') || true
        DISKS+=("$dev ($size) - $model")
    done

    PAGE=1
    COLS=$(( $(tput cols) - 10 ))
    ROWS=$(( $(tput lines) - 10 ))

    grid_menu DISKS "$PAGE" "$COLS" "$ROWS"

    while true; do
        clear
        echo "=== SELECT INSTALLATION DISK ==="
        print_grid_menu $(( PAGE - 1 ))
        echo -e "\n[n] Next | [p] Prev | [q] Quit"
        read -rp "Entrée (n/p ou nombre) : " input

        if [[ "$input" == "q" ]]; then exit 1; fi
        if [[ "$input" =~ ^[0-9]+$ ]]; then
            PAGE="$input"
            break
        elif [[ "$input" == "n" ]]; then
            if (( PAGE < GRID_NUM_PAGES )); then PAGE=$(( PAGE + 1 )); fi
        elif [[ "$input" == "p" ]]; then
            if (( PAGE > 1 )); then PAGE=$(( PAGE - 1 )); fi
        fi
    done
    disk=$(echo "${DISKS[$((PAGE - 1))]}" | awk '{print $1}')

    # --- 5. JSON GENERATION ---
    local pw_esc="\"$(json_escape "$password")\""
    local hash_esc="\"$(json_escape "$password_hash")\""
    local user_esc="\"$(json_escape "$username")\""
    local host_esc="\"$(json_escape "$hostname")\""
    local tz_esc="\"$(json_escape "$timezone")\""
    local kb_esc="\"$(json_escape "$keyboard")\""
    local disk_esc="\"$(json_escape "$disk")\""

    credentials_encryption_line=" \"encryption_password\": $pw_esc,"

    cat <<_EOF_ >user_credentials.json
{
 $credentials_encryption_line
"root_enc_password": $hash_esc,
"users": [
{
"enc_password": $hash_esc,
"groups": [],
"sudo": true,
"username": $user_esc
}
]
}
_EOF_

    local disk_size; disk_size=$(lsblk -bdno SIZE "$disk" 2>/dev/null) || true
    local mib=$((1024*1024))
    local gib=$((mib*1024))
    local disk_size_in_mib=$((disk_size / mib * mib))
    local boot_size=$((2 * gib))
    local main_start=$((boot_size + mib))
    local main_size=$((disk_size_in_mib - main_start - mib))

    disk_encryption_config=$(cat <<_EOF_
,
"disk_encryption": {
"encryption_type": "luks",
"lvm_volumes": [],
"iter_time": 2000,
"partitions": [ "8c2c2b92-1070-455d-b76a-56263bab24aa" ],
"encryption_password": $pw_esc
}
_EOF_
)

    cat <<_EOF_ >user_configuration.json
{
"archinstall-language": "English",
"audio_config": { "audio": "pipewire" },
"bootloader": "grub",
"disk_config": {
"btrfs_options": { "snapshot_config": { "type": "Snapper" } },
"config_type": "default_layout",
"device_modifications": [
{
"device": $disk_esc,
"partitions": [
{
"btrfs": [],
"dev_path": null,
"flags": [ "boot", "esp" ],
"fs_type": "fat32",
"mount_options": [],
"mountpoint": "/boot",
"obj_id": "ea21d3f2-82bb-49cc-ab5d-6f81ae94e18d",
"size": {
"sector_size": { "unit": "B", "value": 512 },
"unit": "B",
"value": $boot_size
},
"start": {
"sector_size": { "unit": "B", "value": 512 },
"unit": "B",
"value": $mib
},
"status": "create",
"type": "primary"
},
{
"btrfs": [
{ "mountpoint": "/", "name": "@" },
{ "mountpoint": "/home", "name": "@home" },
{ "mountpoint": "/var/log", "name": "@log" },
{ "mountpoint": "/var/cache/pacman/pkg", "name": "@pkg" }
],
"dev_path": null,
"flags": [],
"fs_type": "btrfs",
"mount_options": [ "compress=zstd" ],
"mountpoint": null,
"obj_id": "8c2c2b92-1070-455d-b76a-56263bab24aa",
"size": {
"sector_size": { "unit": "B", "value": 512 },
"unit": "B",
"value": $main_size
},
"start": {
"sector_size": { "unit": "B", "value": 512 },
"unit": "B",
"value": $main_start
},
"status": "create",
"type": "primary"
}
],
"wipe": true
}
]$disk_encryption_config
},
"hostname": $host_esc,
"kernels": [ "linux" ],
"network_config": { "type": "iso" },
"ntp": true,
"parallel_downloads": 8,
"swap": true,
"timezone": $tz_esc,
"locale_config": {
"kb_layout": $kb_esc,
"sys_enc": "UTF-8",
"sys_lang": "fr_FR.UTF-8"
},
"mirror_config": {
"custom_servers": [
{"url": "https://geo.mirror.pkgbuild.com/\$repo/os/\$arch"},
{"url": "https://mirror.rackspace.com/archlinux/\$repo/os/\$arch"}
]
},
"packages": [
"base-devel",
"git",
"snapper"
],
"profile_config": {
"gfx_driver": null,
"greeter": null,
"profile": {}
},
"version": "3.0.9"
}
_EOF_
}

# ==========================================
# MAIN
# ==========================================

if [[ $(tty) == "/dev/tty1" ]]; then
    run_configurator
    clear
    echo "Installing base system..."
    install_base_system
    
    # --- 0. CONFIGURATION HORS-LIGNE ---
    ISO_CACHE="/root/offline_cache"
    # On monte le cache dans un dossier à part pour ne pas saturer la RAM
    CHROOT_OFFLINE_DIR="/mnt/opt/offline_cache"
    
    if [[ -d "$ISO_CACHE" && -n "$(ls -A $ISO_CACHE/*.pkg.tar.zst 2>/dev/null)" ]]; then
        echo ">>> Mode HORS-LIGNE activé : Utilisation du cache de l'ISO"
        mkdir -p "$CHROOT_OFFLINE_DIR"
        mount --bind "$ISO_CACHE" "$CHROOT_OFFLINE_DIR"
    else
        echo ">>> Mode EN-LIGNE : Cache de l'ISO non trouvé, téléchargement depuis internet."
    fi

    # --- 1. INSTALLATION PACKAGES OFFICIELS ---
    clear
    echo "Installing packages (Offline or Online)..."
    
    EXTRA_PACKAGES=(
        "neovim" "ghostty" "hyprland" "xdg-desktop-portal-hyprland" 
        "git" "yazi" "dolphin" "rofi" "waybar" "wiremix" "impala" 
        "bluetui" "btop" "cava" "fastfetch" "obsidian" "obs-studio" 
        "lazygit" "docker" "docker-buildx" "docker-compose" "lazydocker" 
        "mpv" "prismlauncher" "rust" "chromium" "bat" "base-devel" 
        "cmake" "nodejs" "npm" "pnpm" "python" "python-pip" 
        "curl" "wget" "unzip"
    )
    
    # On dit à pacman d'utiliser le disque dur pour écrire, et le dossier /opt/offline_cache pour LIRE les paquets pré-téléchargés
    if [[ -d "$CHROOT_OFFLINE_DIR" ]]; then
        arch-chroot /mnt pacman -S --noconfirm --cachedir /var/cache/pacman/pkg --cachedir /opt/offline_cache "${EXTRA_PACKAGES[@]}"
    else
        arch-chroot /mnt pacman -S --noconfirm "${EXTRA_PACKAGES[@]}"
    fi
    
    # --- 2. INSTALLATION PACKAGES AUR (HORS-LIGNE) ---
    clear
    echo "Installing pre-compiled AUR packages..."
    for pkg in visual-studio-code-bin subtui-bin localsend-bin; do
        # On cherche le nom exact du fichier depuis l'hôte
        PKG_PATH=$(ls ${CHROOT_OFFLINE_DIR}/${pkg}*.pkg.tar.zst 2>/dev/null | head -n 1)
        
        if [[ -n "$PKG_PATH" ]]; then
            echo ">>> Installation de $pkg"
            # On enlève "/mnt" du chemin pour que ça corresponde au point de vue du chroot
            CHROOT_PKG_PATH="${PKG_PATH#/mnt}"
            
            # On passe le chemin exact (sans étoile) à pacman
            arch-chroot /mnt pacman -U --noconfirm "$CHROOT_PKG_PATH"
        else
            echo ">>> $pkg non trouvé, ignoré."
        fi
    done

    # --- 3. CONFIGURATION TTY AUTO-LOGIN ---
    echo "Configuring TTY auto-login for $username..."
    
    mkdir -p /mnt/etc/systemd/system/getty@tty1.service.d
    cat > /mnt/etc/systemd/system/getty@tty1.service.d/override.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $username --noclear %I \$TERM
EOF
    
    # --- 4. LANCEMENT AUTOMATIQUE DE HYPRLAND ---
    echo "Configuring auto-start Hyprland..."
    cat > "/mnt/home/$username/.bash_profile" << 'EOF'
if [ -f /.arch-chroot ] || [ -n "$INSTALLING" ]; then
    return 0 2>/dev/null || exit 0
fi
if [ -z "${DISPLAY:-}" ] && [ "$(tty 2>/dev/null)" = "/dev/tty1" ]; then
    exec Hyprland
fi
EOF
    chown 1000:1000 "/mnt/home/$username/.bash_profile"

    # --- 5. COPIE DES DOTFILES & INJECTION CLAVIER ---
    clear
    echo "Copying custom .config files..."
    if [[ -d ".config" ]]; then
        cp -r .config "/mnt/home/$username/"
        
        HYPRLAND_CONF="/mnt/home/$username/.config/hypr/init.lua"
        if [[ -f "$HYPRLAND_CONF" ]]; then
            sed -i "s/__KB_LAYOUT__/$keyboard/g" "$HYPRLAND_CONF"
            echo "Hyprland keyboard set to: $keyboard"
        fi

        chown -R 1000:1000 "/mnt/home/$username/.config"
        echo "Dotfiles configured successfully!"
    else
        echo "No .config folder found, skipping."
    fi
    
    # --- REBOOT ---
    echo "Installation finished! Rebooting in 3 seconds..."
    sleep 3
    reboot
fi