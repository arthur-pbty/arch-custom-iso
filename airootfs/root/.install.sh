#!/bin/bash
set -e

clear
echo "========================"
echo " Arch Custom Installer"
echo "========================"

# =========================
# 1. KEYBOARD
# =========================
echo "Clavier (fr / us / uk / de / es) :"
read -r KEYMAP
loadkeys "$KEYMAP"

# =========================
# 2. NETWORK (AUTO + WIFI MANUEL)
# =========================
if ! ping -c 1 archlinux.org &>/dev/null; then
    echo "Pas d'internet détecté."

    iwctl device list
    echo "Device Wi-Fi (ex: wlan0) :"
    read -r DEVICE

    iwctl station "$DEVICE" scan
    sleep 3

    iwctl station "$DEVICE" get-networks

    echo "SSID :"
    read -r SSID

    echo "Password Wi-Fi :"
    read -rs PASS
    echo

    iwctl station "$DEVICE" connect "$SSID" --passphrase "$PASS"

    sleep 5
fi

# =========================
# 3. TIMEZONE
# =========================
echo "Fuseau horaire (ex: Europe/Paris) :"
read -r TIMEZONE

# =========================
# 4. LOCALE
# =========================
echo "Langue système (fr_FR.UTF-8 / en_US.UTF-8 / etc) :"
read -r LOCALE

# =========================
# 5. USER
# =========================
DEFAULT_USER="user"
echo "Nom utilisateur [$DEFAULT_USER] :"
read -r USERNAME
USERNAME=${USERNAME:-$DEFAULT_USER}

echo "Mot de passe utilisateur :"
read -rs USERPASS
echo

# =========================
# 6. HOSTNAME
# =========================
DEFAULT_HOST="archbox"
echo "Hostname [$DEFAULT_HOST] :"
read -r HOSTNAME
HOSTNAME=${HOSTNAME:-$DEFAULT_HOST}

# =========================
# 7. DISK
# =========================
lsblk -dpno NAME,SIZE,MODEL

echo "Disque (ex: /dev/sda ou /dev/nvme0n1) :"
read -r DISK

echo "⚠️ TOUT SERA EFFACÉ SUR $DISK"
echo "Taper YES pour confirmer :"
read -r CONFIRM
[[ "$CONFIRM" != "YES" ]] && exit 1

# =========================
# 8. PARTITIONING
# =========================
sgdisk --zap-all "$DISK"

sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI" "$DISK"
sgdisk -n 2:0:0     -t 2:8300 -c 2:"ROOT" "$DISK"

EFI="${DISK}1"
ROOT="${DISK}2"

mkfs.fat -F32 "$EFI"
mkfs.ext4 -F "$ROOT"

mount "$ROOT" /mnt
mount --mkdir "$EFI" /mnt/boot

# =========================
# 9. BASE INSTALL
# =========================
pacstrap -K /mnt \
    base linux linux-firmware \
    sudo networkmanager iwd

genfstab -U /mnt >> /mnt/etc/fstab

# =========================
# 10. CHROOT
# =========================
arch-chroot /mnt /bin/bash <<EOF

set -e

ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc

echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

echo "$LOCALE UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf

echo "$HOSTNAME" > /etc/hostname

useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:$USERPASS" | chpasswd

echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel

systemctl enable NetworkManager

EOF

echo "========================"
echo " Installation terminée"
echo "========================"
reboot