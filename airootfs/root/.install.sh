#!/usr/bin/env bash
set -euo pipefail

# ==========================================
# UI SYSTEM (Robust Bash Nameref)
# ==========================================
declare -A GRID_DATA
GRID_NUM_PAGES=0

grid_menu() {
    # Crée un alias local vers le tableau passé en argument (nom en string)
    local -n _items=$1
    local max_cols=$3 max_rows=$4
    local data_page=0 item_number=0 max_cols_data line

    GRID_DATA=()
    GRID_NUM_PAGES=0
    local total_items=${#_items[@]}

    while (( item_number < total_items )); do
        max_cols_data=1
        for (( line=0; line<max_rows; line++ )); do
            if (( item_number >= total_items )); then break; fi
            local key="P${data_page}L${line}"
            [[ ! -v GRID_DATA[$key] ]] && GRID_DATA[$key]=""

            local index=$(( item_number + max_rows - line ))
            (( index >= total_items )) && index=$(( total_items - 1 ))
            if (( index < 0 )); then index=$(( total_items + index )); (( index < 0 )) && index=0; fi

            local index_str item_num_plus1 item_num_str spaces_needed spaces add
            printf -v index_str "%d" "$index"
            item_num_plus1=$(( item_number + 1 ))
            printf -v item_num_str "%d" "$item_num_plus1"
            spaces_needed=$(( ${#index_str} - ${#item_num_str} ))
            (( spaces_needed < 0 )) && spaces_needed=0
            printf -v spaces "%*s" "$spaces_needed" ""
            
            local item="${_items[$item_number]}"
            add="${spaces}${item_num_plus1}) ${item}"

            local current_line="${GRID_DATA[$key]}"
            if (( ${#current_line} + ${#add} > max_cols )); then (( data_page++ )); break; fi
            
            GRID_DATA[$key]="${current_line}${add}"
            max_cols_data=$(( max_cols_data > ( ${#item} + 2 ) ? max_cols_data : ( ${#item} + 2 ) ))
            (( item_number++ ))
        done

        for (( line=0; line<max_rows; line++ )); do
            local key="P${data_page}L${line}"
            [[ ! -v GRID_DATA[$key] ]] && continue
            local idx=$(( item_number - (max_rows - line) ))
            if (( idx < 0 )); then idx=$(( total_items + idx )); (( idx < 0 )) && idx=0
            elif (( idx >= total_items )); then idx=$(( total_items - 1 )); fi
            
            local item="${_items[$idx]}"
            local pad=$(( max_cols_data - ${#item} ))
            (( pad < 0 )) && pad=0
            local spaces_pad; printf -v spaces_pad "%*s" "$pad" ""
            GRID_DATA[$key]="${GRID_DATA[$key]}${spaces_pad}"
        done
    done
    GRID_NUM_PAGES=$(( data_page + 1 ))
}

print_grid_menu() {
    local page=$1 found=0 key
    for key in "${!GRID_DATA[@]}"; do [[ $key == P${page}L* ]] && found=1 && break; done
    (( found == 0 )) && echo "Page $(( page + 1 )) does not exist." && return

    echo -e "\n--- Page $(( page + 1 )) of $GRID_NUM_PAGES ---\n"
    for key in $(printf "%s\n" "${!GRID_DATA[@]}" | grep "^P${page}L" | sort -t 'L' -k2 -n); do
        echo "${GRID_DATA[$key]}"
    done
}

grid_choose() {
    local arr_name=$1 cols=${2:-80} rows=${3:-15} page=0
    
    grid_menu "$arr_name" "$page" "$cols" "$rows"

    # Crée un alias local pour lire la taille et l'élément choisi
    local -n _items=$arr_name

    while true; do
        clear
        print_grid_menu "$page"
        echo -e "\n[n]ext | [p]rev | [q]uit"
        read -rp "Choice: " choice
        if [[ "$choice" == "q" ]]; then return 1; fi
        if [[ "$choice" == "n" && $page -lt $((GRID_NUM_PAGES - 1)) ]]; then ((page++)); continue; fi
        if [[ "$choice" == "p" && $page -gt 0 ]]; then ((page--)); continue; fi

        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            local idx=$((choice - 1))
            if (( idx >= 0 && idx < ${#_items[@]} )); then
                echo "${_items[$idx]}"
                return 0
            fi
        fi
        sleep 0.5
    done
}

ask_confirm() { read -rp "$1 (y/n): " ans; [[ "$ans" =~ ^[yY]$ ]]; }

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
    done < <(lsblk -rnpo PATH "$disk")
    while read -r dev type; do
        [[ "$type" == "disk" || "$type" == "part" || "$type" == "crypt" ]] || continue
        while read -r vg; do [[ -n "$vg" ]] && vgchange -an "$vg" 2>/dev/null; done < <(pvs --noheadings -o vg_name "$dev" 2>/dev/null | awk '{$1=$1; print}' | sort -u)
    done < <(lsblk -rnpo PATH,TYPE "$disk")
    while read -r dev type; do [[ "$type" == "crypt" ]] && cryptsetup close "$dev" 2>/dev/null; done < <(lsblk -rnpo PATH,TYPE "$disk")
    blockdev --flushbufs "$disk" 2>/dev/null || true
    partprobe "$disk" 2>/dev/null || true
    udevadm settle || true
}

install_base_system() {
    pacman-key --init
    pacman-key --populate archlinux
    pacman -Sy --noconfirm

    local disk
    disk=$(jq -r '.disk_config.device_modifications[] | select(.wipe==true) | .device' user_configuration.json)
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
    command -v jq >/dev/null || pacman -Sy --noconfirm jq

    # 1. Keyboard (PAS de 'local' devant le tableau !)
    kb_keys=("us" "fr" "de" "uk" "es" "it" "pt-latin1" "br-abnt2" "dvorak" "colemak" "ru" "jp106")
    kb_choice=$(grid_choose kb_keys 80 10) || exit 1
    keyboard="$kb_choice"
    [[ $(tty 2>/dev/null) == "/dev/tty"* ]] && loadkeys "$keyboard" 2>/dev/null || true

    # 2. User
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

    # 3. Timezone (PAS de 'local' devant le tableau !)
    clear; echo "Loading timezones..."
    mapfile -t timezones < <(timedatectl list-timezones)
    timezone=$(grid_choose timezones 100 20) || exit 1

    # 4. Disk (PAS de 'local' devant les tableaux !)
    clear
    local boot_source exclude_disk
    boot_source=$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null || true)
    local device_b=$(readlink -f "$boot_source" 2>/dev/null || echo "")
    while [[ -n "$device_b" ]]; do
        local parent_b=$(lsblk -dno PKNAME "$device_b" 2>/dev/null | tail -n1)
        [[ -z "$parent_b" ]] && break; device_b="/dev/$parent_b"
    done
    [[ $(lsblk -dno TYPE "$device_b" 2>/dev/null) == "disk" ]] && exclude_disk="$device_b"

    disk_options_array=()
    mapfile -t available_disks < <(lsblk -dpno NAME,TYPE | awk '$2=="disk"{print $1}' | grep -E '/dev/(sd|hd|vd|nvme|mmcblk|xv)' | { [[ -n "${exclude_disk:-}" ]] && grep -Fvx "$exclude_disk" || cat; })
    for dev in "${available_disks[@]}"; do
        local size=$(lsblk -dno SIZE "$dev") model=$(lsblk -dno MODEL "$dev" | sed 's/ *$//')
        disk_options_array+=("$dev ($size) - $model")
    done
    selected_disk_display=$(grid_choose disk_options_array 100 10) || exit 1
    disk=$(echo "$selected_disk_display" | awk '{print $1}')

    # 5. Encryption
    clear; local encrypt_installation="false"
    ask_confirm "Encrypt disk?" && encrypt_installation="true"

    # --- JSON GENERATION ---
    local pw_esc=$(echo -n "$password" | jq -Rsa)
    local hash_esc=$(echo -n "$password_hash" | jq -Rsa)
    local user_esc=$(echo -n "$username" | jq -Rsa)
    local enc_line=""; [[ "$encrypt_installation" == "true" ]] && enc_line="\"encryption_password\": $pw_esc,"

    cat <<_EOF_ >user_credentials.json
{
 $enc_line
"root_enc_password": $hash_esc,
"users": [{ "enc_password": $hash_esc, "groups": [], "sudo": true, "username": $user_esc }]
}
_EOF_

    local disk_size=$(lsblk -bdno SIZE "$disk") mib=$((1024*1024)) gib=$((mib*1024))
    local disk_size_in_mib=$((disk_size / mib * mib)) boot_size=$((2 * gib)) main_start=$((boot_size + mib))
    local main_size=$((disk_size_in_mib - main_start - mib))
    
    local disk_enc=""
    [[ "$encrypt_installation" == "true" ]] && disk_enc=$(cat <<_EOF_
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
"bootloader": "systemd-boot",
"disk_config": {
"btrfs_options": { "snapshot_config": { "type": "Snapper" } },
"config_type": "default_layout",
"device_modifications": [{
"device": "$disk",
"partitions": [
{ "btrfs": [], "dev_path": null, "flags": ["boot", "esp"], "fs_type": "fat32", "mount_options": [], "mountpoint": "/boot", "obj_id": "ea21d3f2-82bb-49cc-ab5d-6f81ae94e18d", "size": { "sector_size": { "unit": "B", "value": 512 }, "unit": "B", "value": $boot_size }, "start": { "sector_size": { "unit": "B", "value": 512 }, "unit": "B", "value": $mib }, "status": "create", "type": "primary" },
{ "btrfs": [ {"mountpoint": "/", "name": "@"}, {"mountpoint": "/home", "name": "@home"}, {"mountpoint": "/var/log", "name": "@log"}, {"mountpoint": "/var/cache/pacman/pkg", "name": "@pkg"} ], "dev_path": null, "flags": [], "fs_type": "btrfs", "mount_options": ["compress=zstd"], "mountpoint": null, "obj_id": "8c2c2b92-1070-455d-b76a-56263bab24aa", "size": { "sector_size": { "unit": "B", "value": 512 }, "unit": "B", "value": $main_size }, "start": { "sector_size": { "unit": "B", "value": 512 }, "unit": "B", "value": $main_start }, "status": "create", "type": "primary" }
],
"wipe": true
}]$disk_enc
},
"hostname": "$hostname",
"kernels": ["linux"],
"network_config": { "type": "iso" },
"ntp": true,
"parallel_downloads": 8,
"swap": true,
"timezone": "$timezone",
"locale_config": { "kb_layout": "$keyboard", "sys_enc": "UTF-8", "sys_lang": "en_US.UTF-8" },
"mirror_config": {
"custom_servers": [
{"url": "https://geo.mirror.pkgbuild.com/\$repo/os/\$arch"},
{"url": "https://mirror.rackspace.com/archlinux/\$repo/os/\$arch"}
]
},
"packages": ["base-devel", "git", "snapper"],
"profile_config": { "gfx_driver": null, "greeter": null, "profile": {} },
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
    echo "Base installation complete. You can now reboot or chroot into /mnt."
fi