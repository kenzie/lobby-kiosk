#!/bin/bash
set -euo pipefail

# Lobby Kiosk Complete System Installer
# Usage from Arch Linux ISO: curl -sSL https://raw.githubusercontent.com/kenzie/lobby-kiosk/main/install.sh | bash
# This installer ONLY works from Arch Linux live USB/ISO

KIOSK_USER="lobby"
KIOSK_DIR="/opt/lobby"
REPO_URL="https://github.com/kenzie/lobby-display.git"
CONFIG_REPO_URL="https://raw.githubusercontent.com/kenzie/lobby-kiosk/main"
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

# Always run in system install mode (designed for Arch ISO USB only)
INSTALL_MODE="system"

# Verify we're on live ISO
if [[ ! -f /etc/arch-release ]]; then
    error "This installer requires Arch Linux"
fi

if [[ -d /mnt/etc ]]; then
    warn "Found existing /mnt/etc - unmounting previous attempts"
    umount -R /mnt 2>/dev/null || true
fi

log "Starting lobby-kiosk installer in $INSTALL_MODE mode..."

# Install git once at the beginning
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

# Install base Arch Linux system
install_base_system() {
    log "Installing base Arch Linux system..."
    
    # Update package database
    pacman -Sy
    
    # Install base system
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

# Install essential packages from package list
PACKAGE_LIST="/tmp/lobby-kiosk-config/configs/packages.txt"
if [[ ! -f "$PACKAGE_LIST" ]]; then
    error "Package list not found: $PACKAGE_LIST"
fi

# Filter out comments and empty lines, then install
PACKAGES=$(grep -v '^#' "$PACKAGE_LIST" | grep -v '^$' | tr '\n' ' ')
pacman -S --noconfirm $PACKAGES

# Install and configure GRUB
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Enable essential services
systemctl enable NetworkManager
systemctl enable sshd

CHROOT_COMMANDS

    log "Base system installation complete"
}

# Install application packages
install_packages() {
    log "Installing kiosk packages..."
    if [[ $INSTALL_MODE == "system" ]]; then
        # Already installed in base system
        return
    else
        # Application install mode
        pacman -Syu --noconfirm
        pacman -S --noconfirm \
            git nginx nodejs npm chromium xorg-server xorg-xinit xorg-xset \
            xorg-xrandr mesa scrot unclutter sudo openssh tailscale cronie
    fi
}

# Create kiosk user and directories
setup_user() {
    log "Setting up kiosk user and directories..."
    
    local target_root=""
    if [[ $INSTALL_MODE == "system" ]]; then
        target_root="/mnt"
    fi
    
    # Create user (in chroot if system install)
    if [[ $INSTALL_MODE == "system" ]]; then
        arch-chroot /mnt /bin/bash << CHROOT_USER
useradd -m -s /bin/bash -G video,audio,wheel "$KIOSK_USER"
echo "$KIOSK_USER:$KIOSK_USER" | chpasswd
CHROOT_USER
    else
        id "$KIOSK_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash -G video,audio "$KIOSK_USER"
    fi
    
    # Create directories
    mkdir -p "$target_root$KIOSK_DIR"/{app,config,logs,scripts,backups}
    mkdir -p "$target_root$KIOSK_DIR/app"/{releases,shared}
    
    if [[ $INSTALL_MODE == "system" ]]; then
        chroot /mnt chown -R "$KIOSK_USER:$KIOSK_USER" "$KIOSK_DIR"
    else
        chown -R "$KIOSK_USER:$KIOSK_USER" "$KIOSK_DIR"
    fi
}


# Main installation flow
main() {
    if [[ $INSTALL_MODE == "system" ]]; then
        log "Installing complete lobby-kiosk system from scratch..."
        
        
        # Download config files first (needed for package list)
        log "Downloading configuration files..."
        cd /tmp
        rm -rf lobby-kiosk-config
        git clone https://github.com/kenzie/lobby-kiosk.git lobby-kiosk-config
        
        detect_disk
        setup_disk
        install_base_system
        
        # Continue installation in chroot
        cat > /mnt/tmp/kiosk-install.sh << 'KIOSK_SCRIPT'
#!/bin/bash
set -euo pipefail

KIOSK_USER="lobby"
KIOSK_DIR="/opt/lobby"

# Setup directories and user
mkdir -p "$KIOSK_DIR"/{app,config,logs,scripts,backups}
mkdir -p "$KIOSK_DIR/app"/{releases,shared}
chown -R "$KIOSK_USER:$KIOSK_USER" "$KIOSK_DIR"

# Download configuration files using git
cd /tmp
rm -rf lobby-kiosk-config
git clone https://github.com/kenzie/lobby-kiosk.git lobby-kiosk-config

# Install systemd services
cp lobby-kiosk-config/configs/systemd/*.target /etc/systemd/system/
cp lobby-kiosk-config/configs/systemd/*.service /etc/systemd/system/

# Install nginx config
cp lobby-kiosk-config/configs/nginx/nginx.conf /etc/nginx/

# Install font config
mkdir -p /etc/fonts
cp lobby-kiosk-config/configs/fonts/local.conf /etc/fonts/

# Install scripts
cp lobby-kiosk-config/scripts/*.sh "$KIOSK_DIR/scripts/"
cp lobby-kiosk-config/bin/lobby /usr/local/bin/

# Cleanup
rm -rf lobby-kiosk-config

# Set permissions
chmod +x "$KIOSK_DIR/scripts"/*.sh /usr/local/bin/lobby
chown -R "$KIOSK_USER:$KIOSK_USER" "$KIOSK_DIR/scripts"

# Configure autologin
mkdir -p /etc/systemd/system/getty@tty1.service.d/
cat > /etc/systemd/system/getty@tty1.service.d/override.conf << EOF
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin $KIOSK_USER --noclear %I \$TERM
EOF

# Configure sudo
cat > /etc/sudoers.d/lobby << EOF
$KIOSK_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart lobby-*.service
$KIOSK_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl reload nginx
$KIOSK_USER ALL=(ALL) NOPASSWD: /usr/bin/reboot
EOF

# Enable services
systemctl daemon-reload
systemctl enable lobby-kiosk.target
systemctl enable sshd tailscaled
systemctl set-default multi-user.target
systemctl disable bluetooth cups avahi-daemon 2>/dev/null || true

echo "2.0.0" > "$KIOSK_DIR/config/version"
chown "$KIOSK_USER:$KIOSK_USER" "$KIOSK_DIR/config/version"

KIOSK_SCRIPT

        chmod +x /mnt/tmp/kiosk-install.sh
        arch-chroot /mnt /tmp/kiosk-install.sh
        
        log "System installation complete!"
        echo -e "${YELLOW}Installation finished!${NC}"
        echo "1. Unmount: umount -R /mnt"
        echo "2. Reboot: reboot"
        echo "3. Remove installation media"
        echo "4. System will auto-login as '$KIOSK_USER'"
        echo "5. Run 'lobby status' to check services"
        
    else
        log "Installing kiosk application on existing system..."
        install_packages
        setup_user
        install_configs
        configure_system
        
        log "Application installation complete!"
        echo -e "${YELLOW}Next steps:${NC}"
        echo "1. Configure Tailscale: tailscale up"
        echo "2. Reboot: reboot"
        echo "3. Check status: lobby status"
    fi
}

# Install configuration files using git
install_configs() {
    log "Downloading configuration files via git..."
    cd /tmp
    rm -rf lobby-kiosk-config
    git clone https://github.com/kenzie/lobby-kiosk.git lobby-kiosk-config

    log "Installing configuration files..."
    # Install systemd services
    cp lobby-kiosk-config/configs/systemd/*.target /etc/systemd/system/
    cp lobby-kiosk-config/configs/systemd/*.service /etc/systemd/system/

    # Install nginx config
    cp lobby-kiosk-config/configs/nginx/nginx.conf /etc/nginx/

    # Install font config
    mkdir -p /etc/fonts
    cp lobby-kiosk-config/configs/fonts/local.conf /etc/fonts/

    log "Installing management scripts..."
    # Install scripts
    cp lobby-kiosk-config/scripts/*.sh "$KIOSK_DIR/scripts/"
    cp lobby-kiosk-config/bin/lobby /usr/local/bin/

    # Cleanup
    rm -rf lobby-kiosk-config
    
    chmod +x "$KIOSK_DIR/scripts"/*.sh /usr/local/bin/lobby
    chown -R "$KIOSK_USER:$KIOSK_USER" "$KIOSK_DIR/scripts"
}

# Configure system settings
configure_system() {
    log "Configuring system..."
    
    # Configure autologin
    mkdir -p /etc/systemd/system/getty@tty1.service.d/
    cat > /etc/systemd/system/getty@tty1.service.d/override.conf << EOF
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin $KIOSK_USER --noclear %I \$TERM
EOF

    # Configure sudo permissions
    cat > /etc/sudoers.d/lobby << EOF
$KIOSK_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart lobby-*.service
$KIOSK_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl reload nginx
$KIOSK_USER ALL=(ALL) NOPASSWD: /usr/bin/reboot
EOF

    # Initial app deployment
    log "Setting up initial application..."
    echo "2.0.0" > "$KIOSK_DIR/config/version"
    chown "$KIOSK_USER:$KIOSK_USER" "$KIOSK_DIR/config/version"
    
    # Enable services
    systemctl daemon-reload
    systemctl enable lobby-kiosk.target
    systemctl enable sshd tailscaled
    
    # Boot optimization
    systemctl set-default multi-user.target
    systemctl disable bluetooth cups avahi-daemon 2>/dev/null || true
}

# Run main installation
main "$@"