#!/bin/bash
set -euo pipefail

# Lobby Kiosk Minimal System Installer
# Sets up base Arch Linux system, then runs post-install for configuration

TARGET_DISK="/dev/sda"  # Will be auto-detected
HOSTNAME="lobby-kiosk"
ROOT_PASSWORD="kiosk123"  # Change this!

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"; }
error() { echo -e "${RED}[$(date +'%H:%M:%S')] ERROR: $1${NC}"; exit 1; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARNING: $1${NC}"; }

# Verify we're on live ISO
if [[ ! -f /etc/arch-release ]]; then
    error "This installer requires Arch Linux"
fi

if [[ -d /mnt/etc ]]; then
    warn "Found existing /mnt/etc - unmounting previous attempts"
    umount -R /mnt 2>/dev/null || true
fi

log "Starting lobby-kiosk minimal system installer..."

# Install git for post-install
log "Installing git..."
pacman -Sy --noconfirm git

# Auto-detect target disk
detect_disk() {
    log "Detecting target disk..."
    
    # Find the largest disk (usually the main drive)
    local largest_disk=""
    local largest_size=0
    
    for disk in /dev/sd? /dev/nvme?n1 /dev/vd?; do
        if [[ -b "$disk" ]]; then
            local size=$(lsblk -b -d -o SIZE "$disk" 2>/dev/null | tail -1 | tr -d ' ')
            if [[ $size -gt $largest_size ]]; then
                largest_size=$size
                largest_disk="$disk"
            fi
        fi
    done
    
    if [[ -z "$largest_disk" ]]; then
        error "No suitable disk found"
    fi
    
    TARGET_DISK="$largest_disk"
    log "Using disk: $TARGET_DISK ($(( largest_size / 1024 / 1024 / 1024 ))GB)"
}

# Partition and format disk
setup_disk() {
    log "Partitioning disk $TARGET_DISK..."
    
    # Clear existing partitions
    wipefs -af "$TARGET_DISK"
    
    # Create GPT partition table
    parted -s "$TARGET_DISK" mklabel gpt
    
    # Create EFI boot partition (512MB)
    parted -s "$TARGET_DISK" mkpart primary fat32 1MiB 513MiB
    parted -s "$TARGET_DISK" set 1 esp on
    
    # Create root partition (rest of disk)
    parted -s "$TARGET_DISK" mkpart primary ext4 513MiB 100%
    
    # Wait for partitions to appear
    sleep 2
    partprobe "$TARGET_DISK"
    sleep 2
    
    # Format partitions
    local boot_part="${TARGET_DISK}1"
    local root_part="${TARGET_DISK}2"
    
    # Handle nvme naming
    if [[ $TARGET_DISK == *"nvme"* ]]; then
        boot_part="${TARGET_DISK}p1"
        root_part="${TARGET_DISK}p2"
    fi
    
    log "Formatting partitions..."
    mkfs.fat -F32 "$boot_part"
    mkfs.ext4 -F "$root_part"
    
    # Mount filesystems
    mount "$root_part" /mnt
    mkdir -p /mnt/boot
    mount "$boot_part" /mnt/boot
    
    log "Disk setup complete"
}

# Install minimal base system
install_base_system() {
    log "Installing minimal base Arch Linux system..."
    
    # Update package database
    pacman -Sy
    
    # Install minimal base system
    pacstrap /mnt base base-devel linux linux-firmware
    
    # Generate fstab
    genfstab -U /mnt >> /mnt/etc/fstab
    
    # Configure system in chroot
    arch-chroot /mnt /bin/bash << 'CHROOT_COMMANDS'
set -euo pipefail

# Set timezone
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
hwclock --systohc

# Configure locale
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set hostname
echo "lobby-kiosk" > /etc/hostname

# Configure hosts file
cat > /etc/hosts << EOF
127.0.0.1 localhost
::1       localhost
127.0.1.1 lobby-kiosk.localdomain lobby-kiosk
EOF

# Set root password
echo "root:kiosk123" | chpasswd

# Install minimal essential packages
pacman -S --noconfirm \
    grub efibootmgr networkmanager openssh sudo \
    git curl wget

# Install and configure GRUB
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Enable essential services
systemctl enable NetworkManager
systemctl enable sshd

CHROOT_COMMANDS

    log "Base system installation complete"
}

# Run post-install configuration
run_post_install() {
    log "Running post-install configuration..."
    
    # Download and run post-install script in chroot
    arch-chroot /mnt /bin/bash << 'POST_INSTALL'
set -euo pipefail

# Download and run post-install
curl -sSL https://raw.githubusercontent.com/kenzie/lobby-kiosk/main/post-install.sh | bash

POST_INSTALL

    log "Post-install configuration complete"
}

# Main installation flow
main() {
    log "Installing complete lobby-kiosk system..."
    
    detect_disk
    setup_disk
    install_base_system
    run_post_install
    
    log "Installation complete!"
    echo -e "${YELLOW}Installation finished!${NC}"
    echo "1. Unmount: umount -R /mnt"
    echo "2. Reboot: reboot"
    echo "3. Remove installation media"
    echo "4. System will auto-login as 'lobby'"
    echo "5. Run 'lobby status' to check services"
    echo ""
    echo "To update the system in the future:"
    echo "  curl -sSL https://raw.githubusercontent.com/kenzie/lobby-kiosk/main/post-install.sh | sudo bash"
}

# Run main installation
main "$@"