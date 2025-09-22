#!/bin/bash
set -euo pipefail

# Lobby Kiosk Installer for Lenovo M75q-1
TARGET_DISK="/dev/nvme0n1"
ROOT_PASSWORD=""

log() { echo "[$(date +'%H:%M:%S')] $1"; }
error() { echo "ERROR: $1"; exit 1; }

[[ ! -f /etc/arch-release ]] && error "This installer requires Arch Linux"

# Get password - always prompt
while [[ -z "$ROOT_PASSWORD" ]]; do
    echo -n "Enter root password: "
    read -s ROOT_PASSWORD
    echo
    if [[ -z "$ROOT_PASSWORD" ]]; then
        echo "Password cannot be empty. Please try again."
    fi
done

log "Lobby Kiosk Installer for Lenovo M75q-1"
log "Target disk: $TARGET_DISK"

# Verify target disk exists
[[ ! -b "$TARGET_DISK" ]] && error "Target disk $TARGET_DISK not found"

# Warning - force user confirmation
echo ""
echo "========================================"
echo "WARNING: DESTRUCTIVE OPERATION AHEAD!"
echo "========================================"
echo "This will COMPLETELY DESTROY all data on $TARGET_DISK"
echo "Target disk: $TARGET_DISK"
echo ""
echo "Are you absolutely sure you want to continue? (type 'YES' to proceed)"
echo "DEBUG: About to read confirmation..."
CONFIRMATION=""
while true; do
    echo -n "Confirmation: "
    read CONFIRMATION </dev/tty
    echo "DEBUG: Received input: '$CONFIRMATION' (length: ${#CONFIRMATION})"
    
    if [[ "$CONFIRMATION" == "YES" ]]; then
        echo "DEBUG: Confirmation accepted, proceeding..."
        break
    elif [[ -z "$CONFIRMATION" ]]; then
        echo "DEBUG: Empty input received"
        echo "Please type 'YES' to continue or press Ctrl+C to abort."
    else
        echo "DEBUG: Invalid input: '$CONFIRMATION'"
        echo "You typed '$CONFIRMATION'. Please type exactly 'YES' to continue or press Ctrl+C to abort."
    fi
    
    # Add a small delay to see what's happening
    sleep 1
done

# Unmount any existing partitions
umount ${TARGET_DISK}* 2>/dev/null || true

# Wipe and partition using fdisk
log "Partitioning $TARGET_DISK..."
wipefs -af "$TARGET_DISK"

(
echo g      # create GPT partition table
echo n      # new partition
echo 1      # partition number 1
echo        # default start
echo +512M  # 512MB EFI partition
echo t      # change type
echo 1      # EFI System
echo n      # new partition
echo 2      # partition number 2
echo        # default start
echo        # default end (rest of disk)
echo w      # write changes
) | fdisk "$TARGET_DISK"

# Wait for partitions to appear
sleep 3

# Format partitions
log "Formatting partitions..."
mkfs.fat -F32 "${TARGET_DISK}p1"
mkfs.ext4 -F "${TARGET_DISK}p2"

# Mount
log "Mounting filesystems..."
mount "${TARGET_DISK}p2" /mnt
mkdir -p /mnt/boot
mount "${TARGET_DISK}p1" /mnt/boot

# Install base system optimized for Lenovo M75q-1 (AMD Ryzen)
log "Installing base system for Lenovo M75q-1..."
pacman -Sy --noconfirm
pacstrap /mnt \
    base linux linux-firmware \
    grub efibootmgr \
    networkmanager openssh sudo \
    amd-ucode \
    mesa xf86-video-amdgpu \
    inetutils \
    nodejs npm

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Configure system
log "Configuring system..."
arch-chroot /mnt bash -c "
# Timezone
ln -sf /usr/share/zoneinfo/America/Halifax /etc/localtime
hwclock --systohc

# Locale
echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf

# Hostname
echo 'lobby-kiosk' > /etc/hostname
echo '127.0.0.1 localhost
::1 localhost
127.0.1.1 lobby-kiosk.localdomain lobby-kiosk' > /etc/hosts

# Root password
echo 'root:$ROOT_PASSWORD' | chpasswd

# GRUB bootloader
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Enable services
systemctl enable NetworkManager sshd

# Create lobby user
useradd -m -G wheel lobby
echo 'lobby:$ROOT_PASSWORD' | chpasswd
echo 'lobby ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/lobby

# Configure autologin
mkdir -p /etc/systemd/system/getty@tty1.service.d/
echo '[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin lobby --noclear %I \$TERM' > /etc/systemd/system/getty@tty1.service.d/override.conf
"

# Run post-install configuration automatically
log "Running post-install configuration..."
arch-chroot /mnt bash -c "curl -sSL https://raw.githubusercontent.com/kenzie/lobby-kiosk/main/post-install.sh | bash"

log "Installation complete!"
echo ""

# Unmount filesystems first
log "Unmounting filesystems..."
umount -R /mnt || {
    error "Failed to unmount filesystems. Please unmount manually: umount -R /mnt"
}

# Prompt for USB removal
echo "========================================"
echo "REMOVE INSTALLATION MEDIA NOW"
echo "========================================"
echo "Please remove the USB installation media"
echo "from the system before rebooting."
echo ""
echo "Press Enter after removing the USB drive to reboot..."
read

log "Rebooting system..."
echo "System will start automatically with the kiosk display."
reboot