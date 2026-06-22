#!/bin/bash

clear

echo "=============================="
echo " Arch Custom Installer"
echo "=============================="

# 1. Nom utilisateur
read -p "Nom utilisateur: " USERNAME

# 2. Hostname
read -p "Nom machine (hostname): " HOSTNAME

# 3. Disque
lsblk
read -p "Disque à installer (ex: /dev/sda): " DISK

echo "WARNING: Tout sera effacé sur $DISK"
read -p "Continuer ? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Installation annulée"
    exit 1
fi

# 4. Partitionnement simple
parted $DISK --script mklabel gpt
parted $DISK --script mkpart primary fat32 1MiB 512MiB
parted $DISK --script set 1 esp on
parted $DISK --script mkpart primary ext4 512MiB 100%

mkfs.fat -F32 ${DISK}1
mkfs.ext4 ${DISK}2

mount ${DISK}2 /mnt
mkdir -p /mnt/boot
mount ${DISK}1 /mnt/boot

# 5. Base system
pacstrap /mnt base linux linux-firmware sudo networkmanager

genfstab -U /mnt >> /mnt/etc/fstab

# 6. Config système
arch-chroot /mnt bash -c "
  useradd -m -G wheel $USERNAME
  echo '$HOSTNAME' > /etc/hostname
  systemctl enable NetworkManager
"

echo "Installation terminée"
echo "Reboot..."
reboot