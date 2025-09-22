#!/bin/bash
set -euo pipefail

# Simple Lobby Kiosk Installer
TARGET_DISK="/dev/sda"
ROOT_PASSWORD="${ROOT_PASSWORD:-}"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"; }
error() { echo -e "${RED}[$(date +'%H:%M:%S')] ERROR: $1${NC}"; exit 1; }

# Verify we're on live ISO
[[ ! -f /etc/arch-release ]] && error "This installer requires Arch Linux"

# Prompt for root password
if [[ -z "${ROOT_PASSWORD:-}" ]]; then
    while true; do
        echo -n "Enter root password: "
        read -s password1
        echo
        echo -n "Confirm password: "
        read -s password2
        echo
        
        if [[ "$password1" == "$password2" && -n "$password1" ]]; then
            ROOT_PASSWORD="$password1"
            break
        else
            echo "Passwords do not match or empty. Try again."
        fi
    done
fi

log "Starting lobby-kiosk installer..."

# Auto-detect largest disk
for disk in /dev/sd? /dev/nvme?n1 /dev/vd?; do
    if [[ -b "$disk" ]]; then
        size=$(lsblk -b -d -o SIZE "$disk" 2>/dev/null | tail -1 | tr -d ' ')
        if [[ $size -gt ${largest_size:-0} ]]; then
            largest_size=$size
            TARGET_DISK="$disk"
        fi
    fi
done

log "Using disk: $TARGET_DISK"

# Partition disk
log "Partitioning disk..."

# Ensure disk is not mounted
umount "${TARGET_DISK}"* 2>/dev/null || true

# Clear existing partitions thoroughly
wipefs -af "$TARGET_DISK"
dd if=/dev/zero of="$TARGET_DISK" bs=1M count=100 2>/dev/null || true

# Create partition table
parted -s "$TARGET_DISK" mklabel gpt
parted -s "$TARGET_DISK" mkpart primary fat32 1MiB 513MiB
parted -s "$TARGET_DISK" set 1 esp on
parted -s "$TARGET_DISK" mkpart primary ext4 513MiB 100%

# Force kernel to re-read partition table
sync
partprobe "$TARGET_DISK"
sleep 3
udevadm settle
sleep 2

# Format partitions
boot_part="${TARGET_DISK}1"
root_part="${TARGET_DISK}2"
[[ $TARGET_DISK == *"nvme"* ]] && boot_part="${TARGET_DISK}p1" && root_part="${TARGET_DISK}p2"

log "Formatting partitions..."
mkfs.fat -F32 "$boot_part"
mkfs.ext4 -F "$root_part"

# Mount filesystems
mount "$root_part" /mnt
mkdir -p /mnt/boot
mount "$boot_part" /mnt/boot

# Install base system
log "Installing base system..."
pacman -Sy
pacstrap /mnt base base-devel linux linux-firmware grub efibootmgr networkmanager openssh sudo git

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Configure system
log "Configuring system..."
arch-chroot /mnt bash -c "
set -euo pipefail

# Timezone
ln -sf /usr/share/zoneinfo/America/Halifax /etc/localtime
hwclock --systohc

# Locale
echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf

# Hostname
echo 'lobby-kiosk' > /etc/hostname
cat > /etc/hosts << 'EOF'
127.0.0.1 localhost
::1       localhost
127.0.1.1 lobby-kiosk.localdomain lobby-kiosk
EOF

# Root password
echo 'root:$ROOT_PASSWORD' | chpasswd

# GRUB
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Enable services
systemctl enable NetworkManager sshd

# Create lobby user
useradd -m -s /bin/bash -G wheel lobby
echo 'lobby:$ROOT_PASSWORD' | chpasswd

# Configure autologin
mkdir -p /etc/systemd/system/getty@tty1.service.d/
cat > /etc/systemd/system/getty@tty1.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin lobby --noclear %I \$TERM
EOF

# Sudo for lobby user
echo 'lobby ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/lobby
"

log "Base installation complete!"
echo "1. Unmount: umount -R /mnt"
echo "2. Reboot: reboot"
echo "3. Remove installation media"
echo "4. System will auto-login as 'lobby'"
echo "5. Run post-install after boot: curl -sSL https://raw.githubusercontent.com/kenzie/lobby-kiosk/main/post-install.sh | sudo bash"
