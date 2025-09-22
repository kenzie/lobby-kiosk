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
ROOT_PASSWORD="${ROOT_PASSWORD:-}"

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

# Check if this script is being piped from curl
if [[ ! -t 0 ]]; then
    echo "=== Lobby Kiosk Installer ==="
    echo "For interactive password setup, please run:"
    echo ""
    echo "  curl -O https://raw.githubusercontent.com/kenzie/lobby-kiosk/main/install.sh"
    echo "  bash install.sh"
    echo ""
    echo "Or set password with environment variable:"
    echo "  ROOT_PASSWORD='your-password' curl ... | bash"
    exit 1
fi

# Interactive password prompt
if [[ -z "${ROOT_PASSWORD:-}" ]]; then
    while true; do
        echo
        echo "=== Root Password Setup ==="
        echo -n "Enter root password: "
        read -s password1
        echo
        echo -n "Confirm password: "
        read -s password2
        echo
        
        if [[ "$password1" == "$password2" ]]; then
            if [[ -n "$password1" ]]; then
                ROOT_PASSWORD="$password1"
                log "Root password set successfully"
                break
            else
                echo "Password cannot be empty. Please try again."
            fi
        else
            echo "Passwords do not match. Please try again."
        fi
    done
fi

log "Starting lobby-kiosk installer in $INSTALL_MODE mode..."

# Install git once at the beginning
log "Installing git..."
pacman -Sy --noconfirm git
log "Git installation complete"

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
    
    # Configure system in chroot (no heredocs!)
    configure_chroot_system

    log "Base system installation complete"
}

# Configure system inside chroot (no heredocs!)
configure_chroot_system() {
    log "Configuring system in chroot..."
    
    # Set timezone
    arch-chroot /mnt ln -sf /usr/share/zoneinfo/America/Halifax /etc/localtime
    arch-chroot /mnt hwclock --systohc
    
    # Configure locale
    arch-chroot /mnt bash -c 'echo "en_US.UTF-8 UTF-8" > /etc/locale.gen'
    arch-chroot /mnt locale-gen
    arch-chroot /mnt bash -c 'echo "LANG=en_US.UTF-8" > /etc/locale.conf'
    
    # Set hostname
    arch-chroot /mnt bash -c 'echo "lobby-kiosk" > /etc/hostname'
    
    # Configure hosts file
    arch-chroot /mnt bash -c 'cat > /etc/hosts << EOF
127.0.0.1 localhost
::1       localhost
127.0.1.1 lobby-kiosk.localdomain lobby-kiosk
EOF'
    
    # Set root password
    arch-chroot /mnt bash -c "echo 'root:$ROOT_PASSWORD' | chpasswd"
    arch-chroot /mnt bash -c "echo 'Root password set' >> /var/log/install.log"
    
    # Install packages from list
    local package_list="/tmp/lobby-kiosk-config/configs/packages.txt"
    if [[ ! -f "$package_list" ]]; then
        error "Package list not found: $package_list"
    fi
    
    local packages=$(grep -v '^#' "$package_list" | grep -v '^$' | tr '\n' ' ')
    arch-chroot /mnt pacman -S --noconfirm $packages
    
    # Install and configure GRUB
    arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
    arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
    
    # Enable essential services
    arch-chroot /mnt systemctl enable NetworkManager
    arch-chroot /mnt systemctl enable sshd
}

# Configure kiosk system inside chroot (no heredocs!)
configure_kiosk_system() {
    log "Configuring kiosk system in chroot..."
    
    # Create lobby user
    arch-chroot /mnt useradd -m -s /bin/bash -G video,audio,wheel lobby
    arch-chroot /mnt bash -c "echo 'lobby:lobby' | chpasswd"
    
    # Create directories
    arch-chroot /mnt mkdir -p /opt/lobby/{app,config,logs,scripts,backups}
    arch-chroot /mnt mkdir -p /opt/lobby/app/{releases,shared}
    arch-chroot /mnt chown -R lobby:lobby /opt/lobby
    
    # Copy already downloaded config files into chroot
    log "Copying config files into chroot..."
    if [[ ! -d "/tmp/lobby-kiosk-config" ]]; then
        error "Config files not found at /tmp/lobby-kiosk-config - base system setup may have failed"
    fi
    
    # Debug: show what's in the host config directory
    log "Debug: Contents of host /tmp/lobby-kiosk-config:"
    ls -la /tmp/lobby-kiosk-config/configs/systemd/ || error "systemd configs not found on host"
    
    # Create target directory in chroot and copy files
    mkdir -p /mnt/tmp/lobby-kiosk-config
    cp -r /tmp/lobby-kiosk-config/* /mnt/tmp/lobby-kiosk-config/
    
    # Debug: show what's in the chroot config directory
    log "Debug: Contents of chroot /mnt/tmp/lobby-kiosk-config:"
    ls -la /mnt/tmp/lobby-kiosk-config/configs/systemd/ || error "systemd configs not found in chroot"
    
    # Install systemd services with explicit file names
    log "Installing lobby-kiosk.target..."
    arch-chroot /mnt cp /tmp/lobby-kiosk-config/configs/systemd/lobby-kiosk.target /etc/systemd/system/
    log "Installing lobby-app.service..."
    arch-chroot /mnt cp /tmp/lobby-kiosk-config/configs/systemd/lobby-app.service /etc/systemd/system/
    log "Installing lobby-display.service..."
    arch-chroot /mnt cp /tmp/lobby-kiosk-config/configs/systemd/lobby-display.service /etc/systemd/system/
    log "Installing lobby-watchdog.service..."
    arch-chroot /mnt cp /tmp/lobby-kiosk-config/configs/systemd/lobby-watchdog.service /etc/systemd/system/
    
    # Install nginx config
    arch-chroot /mnt cp /tmp/lobby-kiosk-config/configs/nginx/nginx.conf /etc/nginx/
    
    # Install font config
    arch-chroot /mnt mkdir -p /etc/fonts
    arch-chroot /mnt cp /tmp/lobby-kiosk-config/configs/fonts/local.conf /etc/fonts/
    
    # Install scripts with explicit file names
    arch-chroot /mnt cp /tmp/lobby-kiosk-config/scripts/build-app.sh /opt/lobby/scripts/
    arch-chroot /mnt cp /tmp/lobby-kiosk-config/scripts/chromium-kiosk.sh /opt/lobby/scripts/
    arch-chroot /mnt cp /tmp/lobby-kiosk-config/scripts/setup-display.sh /opt/lobby/scripts/
    arch-chroot /mnt cp /tmp/lobby-kiosk-config/scripts/watchdog.sh /opt/lobby/scripts/
    arch-chroot /mnt cp /tmp/lobby-kiosk-config/bin/lobby /usr/local/bin/
    
    # Cleanup
    arch-chroot /mnt rm -rf /tmp/lobby-kiosk-config
    
    # Set permissions
    arch-chroot /mnt chmod +x /opt/lobby/scripts/build-app.sh /opt/lobby/scripts/chromium-kiosk.sh /opt/lobby/scripts/setup-display.sh /opt/lobby/scripts/watchdog.sh /usr/local/bin/lobby
    arch-chroot /mnt chown -R lobby:lobby /opt/lobby/scripts
    
    # Configure autologin
    arch-chroot /mnt mkdir -p /etc/systemd/system/getty@tty1.service.d/
    arch-chroot /mnt bash -c 'cat > /etc/systemd/system/getty@tty1.service.d/override.conf << EOF
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin lobby --noclear %I \$TERM
EOF'
    
    # Configure sudo
    arch-chroot /mnt bash -c 'cat > /etc/sudoers.d/lobby << EOF
lobby ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart lobby-*.service
lobby ALL=(ALL) NOPASSWD: /usr/bin/systemctl reload nginx
lobby ALL=(ALL) NOPASSWD: /usr/bin/reboot
EOF'
    
    # Enable services
    arch-chroot /mnt systemctl daemon-reload
    arch-chroot /mnt systemctl enable lobby-kiosk.target
    arch-chroot /mnt systemctl enable sshd tailscaled
    arch-chroot /mnt systemctl set-default multi-user.target
    arch-chroot /mnt bash -c "systemctl disable bluetooth cups avahi-daemon 2>/dev/null || true"
    
    # Set version
    arch-chroot /mnt bash -c 'echo "2.0.0" > /opt/lobby/config/version'
    arch-chroot /mnt chown lobby:lobby /opt/lobby/config/version
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
        arch-chroot /mnt useradd -m -s /bin/bash -G video,audio,wheel "$KIOSK_USER"
        arch-chroot /mnt bash -c "echo '$KIOSK_USER:$KIOSK_USER' | chpasswd"
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
    log "Main function started with INSTALL_MODE: $INSTALL_MODE"
    if [[ $INSTALL_MODE == "system" ]]; then
        log "Installing complete lobby-kiosk system from scratch..."
        
        
        # Download config files first (needed for package list)
        log "Downloading configuration files..."
        cd /tmp
        rm -rf lobby-kiosk-config
        git clone https://github.com/kenzie/lobby-kiosk.git lobby-kiosk-config
        
        # Verify initial download worked
        if [[ ! -f "/tmp/lobby-kiosk-config/configs/systemd/lobby-kiosk.target" ]]; then
            error "Initial config download failed - lobby-kiosk.target not found"
        fi
        log "Initial config download successful"
        
        detect_disk
        setup_disk
        install_base_system
        
        # Continue installation in chroot
        configure_kiosk_system
        
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
log "Calling main function..."
main "$@"
log "Main function completed"