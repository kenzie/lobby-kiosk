#!/bin/bash
set -euo pipefail

# Simple Working Lobby Kiosk Installer
ROOT_PASSWORD="${ROOT_PASSWORD:-}"

log() { echo "[$(date +'%H:%M:%S')] $1"; }
error() { echo "ERROR: $1"; exit 1; }

[[ ! -f /etc/arch-release ]] && error "This installer requires Arch Linux"

# Get password
if [[ -z "${ROOT_PASSWORD:-}" ]]; then
    echo -n "Enter root password: "
    read -s ROOT_PASSWORD
    echo
fi

log "Starting installer..."

# Find disk
TARGET_DISK=""
for disk in /dev/vda /dev/sda /dev/nvme0n1; do
    if [[ -b "$disk" ]]; then
        TARGET_DISK="$disk"
        break
    fi
done

[[ -z "$TARGET_DISK" ]] && error "No disk found"
log "Using disk: $TARGET_DISK"

# Partition
log "Partitioning..."
(
echo g      # create GPT partition table
echo n      # new partition
echo 1      # partition number 1
echo        # default - start at beginning of disk
echo +512M  # 512MB EFI partition
echo t      # change type
echo 1      # EFI System
echo n      # new partition
echo 2      # partition number 2
echo        # default start
echo        # default end (rest of disk)
echo w      # write changes
) | fdisk "$TARGET_DISK"

# Wait and format
sleep 3
mkfs.fat -F32 "${TARGET_DISK}1" || mkfs.fat -F32 "${TARGET_DISK}p1"
mkfs.ext4 -F "${TARGET_DISK}2" || mkfs.ext4 -F "${TARGET_DISK}p1"

# Mount
if [[ -b "${TARGET_DISK}1" ]]; then
    mount "${TARGET_DISK}2" /mnt
    mkdir -p /mnt/boot
    mount "${TARGET_DISK}1" /mnt/boot
else
    mount "${TARGET_DISK}p2" /mnt
    mkdir -p /mnt/boot
    mount "${TARGET_DISK}p1" /mnt/boot
fi

# Install
log "Installing base system..."
pacman -Sy --noconfirm
pacstrap /mnt base linux linux-firmware grub efibootmgr networkmanager openssh sudo

# Configure
genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt bash -c "
ln -sf /usr/share/zoneinfo/America/Halifax /etc/localtime
hwclock --systohc
echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
echo 'lobby-kiosk' > /etc/hostname
echo 'root:$ROOT_PASSWORD' | chpasswd
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
systemctl enable NetworkManager sshd
useradd -m -G wheel lobby
echo 'lobby:$ROOT_PASSWORD' | chpasswd
echo 'lobby ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/lobby
mkdir -p /etc/systemd/system/getty@tty1.service.d/
echo '[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin lobby --noclear %I \$TERM' > /etc/systemd/system/getty@tty1.service.d/override.conf
"

log "Done! Unmount with: umount -R /mnt && reboot"